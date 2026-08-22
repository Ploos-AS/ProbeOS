#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Authoritative ProbeOS diagnostics engine.

The latest result set is intentionally separate from hardware schema 1.1.
Checks return evidence, never arbitrary health scores, and fixture data passes
through the same interpretation functions as live data.
"""
import argparse
import datetime as dt
import html
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

SCHEMA_VERSION = "1.0"
STATUSES = ("PASS", "WARN", "FAIL", "UNKNOWN", "SKIPPED", "ERROR")
SAFETY_CLASSES = ("passive", "safe_active", "stress", "destructive")
CATEGORIES = ("system", "cpu", "memory", "storage", "network", "thermal",
              "battery", "firmware", "pci", "usb", "graphics")
CHECK_REGISTRY = (
    ("system.inventory", "system", "passive"), ("firmware.metadata", "firmware", "passive"),
    ("cpu.topology", "cpu", "passive"), ("memory.configuration", "memory", "passive"),
    ("storage.health", "storage", "passive"), ("network.interfaces", "network", "passive"),
    ("thermal.sensors", "thermal", "passive"), ("battery.capacity", "battery", "passive"),
    ("pci.enumeration", "pci", "passive"), ("usb.enumeration", "usb", "passive"),
    ("graphics.enumeration", "graphics", "passive"), ("system.kernel_signals", "system", "passive"),
    ("cpu.active", "cpu", "stress"), ("memory.userspace", "memory", "safe_active"),
    ("storage.read", "storage", "safe_active"),
)
DEFAULT_TIMEOUT = 20
SENSITIVE = re.compile(r"(?:serial|uuid|mac_address|product_key|windows.*key)", re.I)


def utcnow():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def safe_evidence(value):
    if isinstance(value, dict):
        return {key: ("[redacted]" if SENSITIVE.search(key) and item is not None else safe_evidence(item))
                for key, item in value.items()}
    if isinstance(value, list):
        return [safe_evidence(item) for item in value]
    return value


def result(check_id, category, name, status, summary, evidence=None, severity=None,
           safety_class="passive", duration_ms=0, requires_user_action=False,
           unavailable_reason=None):
    if status not in STATUSES:
        raise ValueError("invalid diagnostic status: " + status)
    if category not in CATEGORIES or safety_class not in SAFETY_CLASSES:
        raise ValueError("invalid diagnostic metadata")
    if severity is None:
        severity = {"PASS": "info", "WARN": "warning", "FAIL": "critical",
                    "UNKNOWN": "info", "SKIPPED": "info", "ERROR": "error"}[status]
    value = {"id": check_id, "category": category, "name": name, "status": status,
             "severity": severity, "summary": summary, "evidence": safe_evidence(evidence or {}),
             "timestamp": utcnow(), "duration_ms": max(0, int(duration_ms)),
             "safety_class": safety_class, "destructive": safety_class == "destructive",
             "requires_user_action": bool(requires_user_action)}
    if unavailable_reason:
        value["unavailable_reason"] = unavailable_reason
    return value


def aggregate(results):
    statuses = [item["status"] for item in results]
    if "FAIL" in statuses:
        return "FAIL"
    if "WARN" in statuses:
        return "WARN"
    if "ERROR" in statuses:
        return "ERROR"
    if statuses and all(item in ("PASS", "SKIPPED") for item in statuses) and "PASS" in statuses:
        return "PASS"
    return "UNKNOWN"


def category_summary(results):
    return {category: aggregate([item for item in results if item["category"] == category])
            for category in CATEGORIES if any(item["category"] == category for item in results)}


class Source:
    """Fixture-aware bounded data source; commands never use a shell."""
    def __init__(self, fixture_dir=None, timeout=DEFAULT_TIMEOUT):
        self.fixture_dir = Path(fixture_dir) if fixture_dir else None
        self.timeout = timeout

    def fixture_json(self, name, default=None):
        if not self.fixture_dir:
            return default
        path = self.fixture_dir / name
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return default

    def text(self, fixture, command=None):
        if self.fixture_dir:
            try:
                return (self.fixture_dir / fixture).read_text(encoding="utf-8"), None
            except OSError:
                return "", "fixture unavailable: " + fixture
        if not command:
            return "", "source unavailable"
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=self.timeout,
                                 check=False, stdin=subprocess.DEVNULL)
            if run.returncode != 0 and not run.stdout:
                return run.stderr.strip(), "command exited %d" % run.returncode
            return run.stdout, None
        except FileNotFoundError:
            return "", "command unavailable: " + command[0]
        except subprocess.TimeoutExpired:
            return "", "command timed out after %d seconds" % self.timeout

    def report(self, report_path):
        fixture_path = self.fixture_dir / "report.json" if self.fixture_dir else None
        path = fixture_path if fixture_path and fixture_path.is_file() else Path(report_path)
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError):
            return {}


def check_system(source, report):
    system = report.get("system") or {}
    present = [system.get(key) for key in ("manufacturer", "product")]
    if not report:
        return result("system.inventory", "system", "System inventory", "UNKNOWN",
                      "Hardware inventory is unavailable.", unavailable_reason="report.json unavailable")
    status = "PASS" if any(present) else "WARN"
    summary = "System identity metadata is available." if status == "PASS" else "System identity metadata is incomplete."
    return result("system.inventory", "system", "System inventory", status, summary,
                  {"identity_fields_present": sum(value is not None for value in present), "architecture": (report.get("probeos") or {}).get("architecture")})


def check_firmware(source, report):
    fw = report.get("firmware") or {}
    if not fw:
        return result("firmware.metadata", "firmware", "Firmware metadata", "UNKNOWN",
                      "Firmware metadata could not be read.", unavailable_reason="firmware inventory unavailable")
    fields = {key: fw.get(key) for key in ("vendor", "version", "release_date", "boot_mode", "secure_boot")}
    missing = [key for key in ("vendor", "version", "release_date") if not fields[key]]
    acpi = (fw.get("acpi") or {}).get("status")
    smbios = (fw.get("smbios") or {}).get("status")
    status = "PASS" if not missing and (smbios in (None, "ok")) else "WARN"
    summary = "Firmware identity and boot-mode metadata are available." if status == "PASS" else "Some firmware metadata is unavailable."
    return result("firmware.metadata", "firmware", "Firmware and ACPI", status, summary,
                  {"boot_mode": fields["boot_mode"], "secure_boot": fields["secure_boot"],
                   "firmware_fields_missing": missing, "acpi_access": acpi, "smbios_access": smbios})


def check_cpu(source, report):
    cpus = report.get("cpu") or []
    if not cpus:
        return result("cpu.topology", "cpu", "CPU topology", "UNKNOWN", "CPU topology is unavailable.",
                      unavailable_reason="CPU inventory unavailable")
    cpu = cpus[0]
    expected = None
    try:
        sockets, cores, threads_per_core = (int(cpu.get(key) or 0) for key in ("sockets", "cores_per_socket", "threads_per_core"))
        expected = sockets * cores * threads_per_core or None
        visible = int(cpu.get("threads") or 0)
    except (TypeError, ValueError):
        visible = 0
    online_text, _ = source.text("cpu_online", ["cat", "/sys/devices/system/cpu/online"])
    flags = str(cpu.get("flags") or "").split()
    evidence = {"architecture": cpu.get("architecture"), "logical_cpus_reported": visible or None,
                "logical_cpus_expected": expected, "online_cpu_range": online_text.strip() or None,
                "virtualization": cpu.get("virtualization"), "capability_count": len(flags)}
    if expected and visible and expected != visible:
        return result("cpu.topology", "cpu", "CPU topology", "WARN", "Reported CPU topology is inconsistent.", evidence)
    if not visible or not cpu.get("architecture"):
        return result("cpu.topology", "cpu", "CPU topology", "WARN", "CPU topology metadata is incomplete.", evidence)
    return result("cpu.topology", "cpu", "CPU topology", "PASS", "CPU topology and capabilities are consistently visible.", evidence)


def check_memory(source, report):
    memory = report.get("memory") or {}
    total = memory.get("total_usable_bytes")
    slots = memory.get("slots") or {}
    dimms = memory.get("dimms") or []
    evidence = {"total_usable_bytes": total, "slots_total": slots.get("total"),
                "slots_populated": slots.get("populated"), "dimms_reported": len(dimms),
                "ecc_exposed": any("ecc" in json.dumps(item).lower() for item in dimms)}
    if not total:
        return result("memory.configuration", "memory", "Memory configuration", "UNKNOWN",
                      "Usable memory could not be determined.", evidence, unavailable_reason="memory inventory unavailable")
    if slots.get("populated") is not None and dimms and int(slots["populated"]) != len(dimms):
        return result("memory.configuration", "memory", "Memory configuration", "WARN",
                      "DIMM inventory and populated-slot count differ.", evidence)
    return result("memory.configuration", "memory", "Memory configuration", "PASS",
                  "Usable memory and configuration are visible; this is not a full RAM test.", evidence)


def storage_interpret(device, smart):
    evidence = {key: smart.get(key) for key in ("device_type", "smart_passed", "critical_warning",
                "media_errors", "percentage_used", "available_spare", "temperature_celsius",
                "power_on_hours", "reallocated_sectors", "pending_sectors", "uncorrectable_sectors")}
    serious = []
    if smart.get("smart_passed") is False:
        serious.append("SMART overall health reports failure")
    warning = smart.get("critical_warning")
    if isinstance(warning, str):
        try: warning = int(warning, 0)
        except ValueError: warning = None
    if isinstance(warning, (int, float)) and warning != 0:
        serious.append("NVMe critical warning is non-zero")
    def number(value):
        if isinstance(value, (int, float)): return value
        match = re.match(r"\s*(\d+)", str(value or ""))
        return int(match.group(1)) if match else 0
    if number(smart.get("media_errors")) > 0 or number(smart.get("uncorrectable_sectors")) > 0:
        serious.append("uncorrectable or media errors are reported")
    if serious:
        return "FAIL", "; ".join(serious) + ".", evidence
    concerns = []
    if number(smart.get("pending_sectors")) > 0:
        concerns.append("%s pending sectors" % smart["pending_sectors"])
    if number(smart.get("reallocated_sectors")) > 0:
        concerns.append("%s reallocated sectors" % smart["reallocated_sectors"])
    if isinstance(smart.get("percentage_used"), (int, float)) and smart["percentage_used"] >= 90:
        concerns.append("NVMe percentage used is %s%%" % smart["percentage_used"])
    limit = smart.get("temperature_limit_celsius")
    temp = smart.get("temperature_celsius")
    if isinstance(limit, (int, float)) and isinstance(temp, (int, float)) and temp >= limit:
        concerns.append("temperature meets or exceeds the reported limit")
    if concerns:
        return "WARN", "; ".join(concerns) + ".", evidence
    supported = smart.get("smart_supported")
    if supported is False or not any(smart.get(key) is not None for key in ("smart_passed", "critical_warning")):
        return "WARN", "A supported health interface did not provide an overall state.", evidence
    return "PASS", "No failing SMART/NVMe indicators were found.", evidence


def smart_normalize(raw):
    if not isinstance(raw, dict):
        return {}
    nvme = raw.get("nvme_smart_health_information_log") or {}
    temp = nvme.get("temperature")
    if isinstance(temp, (int, float)) and temp > 200:
        temp -= 273
    attrs = ((raw.get("ata_smart_attributes") or {}).get("table") or [])
    by_name = {str(item.get("name", "")).lower(): item.get("raw", {}).get("value") for item in attrs}
    temperature = next((value for key, value in by_name.items() if "temperature" in key and isinstance(value, (int, float))), None)
    return {"device_type": "nvme" if nvme else "ata", "smart_supported": (raw.get("smart_support") or {}).get("available"),
            "smart_passed": (raw.get("smart_status") or {}).get("passed"),
            "critical_warning": nvme.get("critical_warning"), "media_errors": nvme.get("media_errors"),
            "percentage_used": nvme.get("percentage_used"), "available_spare": nvme.get("available_spare"),
            "temperature_celsius": temp if temp is not None else temperature,
            "power_on_hours": nvme.get("power_on_hours"),
            "reallocated_sectors": by_name.get("reallocated_sector_ct", 0),
            "pending_sectors": by_name.get("current_pending_sector", 0),
            "uncorrectable_sectors": by_name.get("offline_uncorrectable", 0)}


def check_storage(source, report):
    disks = report.get("storage") or []
    if not disks:
        return [result("storage.inventory", "storage", "Storage health", "UNKNOWN", "No physical storage devices were detected.",
                       unavailable_reason="no storage devices")]
    output = []
    for index, disk in enumerate(disks):
        device = disk.get("device") or "disk-%d" % index
        fixture = "smartctl.%s.json" % Path(device).name
        text, reason = source.text(fixture, ["smartctl", "-a", "-j", device])
        try:
            normalized = smart_normalize(json.loads(text))
        except (ValueError, TypeError):
            normalized = {"smart_supported": (disk.get("smart") or {}).get("capable"),
                          "smart_passed": (disk.get("smart") or {}).get("status")}
        status, summary, evidence = storage_interpret(device, normalized)
        evidence.update({"device": device, "model": disk.get("model"), "transport": disk.get("transport")})
        output.append(result("storage.health.%s" % re.sub(r"[^a-z0-9]+", "_", Path(device).name.lower()),
                             "storage", "Storage health: " + Path(device).name, status, summary, evidence,
                             unavailable_reason=reason if status in ("UNKNOWN", "WARN") else None))
    return output


def check_network(source, report):
    interfaces = [item for item in report.get("network") or [] if item.get("interface") != "lo"]
    if not interfaces:
        return result("network.interfaces", "network", "Network interfaces", "UNKNOWN", "No non-loopback network interface was detected.",
                      unavailable_reason="no network interface")
    addresses_text, _ = source.text("ip_addr.json", ["ip", "-j", "addr", "show"])
    routes_text, _ = source.text("ip_route.json", ["ip", "-j", "route", "show"])
    try: address_data = json.loads(addresses_text)
    except ValueError: address_data = []
    try: route_data = json.loads(routes_text)
    except ValueError: route_data = []
    address_map = {item.get("ifname"): [entry.get("local") for entry in item.get("addr_info", []) if entry.get("family") in ("inet", "inet6")]
                   for item in address_data if isinstance(item, dict)}
    gateways = {item.get("dev"): item.get("gateway") for item in route_data if isinstance(item, dict) and item.get("dst") == "default"}
    evidence = []
    active = False
    for item in interfaces:
        state = str(item.get("state") or "unknown").lower()
        active |= state == "up"
        evidence.append({"interface": item.get("interface"), "driver": item.get("driver"), "state": state,
                         "carrier": item.get("carrier"), "speed": (item.get("link_capability") or {}).get("speed"),
                         "duplex": item.get("duplex"), "address_configured": bool(address_map.get(item.get("interface"))),
                         "ip_address_count": len(address_map.get(item.get("interface"), [])),
                         "default_gateway_present": bool(gateways.get(item.get("interface")))})
    summary = "At least one network interface has an active link." if active else "Network interfaces are detected but no active link is present."
    return result("network.interfaces", "network", "Network interfaces", "PASS" if active else "WARN", summary, evidence)


def thermal_values(report, source):
    fixture = source.fixture_json("thermal.json")
    if isinstance(fixture, list):
        return fixture
    readings = (report.get("sensors") or {}).get("readings") or {}
    values = []
    def walk(value, path=""):
        if isinstance(value, dict):
            inputs = {key: item for key, item in value.items() if key.endswith("_input") and isinstance(item, (int, float))}
            for key, item in inputs.items():
                stem = key[:-6]
                values.append({"sensor": path + "/" + stem, "temperature_celsius": item,
                               "critical_celsius": value.get(stem + "_crit"), "max_celsius": value.get(stem + "_max")})
            for key, item in value.items(): walk(item, path + "/" + key)
        elif isinstance(value, list):
            for index, item in enumerate(value): walk(item, path + "/" + str(index))
    walk(readings)
    return values


def check_thermal(source, report):
    values = thermal_values(report, source)
    if not values:
        return result("thermal.sensors", "thermal", "Thermal sensors", "UNKNOWN", "No reliable thermal sensor readings are available.",
                      unavailable_reason="sensors unavailable")
    failures, warnings = [], []
    for item in values:
        temp, critical, maximum = (item.get(key) for key in ("temperature_celsius", "critical_celsius", "max_celsius"))
        limit = critical if isinstance(critical, (int, float)) else maximum
        if isinstance(temp, (int, float)) and isinstance(limit, (int, float)):
            if temp >= limit: failures.append(item.get("sensor"))
            elif temp >= limit - 5: warnings.append(item.get("sensor"))
    if failures:
        return result("thermal.sensors", "thermal", "Thermal sensors", "FAIL", "A temperature meets or exceeds its reported hardware limit.", values)
    if warnings:
        return result("thermal.sensors", "thermal", "Thermal sensors", "WARN", "A temperature is approaching its reported hardware limit.", values)
    return result("thermal.sensors", "thermal", "Thermal sensors", "PASS", "Available temperatures are below their reported limits.", values)


def check_battery(source, report):
    supplies = [item for item in (report.get("power") or {}).get("supplies") or [] if str(item.get("type")).lower() == "battery"]
    if not supplies:
        return result("battery.capacity", "battery", "Battery capacity", "UNKNOWN", "No battery is present.", unavailable_reason="no battery")
    evidence, warnings = [], []
    for item in supplies:
        design, full = item.get("design_capacity"), item.get("full_charge_capacity")
        health = round(full * 100 / design, 1) if isinstance(design, (int, float)) and design > 0 and isinstance(full, (int, float)) else None
        evidence.append({"name": item.get("name"), "state": item.get("status"), "charge_percent": item.get("capacity_percent"),
                         "design_capacity": design, "full_charge_capacity": full, "health_percent": health, "cycle_count": item.get("cycle_count")})
        if health is not None and health < 70: warnings.append(health)
    if warnings:
        return result("battery.capacity", "battery", "Battery capacity", "WARN", "Derived full-charge capacity is below 70% of design capacity.", evidence)
    if all(item["health_percent"] is None for item in evidence):
        return result("battery.capacity", "battery", "Battery capacity", "UNKNOWN", "Battery is present but capacity health cannot be derived.", evidence)
    return result("battery.capacity", "battery", "Battery capacity", "PASS", "Battery capacity health was derived from reported design and full-charge capacities.", evidence)


def kernel_check(source, report):
    text, reason = source.text("kernel.log", ["dmesg", "--color=never"])
    if reason and not text:
        return result("system.kernel_signals", "system", "Kernel error signals", "UNKNOWN", "Kernel diagnostic messages are unavailable.",
                      unavailable_reason=reason)
    patterns = (("FAIL", "uncorrected ECC", r"uncorrect(?:ed|able).*ECC|EDAC.*UE "),
                ("FAIL", "fatal PCIe AER", r"AER:.*(?:Fatal|Uncorrected.*fatal)"),
                ("FAIL", "storage I/O error", r"(?:nvme\S*|ata\S*|sd \S+).*I/O error"),
                ("WARN", "corrected ECC", r"corrected.*ECC|EDAC.*CE "),
                ("WARN", "corrected PCIe AER", r"AER:.*Corrected"),
                ("WARN", "storage reset/timeout", r"ata\S*:.*(?:reset|timeout)|nvme\S*:.*timeout"),
                ("WARN", "USB enumeration/disconnect", r"usb \S+:.*(?:device descriptor read.*error|USB disconnect)"),
                ("WARN", "thermal throttling", r"thermal.*throttl|temperature above threshold"))
    matches = []
    for status, label, pattern in patterns:
        count = len(re.findall(pattern, text, re.I))
        if count: matches.append({"signal": label, "status": status, "count": count})
    status = "FAIL" if any(item["status"] == "FAIL" for item in matches) else "WARN" if matches else "PASS"
    summary = "Targeted kernel signals include clear hardware-error evidence." if status == "FAIL" else "Targeted kernel signals warrant review." if status == "WARN" else "No targeted hardware-error signals were found in available kernel messages."
    return result("system.kernel_signals", "system", "Kernel error signals", status, summary, matches)


def passive_device_check(category, report_key, label):
    items = report_key
    if not items:
        return result("%s.enumeration" % category, category, label, "UNKNOWN", "No %s inventory is available." % category,
                      unavailable_reason="inventory unavailable")
    missing = sum(1 for item in items if category in ("pci", "graphics") and not item.get("driver"))
    status = "WARN" if missing else "PASS"
    summary = "%d device(s) enumerated." % len(items)
    if missing: summary += " %d have no bound driver; this does not by itself prove a fault." % missing
    evidence = {"devices_detected": len(items), "without_bound_driver": missing}
    return result("%s.enumeration" % category, category, label, status, summary, evidence)


def quick_checks(source, report):
    results = [check_system(source, report), check_firmware(source, report), check_cpu(source, report),
               check_memory(source, report)]
    results.extend(check_storage(source, report))
    results.extend([check_network(source, report), check_thermal(source, report), check_battery(source, report),
                    passive_device_check("pci", report.get("pci") or [], "PCI devices"),
                    passive_device_check("usb", report.get("usb") or [], "USB devices"),
                    passive_device_check("graphics", report.get("graphics") or [], "Graphics devices"),
                    kernel_check(source, report)])
    return results


def run_child(command, timeout, cancel_state):
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                               start_new_session=True)
    cancel_state["process"] = process
    try:
        output, _ = process.communicate(timeout=timeout)
        return process.returncode, output, int((time.monotonic() - started) * 1000), False
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try: output, _ = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL); output, _ = process.communicate()
        return 124, output, int((time.monotonic() - started) * 1000), True
    finally:
        cancel_state["process"] = None


def thermal_snapshot():
    values = []
    for path in Path("/sys/class/thermal").glob("thermal_zone*/temp"):
        try:
            raw = float(path.read_text().strip())
            values.append({"zone": path.parent.name, "temperature_celsius": raw / 1000 if raw > 1000 else raw})
        except (OSError, ValueError):
            pass
    return values


def throttling_snapshot():
    values = {}
    for path in Path("/sys/devices/system/cpu").glob("cpu*/thermal_throttle/*_throttle_count"):
        try: values[str(path.relative_to("/sys/devices/system/cpu"))] = int(path.read_text().strip())
        except (OSError, ValueError): pass
    return values


def active_cpu(duration, cancel_state):
    command = ["stress-ng", "--cpu", "0", "--timeout", "%ds" % duration, "--metrics-brief"]
    temperatures_before, throttling_before = thermal_snapshot(), throttling_snapshot()
    try: code, output, elapsed, timed_out = run_child(command, duration + 10, cancel_state)
    except FileNotFoundError:
        return [result("cpu.active", "cpu", "CPU diagnostic", "UNKNOWN", "CPU workload tool is unavailable.",
                       safety_class="stress", requires_user_action=True, unavailable_reason="stress-ng unavailable")]
    temperatures_after, throttling_after = thermal_snapshot(), throttling_snapshot()
    throttle_increase = {key: value - throttling_before.get(key, value) for key, value in throttling_after.items()
                         if value > throttling_before.get(key, value)}
    status = "PASS" if code == 0 and not throttle_increase else "WARN" if code == 0 else "ERROR"
    summary = ("Bounded CPU workload completed, but an exposed thermal-throttling counter increased." if code == 0 and throttle_increase
               else "Bounded CPU workload completed normally." if code == 0 else "CPU workload did not complete normally.")
    return [result("cpu.active", "cpu", "CPU diagnostic", status, summary,
                   {"duration_seconds": duration, "workers": "all logical CPUs", "exit_code": code,
                    "timed_out": timed_out, "temperatures_before": temperatures_before,
                    "temperatures_after": temperatures_after, "thermal_throttle_count_increase": throttle_increase,
                    "output_tail": output[-2000:]}, safety_class="stress",
                   duration_ms=elapsed, requires_user_action=True)]


def active_memory(mib, cancel_state):
    mem_available = 0
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemAvailable:"): mem_available = int(line.split()[1]) // 1024
    except OSError: pass
    reserve = max(512, mem_available // 4)
    chosen = mib or min(2048, max(128, mem_available - reserve))
    if mem_available and chosen > mem_available - reserve:
        return [result("memory.userspace", "memory", "Userspace memory test", "SKIPPED",
                       "Requested allocation would not leave the required memory reserve.",
                       {"requested_mib": chosen, "available_mib": mem_available, "reserve_mib": reserve},
                       safety_class="safe_active", requires_user_action=True)]
    command = ["memtester", "%dM" % chosen, "1"]
    try: code, output, elapsed, timed_out = run_child(command, 900, cancel_state)
    except FileNotFoundError:
        return [result("memory.userspace", "memory", "Userspace memory test", "UNKNOWN",
                       "memtester is unavailable. For deeper full-memory testing, reboot into Memtest86+.",
                       {"requested_mib": chosen}, safety_class="safe_active", requires_user_action=True,
                       unavailable_reason="memtester unavailable")]
    status = "PASS" if code == 0 else "FAIL"
    summary = ("Userspace memory test completed; this is not boot-time Memtest86+." if code == 0 else
               "Userspace memory test reported a failure; confirm with boot-time Memtest86+.")
    return [result("memory.userspace", "memory", "Userspace memory test", status, summary,
                   {"tested_mib": chosen, "passes": 1, "exit_code": code, "timed_out": timed_out,
                    "output_tail": output[-2000:]}, safety_class="safe_active", duration_ms=elapsed,
                   requires_user_action=True)]


def active_storage_read(device, mib, cancel_state):
    if not re.fullmatch(r"/dev/[A-Za-z0-9._/+:-]+", device or ""):
        return [result("storage.read", "storage", "Storage read test", "SKIPPED", "A valid /dev device path is required.",
                       safety_class="safe_active", requires_user_action=True)]
    command = ["dd", "if=" + device, "of=/dev/null", "bs=1M", "count=%d" % mib, "iflag=direct", "status=none"]
    try: code, output, elapsed, timed_out = run_child(command, 300, cancel_state)
    except FileNotFoundError:
        return [result("storage.read", "storage", "Storage read test", "UNKNOWN", "Read tool is unavailable.",
                       safety_class="safe_active", requires_user_action=True, unavailable_reason="dd unavailable")]
    throughput = round((mib * 1024 * 1024) / (elapsed / 1000), 1) if elapsed else None
    status = "PASS" if code == 0 else "FAIL"
    return [result("storage.read.%s" % Path(device).name, "storage", "Storage read test: " + Path(device).name,
                   status, "Bounded read completed without errors." if code == 0 else "The bounded read encountered an error.",
                   {"device": device, "amount_mib": mib, "bytes_read": mib * 1024 * 1024 if code == 0 else None,
                    "throughput_bytes_per_second": throughput, "exit_code": code, "timed_out": timed_out,
                    "writes_performed": False, "output_tail": output[-1000:]}, safety_class="safe_active",
                   duration_ms=elapsed, requires_user_action=True)]


def document(mode, results, started, elapsed):
    return {"schema_version": SCHEMA_VERSION, "engine": {"name": "probe-diagnostics", "version": "1.0"},
            "run": {"mode": mode, "started_at": started, "completed_at": utcnow(), "duration_ms": elapsed,
                    "offline": True, "destructive_checks_allowed": False}, "status_vocabulary": list(STATUSES),
            "safety_classes": list(SAFETY_CLASSES), "registry": [{"id": item[0], "category": item[1], "safety_class": item[2]} for item in CHECK_REGISTRY],
            "overall_status": aggregate(results),
            "category_summary": category_summary(results), "results": results}


def render_text(doc):
    lines = ["ProbeOS %s" % ("Quick Check" if doc["run"]["mode"] == "quick" else "Diagnostic Results"),
             "=" * 19, "", "Overall: " + doc["overall_status"], ""]
    for category, status in doc["category_summary"].items():
        lines.append("%-12s %s" % (category.title() + ":", status))
        for item in doc["results"]:
            if item["category"] == category and (len([x for x in doc["results"] if x["category"] == category]) > 1 or item["status"] != status):
                lines.append("  %s: %s - %s" % (item["name"], item["status"], item["summary"]))
    return "\n".join(lines) + "\n"


def render_html(doc):
    rows = "".join("<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % tuple(html.escape(str(value)) for value in
                   (item["name"], item["status"], item["summary"])) for item in doc["results"])
    return "<!doctype html><html><head><meta charset='utf-8'><title>ProbeOS Diagnostics</title><style>body{font-family:sans-serif;max-width:900px;margin:2em auto}td,th{padding:.4em;border:1px solid #bbb}table{border-collapse:collapse}</style></head><body><h1>ProbeOS Diagnostics</h1><p>Overall: %s</p><table><tr><th>Check</th><th>Status</th><th>Summary</th></tr>%s</table></body></html>\n" % (html.escape(doc["overall_status"]), rows)


def write_outputs(doc, output_dir):
    out = Path(output_dir); out.mkdir(parents=True, exist_ok=True)
    contents = {"diagnostics.json": json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                "diagnostics.txt": render_text(doc), "diagnostics.html": render_html(doc)}
    for name, content in contents.items():
        temporary = out / (name + ".tmp")
        temporary.write_text(content, encoding="utf-8")
        os.replace(temporary, out / name)
        os.chmod(out / name, 0o644)


def refresh_report_profiles(report_path, output_dir):
    """Link latest diagnostics into existing profiles without changing schema 1.1."""
    if not Path(report_path).is_file():
        return
    candidates = (Path(__file__).with_name("report-render.py"), Path("/usr/local/lib/probeos/report-render.py"))
    renderer = next((path for path in candidates if path.is_file()), None)
    if renderer:
        subprocess.run([sys.executable, str(renderer), report_path, output_dir], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)


def main():
    parser = argparse.ArgumentParser(description="ProbeOS central diagnostics engine")
    parser.add_argument("command", choices=("quick", "cpu", "memory", "storage-health", "storage-read", "network", "view"), nargs="?", default="quick")
    parser.add_argument("--output-dir", default=os.environ.get("PROBE_OUTPUT_DIR", "/run/probeos"))
    parser.add_argument("--report", default=None)
    parser.add_argument("--fixture-dir")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--duration", type=int, default=60)
    parser.add_argument("--memory-mib", type=int)
    parser.add_argument("--device")
    parser.add_argument("--read-mib", type=int, default=4096)
    args = parser.parse_args()
    if (args.duration < 1 or args.duration > 3600 or args.read_mib < 1 or args.read_mib > 65536 or
            args.memory_mib is not None and (args.memory_mib < 1 or args.memory_mib > 65536)):
        parser.error("active diagnostic bounds are invalid")
    report_path = args.report or os.path.join(args.output_dir, "report.json")
    source = Source(args.fixture_dir, args.timeout)
    report = source.report(report_path)
    cancel_state = {"process": None, "cancelled": False}
    def cancel(_signum, _frame):
        cancel_state["cancelled"] = True
        process = cancel_state.get("process")
        if process and process.poll() is None: os.killpg(process.pid, signal.SIGTERM)
    signal.signal(signal.SIGINT, cancel); signal.signal(signal.SIGTERM, cancel)
    started_at, started = utcnow(), time.monotonic()
    if args.command == "view":
        try: print(Path(args.output_dir, "diagnostics.txt").read_text(), end=""); return 0
        except OSError: print("Diagnostics have not been run.", file=sys.stderr); return 1
    if args.command == "quick": results = quick_checks(source, report)
    elif args.command == "cpu": results = active_cpu(args.duration, cancel_state)
    elif args.command == "memory": results = active_memory(args.memory_mib, cancel_state)
    elif args.command == "storage-health": results = check_storage(source, report)
    elif args.command == "storage-read": results = active_storage_read(args.device, args.read_mib, cancel_state)
    else: results = [check_network(source, report)]
    if cancel_state["cancelled"]:
        results = [result(item["id"], item["category"], item["name"], "SKIPPED", "Diagnostic was cancelled; child workloads were stopped.",
                          item.get("evidence"), safety_class=item["safety_class"], duration_ms=item["duration_ms"], requires_user_action=True) for item in results]
    doc = document(args.command, results, started_at, int((time.monotonic() - started) * 1000))
    write_outputs(doc, args.output_dir)
    refresh_report_profiles(report_path, args.output_dir)
    print(render_text(doc), end="")
    return 1 if doc["overall_status"] in ("FAIL", "ERROR") else 0


if __name__ == "__main__":
    raise SystemExit(main())
