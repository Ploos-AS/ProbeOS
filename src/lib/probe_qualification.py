#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Central offline ProbeOS physical-qualification engine."""

import argparse
import copy
import datetime as dt
import hashlib
import html
import ipaddress
import json
import os
import platform
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

SCHEMA_VERSION = "1.0"
PROCEDURE_VERSION = "physical-qualification-v1"
STATUSES = ("PASS", "PARTIAL", "FAIL", "NOT_TESTED", "UNSUPPORTED", "ERROR")
SOURCES = ("probeos_runtime", "operator_observed", "qemu_ci", "imported_physical_bundle", "synthetic_fixture", "manual_early_boot")
FINGERPRINT_DOMAIN = b"ProbeOS physical machine fingerprint v1\0"
SENSITIVE_KEY = re.compile(r"(?:^|_)(?:serial|uuid|mac|product_key|recoverable_product_key|ip_address|address)(?:_|$)", re.I)
KEY_VALUE = re.compile(r"\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b")
MAC_VALUE = re.compile(r"\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b", re.I)
UUID_VALUE = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b", re.I)
CORE_RESULTS = ("bootloader", "kernel", "initramfs", "userspace", "services", "hardware_inventory", "diagnostics_execution")


def utcnow():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def atomic_json(path, value):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name("." + path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def normalize(value):
    return " ".join(str(value or "").strip().lower().split())


def redact_text(value):
    value = KEY_VALUE.sub("[redacted]", str(value))
    value = MAC_VALUE.sub("[redacted]", value)
    value = UUID_VALUE.sub("[redacted]", value)
    words = []
    for word in value.split():
        candidate = word.strip("[](),;\"")
        try:
            ipaddress.ip_address(candidate)
            word = word.replace(candidate, "[redacted]")
        except ValueError:
            pass
        words.append(word)
    return " ".join(words)


def redact(value):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            if key in ("qualification_id", "fingerprint", "sha256"):
                result[key] = item
            elif SENSITIVE_KEY.search(key) and item not in (None, "", []):
                result[key] = "[redacted]"
            else:
                result[key] = redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    return redact_text(value) if isinstance(value, str) else value


def fingerprint(report):
    """Hash stable identifiers; return only the digest, never its inputs."""
    system = report.get("system") or {}; board = report.get("motherboard") or {}
    inputs = [system.get("manufacturer"), system.get("model"), system.get("serial_number"), system.get("uuid"),
              board.get("manufacturer"), board.get("model"), board.get("serial_number")]
    cpus = report.get("cpu") or []
    inputs.append(cpus[0].get("model") if cpus else None)
    normalized = "\0".join(normalize(item) for item in inputs if normalize(item))
    if not normalized:
        normalized = "insufficient-stable-identifiers"
    return "sha256:" + hashlib.sha256(FINGERPRINT_DOMAIN + normalized.encode()).hexdigest()


def result(status, source="probeos_runtime", summary=None, **extra):
    value = {"status": status, "evidence_source": source}
    if summary: value["summary"] = summary
    value.update(extra)
    return value


def aggregate(results):
    """Compatibility aggregation; diagnostic health WARN is deliberately absent."""
    core = [results.get(name, {}).get("status", "NOT_TESTED") for name in CORE_RESULTS]
    if any(status == "ERROR" for status in core): return "ERROR"
    if any(status == "FAIL" for status in core): return "FAIL"
    if all(status == "UNSUPPORTED" for status in core): return "UNSUPPORTED"
    if all(status == "PASS" for status in core):
        relevant = [item.get("status") for name, item in results.items() if name not in CORE_RESULTS]
        return "PARTIAL" if any(status in ("FAIL", "ERROR", "PARTIAL") for status in relevant) else "PASS"
    if any(status in ("PASS", "PARTIAL") for status in core): return "PARTIAL"
    return "NOT_TESTED"


def qualification_level(results):
    if results.get("diagnostics_execution", {}).get("status") == "PASS": return "Diagnostics"
    if results.get("hardware_inventory", {}).get("status") == "PASS": return "Identification"
    if results.get("userspace", {}).get("status") == "PASS": return "Boot"
    return "None"


def identity(path):
    values = {}
    try:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1); values[key] = value.strip('"')
    except OSError:
        pass
    return values


def controller_summary(report, class_name):
    matches = []
    for item in report.get("pci") or []:
        label = " ".join(str(item.get(key) or "") for key in ("class", "description", "device"))
        if class_name in label.lower():
            matches.append({key: item.get(key) for key in ("description", "vendor_id", "device_id", "driver") if item.get(key) is not None})
    return matches


def detect_bootloader(release, cmdline):
    explicit = release.get("PROBEOS_BOOTLOADER") or os.environ.get("PROBEOS_BOOTLOADER")
    if explicit in ("grub", "syslinux"): return explicit, "build_identity"
    if "BOOT_IMAGE=" in cmdline and "isolinux" in cmdline.lower(): return "syslinux", "kernel_cmdline"
    return "unknown", "unavailable"


def validate_record(doc, allow_synthetic=True):
    errors = []
    required = ("schema_version", "procedure_version", "qualification_id", "environment_type", "provenance", "probeos", "artifact", "platform", "machine", "results", "overall_status", "operator_confirmation")
    for key in required:
        if key not in doc: errors.append("missing required field: " + key)
    if doc.get("schema_version") != SCHEMA_VERSION: errors.append("unsupported schema_version")
    if doc.get("procedure_version") != PROCEDURE_VERSION: errors.append("unsupported procedure_version")
    if doc.get("environment_type") not in ("physical", "emulator", "synthetic"): errors.append("invalid environment_type")
    if not allow_synthetic and doc.get("environment_type") != "physical": errors.append("reviewed physical evidence must have environment_type physical")
    if doc.get("provenance") not in SOURCES: errors.append("invalid provenance")
    try: uuid.UUID(doc.get("qualification_id", ""))
    except (ValueError, AttributeError): errors.append("invalid qualification_id")
    for name, item in (doc.get("results") or {}).items():
        if not isinstance(item, dict) or item.get("status") not in STATUSES: errors.append("invalid result status: " + name)
        if isinstance(item, dict) and item.get("evidence_source") not in SOURCES: errors.append("invalid evidence source: " + name)
    if doc.get("overall_status") not in STATUSES: errors.append("invalid overall_status")
    if doc.get("overall_status") != aggregate(doc.get("results") or {}): errors.append("overall_status does not match aggregation")
    serialized = json.dumps(doc, ensure_ascii=False)
    for pattern, label in ((KEY_VALUE, "product key"), (MAC_VALUE, "MAC address"), (UUID_VALUE, "raw UUID")):
        # qualification_id is a UUID, so inspect after removing that explicitly.
        inspected = serialized.replace(str(doc.get("qualification_id", "")), "")
        if pattern.search(inspected): errors.append("privacy violation: " + label)
    for key in ("serial_number", "system_uuid", "board_serial", "mac_address"):
        if re.search(r'"' + key + r'"\s*:\s*"(?!\[redacted\])[^\"]+"', serialized, re.I): errors.append("privacy violation: " + key)
    return errors


def create_record(args):
    report_path = Path(args.report_dir) / "report.json"
    diagnostics_path = Path(args.report_dir) / "diagnostics.json"
    if not report_path.exists() and not args.no_run:
        subprocess.run([args.identify, "--output-dir", args.report_dir], check=False, stdout=subprocess.DEVNULL)
    report = read_json(report_path) if report_path.exists() else {}
    if not diagnostics_path.exists() and not args.no_run:
        subprocess.run([args.diagnostics, "quick", "--report", str(report_path), "--output-dir", args.report_dir], check=False, stdout=subprocess.DEVNULL)
    diagnostics = read_json(diagnostics_path) if diagnostics_path.exists() else {}
    if args.benchmark_smoke:
        subprocess.run([args.benchmark, "run", "cpu", "--cpu-seconds", "2", "--output-dir", args.report_dir, "--report", str(report_path)], check=False, stdout=subprocess.DEVNULL)
    if args.stability_smoke:
        subprocess.run([args.benchmark, "stability", "--duration", "60", "--output-dir", args.report_dir, "--report", str(report_path)], check=False, stdout=subprocess.DEVNULL)
    benchmark_path = Path(args.report_dir) / "benchmarks.json"; stability_path = Path(args.report_dir) / "stability.json"
    benchmark = read_json(benchmark_path) if benchmark_path.exists() else {}; stability = read_json(stability_path) if stability_path.exists() else {}
    release = identity(args.release_file)
    cmdline = ""
    try: cmdline = Path(args.cmdline).read_text(encoding="utf-8")
    except OSError: pass
    bootloader, bootloader_source = detect_bootloader(release, cmdline)
    firmware = normalize((report.get("firmware") or {}).get("boot_mode")) or "unknown"
    architecture = release.get("PROBEOS_ARCHITECTURE") or platform.machine() or "unknown"
    system = report.get("system") or {}; board = report.get("motherboard") or {}; cpus = report.get("cpu") or []
    memory = report.get("memory") or {}
    timestamp = utcnow(); year = dt.datetime.now().year
    reliable = "trusted" if 2024 <= year <= 2100 else "uncertain"
    report_valid = report.get("schema_version") == "1.1"
    diagnostics_valid = diagnostics.get("schema_version") == "1.0"
    results = {
        "bootloader": result("PASS", summary="Operator reached the running ProbeOS instance.", detection=bootloader_source),
        "kernel": result("PASS", summary="Running kernel observed.", kernel=platform.release()),
        "initramfs": result("PASS", summary="Running diskless userspace implies initramfs completion."),
        "userspace": result("PASS", summary="ProbeOS userspace reached."),
        "services": result("PASS", summary="Qualification engine reached locally."),
        "tui": result("NOT_TESTED"), "report_generated": result("PASS" if report_path.exists() else "FAIL"),
        "hardware_inventory": result("PASS" if report_valid else "FAIL", schema_version=report.get("schema_version")),
        "diagnostics_execution": result("PASS" if diagnostics_valid else "FAIL", schema_version=diagnostics.get("schema_version")),
        "diagnostics_health": result("PASS" if diagnostics_valid else "NOT_TESTED", summary="Health result is not compatibility aggregation.", health_status=diagnostics.get("overall_status")),
        "networking": result("NOT_TESTED", summary="No DHCP environment was asserted."),
        "web_api": result("NOT_TESTED"), "console_display": result("NOT_TESTED"), "local_gui": result("NOT_TESTED"),
        "keyboard": result("NOT_TESTED"), "pointer": result("NOT_TESTED"),
        "storage_enumeration": result("PASS" if isinstance(report.get("storage"), list) else "ERROR", summary="Read-only inventory only; no storage writes performed."),
        "usb_enumeration": result("PASS" if isinstance(report.get("usb"), list) else "ERROR"),
        "memtest_startup": result("NOT_TESTED"), "memtest_completed": result("NOT_TESTED"),
        "benchmark_smoke": result("PASS" if args.benchmark_smoke and benchmark.get("schema_version") == "1.0" and any(item.get("category") == "cpu" and item.get("status") == "COMPLETED" for item in benchmark.get("results", [])) else "FAIL" if args.benchmark_smoke else "NOT_TESTED", summary="Qualification-only two-second CPU framework smoke; not a performance comparison." if args.benchmark_smoke else None),
        "stability_smoke": result("PASS" if args.stability_smoke and stability.get("schema_version") == "1.0" and str(stability.get("status", "")).startswith("COMPLETED") else "FAIL" if args.stability_smoke else "NOT_TESTED", summary="Qualification-only 60-second framework smoke; not evidence of long-term stability." if args.stability_smoke else None)
    }
    artifact_sha = args.iso_sha256 if re.fullmatch(r"[0-9a-fA-F]{64}", args.iso_sha256 or "") else None
    record = {
        "schema_version": SCHEMA_VERSION, "procedure_version": PROCEDURE_VERSION,
        "qualification_id": str(uuid.UUID(bytes=secrets.token_bytes(16), version=4)),
        "environment_type": args.environment, "provenance": "synthetic_fixture" if args.environment == "synthetic" else "qemu_ci" if args.environment == "emulator" else "probeos_runtime",
        "timestamp": timestamp, "timestamp_reliability": reliable,
        "probeos": {"version": release.get("PROBEOS_VERSION", "unknown"), "commit": release.get("PROBEOS_GIT_COMMIT", "unknown"), "build_channel": release.get("PROBEOS_BUILD_CHANNEL", "unknown"), "architecture": architecture},
        "artifact": {"identity": args.artifact_identity or release.get("PROBEOS_GIT_COMMIT", "unknown"), "iso_sha256": artifact_sha, "identity_strength": "iso_sha256" if artifact_sha else "embedded_build_identity", "limitation": None if artifact_sha else "The exact source-medium ISO checksum cannot be derived reliably from this running instance."},
        "platform": {"architecture": architecture, "bootloader": bootloader, "bootloader_detection": bootloader_source, "firmware_mode": firmware, "secure_boot_state": (report.get("firmware") or {}).get("secure_boot") or "unknown", "boot_medium": args.boot_medium},
        "machine": {"fingerprint": fingerprint(report), "fingerprint_version": "1", "manufacturer": system.get("manufacturer"), "model": system.get("model"), "board_manufacturer": board.get("manufacturer"), "board_model": board.get("model"), "cpu": cpus[0].get("model") if cpus else None, "cpu_architecture": architecture, "memory": {"total_bytes": memory.get("total_bytes"), "available_bytes": memory.get("available_bytes")}, "storage_controllers": controller_summary(report, "storage"), "graphics_controllers": copy.deepcopy(report.get("graphics") or []), "network_controllers": controller_summary(report, "network"), "usb_controllers": controller_summary(report, "usb"), "firmware": {key: (report.get("firmware") or {}).get(key) for key in ("vendor", "version", "date")}},
        "capabilities": {"pci_enumeration": isinstance(report.get("pci"), list), "usb_enumeration": isinstance(report.get("usb"), list), "storage_devices": len(report.get("storage") or []), "network_devices": len(report.get("network") or []), "graphics_devices": len(report.get("graphics") or [])},
        "results": results, "firmware_quirks": [], "operator_observations": {}, "operator_confirmation": {"confirmed": False, "confirmed_at": None},
        "notes": [], "failures": [], "skipped_tests": [name for name, value in results.items() if value["status"] == "NOT_TESTED"], "external_evidence_references": [],
        "document_links": {}, "privacy": {"mode": "share_safe", "raw_fingerprint_inputs_exported": False, "sensitive_identifiers_redacted": True}
    }
    for name in ("report.json", "diagnostics.json", "benchmarks.json", "stability.json"):
        path = Path(args.report_dir) / name
        if path.is_file(): record["document_links"][name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    record = redact(record)
    record["overall_status"] = aggregate(record["results"]); record["qualification_level"] = qualification_level(record["results"])
    return record


def update_record(path, args):
    doc = read_json(path)
    if args.action == "observe":
        doc.setdefault("operator_observations", {})[args.name] = {"status": args.status, "evidence_source": "operator_observed", "observed": True, "note": redact_text(args.note or "")}
        doc["results"][args.name] = result(args.status, "operator_observed", redact_text(args.note or "Operator confirmed."))
    elif args.action == "memtest":
        doc["results"]["memtest_startup"] = result(args.status, "operator_observed", redact_text(args.note or "Memtest startup recorded by operator."))
        if args.completed: doc["results"]["memtest_completed"] = result("PASS", "operator_observed", "Operator reported a completed test; startup and completion remain distinct fields.")
    elif args.action == "confirm":
        doc["operator_confirmation"] = {"confirmed": True, "confirmed_at": utcnow()}
    elif args.action == "note":
        doc.setdefault("notes", []).append(redact_text(args.note)[:1000])
    doc["skipped_tests"] = [name for name, value in doc["results"].items() if value["status"] == "NOT_TESTED"]
    doc["overall_status"] = aggregate(doc["results"]); doc["qualification_level"] = qualification_level(doc["results"])
    atomic_json(path, doc)


def render_text(doc):
    lines = ["ProbeOS Physical Qualification", "=" * 30, "", "Environment: " + doc["environment_type"].upper(),
             "Qualification ID: " + doc["qualification_id"], "ProbeOS: " + str(doc["probeos"].get("version")),
             "Architecture: " + str(doc["platform"].get("architecture")), "Bootloader: " + str(doc["platform"].get("bootloader")).upper(),
             "Firmware: " + str(doc["platform"].get("firmware_mode")).upper(), "Boot medium: " + str(doc["platform"].get("boot_medium")), ""]
    for name in sorted(doc["results"]):
        item = doc["results"][name]; lines.append(name.replace("_", " ").title() + ": " + item["status"] + ((" - " + item["summary"]) if item.get("summary") else ""))
    lines += ["", "Overall compatibility: " + doc["overall_status"], "Qualification level: " + doc.get("qualification_level", "None"), "", "Health findings are separate from ProbeOS compatibility."]
    return "\n".join(lines) + "\n"


def write_presentations(doc, directory):
    directory = Path(directory); text = render_text(doc)
    (directory / "qualification.txt").write_text(text, encoding="utf-8")
    body = "<pre>" + html.escape(text) + "</pre>"
    (directory / "qualification.html").write_text("<!doctype html><html><head><meta charset='utf-8'><title>ProbeOS Qualification</title></head><body><h1>ProbeOS Qualification</h1>" + body + "</body></html>\n", encoding="utf-8")


def export_bundle(record_path, destination, report_dir):
    doc = read_json(record_path); errors = validate_record(doc)
    if errors: raise ValueError("; ".join(errors))
    safe_id = doc["qualification_id"]
    destination = Path(destination)
    if destination.is_dir(): destination = destination / ("probeos-qualification-" + safe_id + ".tar.gz")
    with tempfile.TemporaryDirectory(prefix="probeos-qualification-") as temporary:
        root = Path(temporary); bundle_doc = redact(doc)
        source_report = Path(report_dir) / "report.json"
        if source_report.is_file() and source_report.stat().st_size <= 2 * 1024 * 1024:
            atomic_json(root / "hardware-report.json", redact(read_json(source_report)))
        for name in ("sale.json", "sale.txt", "sale.html", "diagnostics.json", "diagnostics.txt", "diagnostics.html", "benchmarks.json", "benchmarks.txt", "benchmarks.html", "stability.json", "stability.txt", "stability.html"):
            source = Path(report_dir) / name
            if source.is_file() and source.stat().st_size <= 2 * 1024 * 1024:
                if source.suffix == ".json": atomic_json(root / name, redact(read_json(source)))
                else: (root / name).write_text(redact_text(source.read_text(encoding="utf-8", errors="replace"))[:2 * 1024 * 1024], encoding="utf-8")
        bundle_doc["document_links"] = {}
        for name in ("hardware-report.json", "diagnostics.json", "benchmarks.json", "stability.json"):
            path = root / name
            if path.is_file(): bundle_doc["document_links"][name] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        atomic_json(root / "qualification.json", bundle_doc); write_presentations(bundle_doc, root)
        files = []
        for path in sorted(root.iterdir(), key=lambda item: item.name):
            if path.name in ("SHA256SUMS", "qualification-manifest.json"): continue
            digest = hashlib.sha256(path.read_bytes()).hexdigest(); files.append({"path": path.name, "sha256": digest, "size": path.stat().st_size})
        manifest = {"bundle_schema_version": "1.0", "procedure_version": PROCEDURE_VERSION, "qualification_id": safe_id, "probeos": doc["probeos"], "files": files}
        atomic_json(root / "qualification-manifest.json", manifest)
        all_hashes = [(hashlib.sha256(path.read_bytes()).hexdigest(), path.name) for path in sorted(root.iterdir(), key=lambda item: item.name) if path.name != "SHA256SUMS"]
        (root / "SHA256SUMS").write_text("".join(digest + "  " + name + "\n" for digest, name in all_hashes), encoding="utf-8")
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(destination, "w:gz", format=tarfile.PAX_FORMAT) as archive:
            for path in sorted(root.iterdir(), key=lambda item: item.name):
                info = archive.gettarinfo(str(path), path.name); info.uid = info.gid = 0; info.uname = info.gname = ""; info.mode = 0o600
                with open(path, "rb") as stream: archive.addfile(info, stream)
    return destination


def parser():
    value = argparse.ArgumentParser(description="Offline ProbeOS physical qualification")
    sub = value.add_subparsers(dest="action", required=True)
    start = sub.add_parser("start"); start.add_argument("--output-dir", default="/run/probeos"); start.add_argument("--report-dir", default="/run/probeos"); start.add_argument("--release-file", default=os.environ.get("PROBEOS_RELEASE_FILE", "/etc/probeos-release")); start.add_argument("--cmdline", default="/proc/cmdline"); start.add_argument("--identify", default="probe-identify"); start.add_argument("--diagnostics", default="probe-diagnostics"); start.add_argument("--benchmark", default="probe-benchmark"); start.add_argument("--benchmark-smoke", action="store_true"); start.add_argument("--stability-smoke", action="store_true"); start.add_argument("--environment", choices=("physical", "emulator", "synthetic"), default="physical"); start.add_argument("--boot-medium", choices=("optical", "usb", "virtual_cd", "virtual_disk", "other", "unknown"), default="unknown"); start.add_argument("--iso-sha256"); start.add_argument("--artifact-identity"); start.add_argument("--no-run", action="store_true")
    for action in ("observe", "memtest", "confirm", "note"):
        item = sub.add_parser(action); item.add_argument("--record", default="/run/probeos/qualification.json")
        if action == "observe": item.add_argument("name", choices=("boot_menu", "tui", "console_display", "local_gui", "keyboard", "pointer", "reboot", "poweroff", "networking", "web_api")); item.add_argument("status", choices=STATUSES); item.add_argument("--note")
        elif action == "memtest": item.add_argument("status", choices=STATUSES); item.add_argument("--completed", action="store_true"); item.add_argument("--note")
        elif action == "note": item.add_argument("note")
    status = sub.add_parser("status"); status.add_argument("--record", default="/run/probeos/qualification.json")
    validate = sub.add_parser("validate"); validate.add_argument("record")
    export = sub.add_parser("export"); export.add_argument("--record", default="/run/probeos/qualification.json"); export.add_argument("--report-dir", default="/run/probeos"); export.add_argument("destination")
    return value


def main():
    args = parser().parse_args()
    if args.action == "start":
        doc = create_record(args); output = Path(args.output_dir); output.mkdir(parents=True, exist_ok=True); atomic_json(output / "qualification.json", doc); write_presentations(doc, output); print(render_text(doc), end="")
    elif args.action in ("observe", "memtest", "confirm", "note"):
        update_record(args.record, args); doc = read_json(args.record); write_presentations(doc, Path(args.record).parent); print(render_text(doc), end="")
    elif args.action == "status": print(render_text(read_json(args.record)), end="")
    elif args.action == "validate":
        errors = validate_record(read_json(args.record)); print("\n".join(errors) if errors else "valid qualification record"); raise SystemExit(bool(errors))
    elif args.action == "export": print(export_bundle(args.record, args.destination, args.report_dir))


if __name__ == "__main__":
    main()
