#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render privacy-safe ProbeOS report profiles from authoritative report.json."""
import argparse
import copy
import html
import json
from pathlib import Path

SENSITIVE_IDENTIFIERS = ("serial", "uuid", "mac_address")


def redact(value):
    if isinstance(value, dict):
        result = {}
        for name, item in value.items():
            low = name.lower()
            if any(token in low for token in SENSITIVE_IDENTIFIERS) or low in ("key", "product_key", "recoverable_product_key"):
                result[name] = "[redacted]" if item is not None else None
            else:
                result[name] = redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def compact(value):
    return {key: item for key, item in value.items() if item not in (None, "", [], {})}


def bytes_size(value):
    if not isinstance(value, (int, float)):
        return None
    units = ("B", "KB", "MB", "GB", "TB", "PB")
    size = float(value)
    unit = units[0]
    for unit in units:
        if size < 1000 or unit == units[-1]:
            break
        size /= 1000
    return ("%.1f" % size).rstrip("0").rstrip(".") + " " + unit


def storage_type(disk):
    transport = str(disk.get("transport") or "").lower()
    if transport == "nvme":
        return "NVMe SSD"
    if disk.get("rotational") is False:
        return (transport.upper() + " SSD").strip()
    if disk.get("rotational") is True:
        return (transport.upper() + " HDD").strip()
    return transport.upper() or None


def battery(item):
    design = item.get("design_capacity") or item.get("energy_full_design")
    full = item.get("full_charge_capacity") or item.get("energy_full")
    def capacity(value):
        return (("%.1f" % (value / 1000000)).rstrip("0").rstrip(".") + " Wh") if isinstance(value, (int, float)) else value
    result = compact({"name": item.get("name"), "status": item.get("status"),
                      "charge_percent": item.get("capacity_percent"), "design_capacity": capacity(design),
                      "full_charge_capacity": capacity(full), "cycle_count": item.get("cycle_count")})
    if isinstance(design, (int, float)) and design and isinstance(full, (int, float)):
        result["health_percent"] = round(full * 100 / design)
    return result


def diagnostic_summary(diagnostics):
    if not diagnostics:
        return {"status": "Not run"}
    return compact({"status": diagnostics.get("overall_status", "UNKNOWN"),
                    "categories": diagnostics.get("category_summary") or {}})


def sale(report, diagnostics=None):
    cpus = report.get("cpu") or []
    cpu = cpus[0] if cpus else {}
    dimms = (report.get("memory") or {}).get("dimms") or []
    memory_types = sorted({str(x["type"]) for x in dimms if x.get("type") not in (None, "Unknown")})
    speeds = sorted({str(x["configured_speed"]) for x in dimms if x.get("configured_speed") not in (None, "Unknown")})
    graphics = [compact({"model": x.get("description"), "driver": x.get("driver")}) for x in report.get("graphics") or []]
    disks = [compact({"model": x.get("model"), "type": storage_type(x),
                      "capacity": bytes_size(x.get("capacity_bytes"))})
             for x in report.get("storage") or []]
    pci_network = [x for x in report.get("pci") or [] if "network" in str(x.get("class", "")).lower() or
                   "ethernet" in str(x.get("class", "")).lower()]
    networks = [compact({"adapter": x.get("description"), "kind": "Wi-Fi" if "wireless" in str(x.get("description", "")).lower() else "Ethernet"}) for x in pci_network]
    if not networks:
        networks = [compact({"adapter": x.get("controller") or x.get("interface"),
                             "kind": "Wi-Fi" if str(x.get("interface", "")).startswith("wl") else "Ethernet"})
                    for x in report.get("network") or [] if x.get("interface") != "lo"]
    windows = []
    for item in (report.get("windows") or {}).get("installations") or []:
        windows.append(compact({"name": item.get("product_name"), "edition": item.get("edition"),
                                "version": item.get("version"), "build": item.get("build"),
                                "architecture": item.get("architecture"),
                                "recoverable_key": item.get("recoverable_key_status")}))
    firmware_license = (report.get("windows") or {}).get("firmware_license") or {}
    return compact({
        "profile": "sale", "generated_at": (report.get("probeos") or {}).get("generated_at"),
        "system": compact({"manufacturer": (report.get("system") or {}).get("manufacturer"),
                           "model": (report.get("system") or {}).get("product"),
                           "family": (report.get("system") or {}).get("version")}),
        "processor": compact({"model": cpu.get("model"), "physical_cores": cpu.get("cores"),
                              "logical_threads": cpu.get("threads"), "max_mhz": cpu.get("max_mhz")}),
        "memory": compact({"total": bytes_size((report.get("memory") or {}).get("total_usable_bytes")),
                           "technology": ", ".join(memory_types) or None,
                           "modules": [x.get("capacity") for x in dimms if x.get("capacity")],
                           "configured_speed": ", ".join(speeds) or None}),
        "graphics": graphics, "storage": disks, "network": networks,
        "firmware": compact({"boot_mode": (report.get("firmware") or {}).get("boot_mode"),
                             "vendor": (report.get("firmware") or {}).get("vendor"),
                             "version": (report.get("firmware") or {}).get("version")}),
        "windows": compact({"installations": windows,
                            "firmware_oem_license": "Found" if firmware_license.get("oem_key_found") else "Not found",
                            "other_recoverable_key": "Found" if any(x.get("recoverable_key_status") == "found" for x in (report.get("windows") or {}).get("installations") or []) else "Not established"}),
        "batteries": [battery(x) for x in (report.get("power") or {}).get("supplies") or [] if x.get("type") == "Battery"],
        "hardware_check": diagnostic_summary(diagnostics),
        "privacy": "Public-facing profile; sensitive identifiers and product keys are excluded.",
    })


def text_value(value):
    if isinstance(value, bool):
        return "Yes" if value else "No"
    return str(value)


def sale_text(model):
    names = {"system": "System", "processor": "Processor", "memory": "Memory", "graphics": "Graphics",
             "storage": "Storage", "network": "Network", "firmware": "Firmware", "windows": "Windows", "batteries": "Battery",
             "hardware_check": "Hardware Check"}
    lines = ["ProbeOS System Report", "=====================", "", "Profile: Sale (privacy-safe)"]
    for key, title in names.items():
        value = model.get(key)
        if not value:
            continue
        lines += ["", title, "-" * len(title)]
        items = value if isinstance(value, list) else [value]
        for index, item in enumerate(items, 1):
            if len(items) > 1:
                lines.append("  %s %d" % (title.rstrip("s"), index))
            if isinstance(item, dict):
                for name, field in item.items():
                    if key == "hardware_check" and name == "status":
                        lines.append("  Overall: " + text_value(field))
                        continue
                    if key == "hardware_check" and name == "categories" and isinstance(field, dict):
                        for category, category_status in field.items():
                            lines.append("  %s: %s" % (category.title(), text_value(category_status)))
                        continue
                    if isinstance(field, list) and field and all(isinstance(entry, dict) for entry in field):
                        lines.append("  %s:" % name.replace("_", " ").title())
                        for number, entry in enumerate(field, 1):
                            lines.append("    Installation %d" % number)
                            for entry_name, entry_value in entry.items():
                                lines.append("      %s: %s" % (entry_name.replace("_", " ").title(), text_value(entry_value)))
                        continue
                    if isinstance(field, list):
                        field = " + ".join(map(str, field))
                    if isinstance(field, dict):
                        field = json.dumps(field, ensure_ascii=False)
                    lines.append("  %s: %s" % (name.replace("_", " ").title(), text_value(field)))
            else:
                lines.append("  " + text_value(item))
    lines += ["", "Privacy", "-------", "  " + model["privacy"]]
    return "\n".join(lines) + "\n"


def technical_text(report, profile, diagnostics=None):
    safe = redact(copy.deepcopy(report))
    sections = ("system", "cpu", "memory", "firmware", "motherboard", "graphics", "storage", "network", "power", "windows")
    if profile == "full":
        sections += ("pci", "usb", "sensors")
    lines = ["ProbeOS %s Report" % profile.title(), "=" * (15 + len(profile)), "",
             "Sensitive identifiers and Windows product keys are redacted."]
    for section in sections:
        lines += ["", section.upper(), json.dumps(safe.get(section), indent=2, ensure_ascii=False)]
    lines += ["", "DIAGNOSTICS", json.dumps(redact(diagnostics), indent=2, ensure_ascii=False) if diagnostics else "Not run"]
    return "\n".join(lines) + "\n"


def sale_html(model):
    body = []
    for section in ("system", "processor", "memory", "graphics", "storage", "network", "firmware", "windows", "batteries", "hardware_check"):
        value = model.get(section)
        if not value:
            continue
        body.append("<section><h2>%s</h2>" % html.escape(section.title()))
        items = value if isinstance(value, list) else [value]
        for item in items:
            if isinstance(item, dict):
                body.append("<dl>")
                for key, field in item.items():
                    if isinstance(field, (list, dict)):
                        field = ", ".join(map(str, field)) if isinstance(field, list) else json.dumps(field, ensure_ascii=False)
                    body.append("<dt>%s</dt><dd>%s</dd>" % (html.escape(key.replace("_", " ").title()), html.escape(text_value(field))))
                body.append("</dl>")
            else:
                body.append("<p>%s</p>" % html.escape(text_value(item)))
        body.append("</section>")
    return """<!doctype html><html><head><meta charset="utf-8"><title>ProbeOS System Report</title>
<style>body{font-family:Arial,sans-serif;max-width:850px;margin:2em auto;padding:0 1.5em;color:#20252a}header{border-bottom:3px solid #315b7d}h1{margin-bottom:.2em}h2{color:#315b7d;border-bottom:1px solid #bbb;padding-bottom:.2em}dl{display:grid;grid-template-columns:minmax(10em,1fr) 2fr;gap:.35em 1em}dt{font-weight:bold}dd{margin:0}@media print{body{margin:0}section{break-inside:avoid}}</style></head><body><header><h1>ProbeOS System Report</h1><p>Sale profile · privacy-safe specification sheet</p></header>%s<footer><hr><small>%s</small></footer></body></html>""" % ("".join(body), html.escape(model["privacy"]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("output_dir")
    args = parser.parse_args()
    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    out = Path(args.output_dir)
    try:
        diagnostics = json.loads((out / "diagnostics.json").read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        diagnostics = None
    model = sale(report, diagnostics)
    safe = redact(copy.deepcopy(report))
    safe["report_profile"] = "detailed"
    safe["diagnostics"] = redact(diagnostics) if diagnostics else {"status": "not_run"}
    full = redact(copy.deepcopy(report))
    full["report_profile"] = "full"
    full["diagnostics"] = redact(diagnostics) if diagnostics else {"status": "not_run"}
    files = {"sale.json": json.dumps(model, indent=2, ensure_ascii=False) + "\n", "sale.txt": sale_text(model),
             "sale.html": sale_html(model), "detailed.json": json.dumps(safe, indent=2, ensure_ascii=False) + "\n",
             "detailed.txt": technical_text(report, "detailed", diagnostics), "full.json": json.dumps(full, indent=2, ensure_ascii=False) + "\n",
             "full.txt": technical_text(report, "full", diagnostics)}
    for name, content in files.items():
        (out / (name + ".tmp")).write_text(content, encoding="utf-8")
        (out / (name + ".tmp")).replace(out / name)


if __name__ == "__main__":
    main()
