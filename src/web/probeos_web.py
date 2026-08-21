#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Small report-backed ProbeOS web UI and read-only API.

The service deliberately uses only Python's standard library.  It never runs
hardware discovery: every response is derived from report.json/report.txt.
"""
import argparse
import html
import json
import os
import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

SECTIONS = (
    "system", "cpu", "memory", "firmware", "motherboard", "pci", "usb",
    "graphics", "storage", "network", "sensors", "power", "windows",
)
PAGE_TITLES = {"/": "Summary", **{"/" + name: name.title() for name in SECTIONS},
               "/benchmarks": "Benchmarks", "/export": "Export", "/about": "About"}
API_SECTIONS = {name: name for name in SECTIONS}
SENSITIVE = re.compile(r"(?:^|_)(?:serial|uuid|mac)(?:_|$)|^(?:serial|uuid)$", re.I)


def load_identity():
    values = {"product_version": "development", "build_channel": "development",
              "git_commit": "unknown", "architecture": "unknown"}
    path = os.environ.get("PROBEOS_RELEASE_FILE", "/etc/probeos-release")
    keys = {"PROBEOS_VERSION": "product_version", "PROBEOS_BUILD_CHANNEL": "build_channel",
            "PROBEOS_GIT_COMMIT": "git_commit", "PROBEOS_ARCHITECTURE": "architecture"}
    try:
        with open(path, "r", encoding="utf-8") as stream:
            for line in stream:
                key, separator, value = line.rstrip("\n").partition("=")
                if separator and key in keys:
                    values[keys[key]] = value
    except OSError:
        pass
    return values


def load_report(report_dir):
    path = os.path.join(report_dir, "report.json")
    try:
        with open(path, "r", encoding="utf-8") as stream:
            value = json.load(stream)
        if not isinstance(value, dict):
            raise ValueError("report root is not an object")
        return value, None
    except (OSError, ValueError, json.JSONDecodeError) as error:
        return None, str(error)


def redact(value):
    """Return a copy with identifiers hidden while retaining report shape."""
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if SENSITIVE.search(key) or key.lower() in ("mac_address", "address_uuid"):
                result[key] = "[redacted]" if item is not None else None
            else:
                result[key] = redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def json_bytes(value):
    return json.dumps(value, indent=2, sort_keys=False, ensure_ascii=False).encode("utf-8")


class ProbeOSHandler(BaseHTTPRequestHandler):
    server_version = "ProbeOSWeb/1.0"

    def log_message(self, fmt, *args):
        if os.environ.get("PROBEOS_WEB_QUIET") != "1":
            super().log_message(fmt, *args)

    @property
    def report_dir(self):
        return self.server.report_dir

    def full_view_allowed(self, query):
        # Full identifiers are a deliberate local-only diagnostic view.  The
        # normal UI/API never links to or returns them to LAN clients.
        return query.get("privacy", ["redacted"])[0] == "full" and self.client_address[0] in ("127.0.0.1", "::1")

    def report_view(self, query):
        report, error = load_report(self.report_dir)
        if report is None:
            return None, error
        return report if self.full_view_allowed(query) else redact(report), None

    def send_bytes(self, payload, content_type, status=HTTPStatus.OK):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def send_json(self, value, status=HTTPStatus.OK):
        self.send_bytes(json_bytes(value), "application/json; charset=utf-8", status)

    def do_GET(self):  # noqa: N802 - stdlib handler API
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)
        if path == "/api/v1/health":
            report, _ = load_report(self.report_dir)
            generated = report.get("probeos", {}).get("generated_at") if report else None
            self.send_json({"service": "running", "api_version": "1", **load_identity(), "report_available": report is not None,
                            "report_generated_at": generated})
            return
        if path.startswith("/api/v1"):
            self.api(path, query)
            return
        self.page(path, query)

    def api(self, path, query):
        suffix = path[len("/api/v1"):].rstrip("/") or "/health"
        report, error = self.report_view(query)
        if report is None:
            self.send_json({"error": "report_unavailable", "detail": error}, HTTPStatus.SERVICE_UNAVAILABLE)
            return
        if suffix == "/report":
            self.send_json(report)
            return
        section = suffix.lstrip("/")
        if section in API_SECTIONS:
            self.send_json(report.get(API_SECTIONS[section]))
            return
        self.send_json({"error": "not_found", "path": path}, HTTPStatus.NOT_FOUND)

    def page(self, path, query):
        if path not in PAGE_TITLES:
            self.send_html("Not found", "<p>Page not found.</p>", HTTPStatus.NOT_FOUND)
            return
        report, error = self.report_view(query)
        if path == "/about":
            identity = load_identity()
            body = "<p>ProbeOS " + html.escape(identity["product_version"]) + " (" + html.escape(identity["build_channel"]) + " build)</p>"
            body += "<p>Commit: " + html.escape(identity["git_commit"]) + "; architecture: " + html.escape(identity["architecture"]) + ".</p>"
            body += "<p>ProbeOS is an offline-first hardware inspection environment.</p>"
            body += "<p>This interface reads the authoritative probe-identify report; it does not run a probe per request.</p>"
        elif path == "/benchmarks":
            body = "<p>Benchmark execution is intentionally not available from the unauthenticated web/API layer.</p>"
            body += "<p>Use the local TUI for explicit, interactive benchmark confirmation.</p>"
        elif path == "/export":
            if report is None:
                body = "<p>Report unavailable: " + html.escape(error or "unknown error") + "</p>"
            else:
                body = "<p>Redacted JSON export:</p><pre>" + html.escape(json.dumps(report, indent=2, ensure_ascii=False)) + "</pre>"
        elif report is None:
            body = "<p>Report unavailable: " + html.escape(error or "unknown error") + "</p>"
        elif path == "/":
            generated = report.get("probeos", {}).get("generated_at", "unknown")
            body = "<p>Generated: " + html.escape(str(generated)) + "</p>"
            body += "<p>Schema: " + html.escape(str(report.get("schema_version", "unknown"))) + "</p>"
            body += "<ul>" + "".join("<li><a href='" + name + "'>" + html.escape(title) + "</a></li>"
                                      for name, title in PAGE_TITLES.items() if name not in ("/", "/about", "/benchmarks", "/export")) + "</ul>"
            body += "<p><a href='/api/v1/report'>JSON API report</a> · <a href='/export'>Export</a></p>"
        else:
            section = path.lstrip("/")
            body = "<pre>" + html.escape(json.dumps(report.get(section), indent=2, ensure_ascii=False)) + "</pre>"
            body += "<p>API: <a href='/api/v1/" + html.escape(section) + "'>/api/v1/" + html.escape(section) + "</a></p>"
        self.send_html(PAGE_TITLES[path], body)

    def send_html(self, title, body, status=HTTPStatus.OK):
        # Deliberately plain HTML/CSS: useful with CSS disabled and old browsers.
        nav = " | ".join("<a href='" + path + "'>" + html.escape(label) + "</a>" for path, label in PAGE_TITLES.items())
        document = "<!DOCTYPE html><html><head><meta charset='utf-8'><title>ProbeOS - " + html.escape(title) + "</title>"
        document += "<style>body{font-family:Arial,sans-serif;max-width:1000px;margin:1em auto;padding:0 1em;color:#222}a{color:#0645ad}pre{white-space:pre-wrap;word-wrap:break-word;background:#f4f4f4;padding:1em;border:1px solid #ccc}nav{line-height:2}</style></head>"
        document += "<body><h1>ProbeOS</h1><nav>" + nav + "</nav><hr><h2>" + html.escape(title) + "</h2>" + body + "</body></html>"
        self.send_bytes(document.encode("utf-8"), "text/html; charset=utf-8", status)


def main():
    parser = argparse.ArgumentParser(description="ProbeOS report web service")
    parser.add_argument("--bind", default=os.environ.get("PROBEOS_WEB_BIND", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("PROBEOS_WEB_PORT", "8080")))
    parser.add_argument("--report-dir", default=os.environ.get("PROBEOS_REPORT_DIR", "/run/probeos"))
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.bind, args.port), ProbeOSHandler)
    server.report_dir = args.report_dir
    print("ProbeOS Web UI listening on http://%s:%d/" % (args.bind, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
