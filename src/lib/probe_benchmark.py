#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Authoritative ProbeOS benchmark and stability engine.

Benchmarks record reproducible native measurements, never health ratings.
Stability workloads reuse ProbeOS diagnostics for hardware interpretation.
"""
import argparse
import datetime as dt
import html
import json
import os
import platform
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BENCHMARK_SCHEMA = "1.0"
STABILITY_SCHEMA = "1.0"
ENGINE_VERSION = "1.0"
STATUSES = ("COMPLETED", "SKIPPED", "CANCELLED", "ERROR", "UNSUPPORTED")
STABILITY_STATUSES = ("COMPLETED_NO_NEW_ERRORS", "COMPLETED_WITH_WARNINGS",
                      "ABORTED_HARDWARE_SIGNAL", "CANCELLED", "ERROR")
DEFAULT_OUTPUT = "/run/probeos"
DEFAULT_CPU_SECONDS = 10
DEFAULT_MEMORY_SECONDS = 10
DEFAULT_STORAGE_MIB = 1024
MIN_STABILITY_SECONDS = 60
MAX_STABILITY_SECONDS = 24 * 60 * 60

REGISTRY = {
    "cpu.sysbench.single.v1": {"category": "cpu", "name": "CPU single thread", "version": "1", "tool": "sysbench", "safety": "safe_active"},
    "cpu.sysbench.multi.v1": {"category": "cpu", "name": "CPU multi thread", "version": "1", "tool": "sysbench", "safety": "safe_active"},
    "memory.sysbench.read.v1": {"category": "memory", "name": "Memory sequential read", "version": "1", "tool": "sysbench", "safety": "safe_active"},
    "memory.sysbench.write.v1": {"category": "memory", "name": "Memory sequential write", "version": "1", "tool": "sysbench", "safety": "safe_active", "scope": "allocated RAM only"},
    "storage.seq-read.v1": {"category": "storage", "name": "Storage sequential read", "version": "1", "tool": "dd", "safety": "read_only"},
    "network.iperf3-tcp.v1": {"category": "network", "name": "Network TCP throughput", "version": "1", "tool": "iperf3", "safety": "network_active"},
}
PROFILES = {
    "quick": ["cpu.sysbench.single.v1", "cpu.sysbench.multi.v1", "memory.sysbench.read.v1", "storage.seq-read.v1"],
    "cpu": ["cpu.sysbench.single.v1", "cpu.sysbench.multi.v1"],
    "memory": ["memory.sysbench.read.v1", "memory.sysbench.write.v1"],
    "storage": ["storage.seq-read.v1"],
    "network": ["network.iperf3-tcp.v1"],
    "full": ["cpu.sysbench.single.v1", "cpu.sysbench.multi.v1", "memory.sysbench.read.v1",
             "memory.sysbench.write.v1", "storage.seq-read.v1", "network.iperf3-tcp.v1"],
}
SENSITIVE = re.compile(r"(?:serial|uuid|mac_address|product_key|windows.*key)", re.I)


def utcnow():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def redact(value):
    if isinstance(value, dict):
        return {key: ("[redacted]" if SENSITIVE.search(key) and item is not None else redact(item)) for key, item in value.items()}
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def read_json(path, default=None):
    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
        return value
    except (OSError, ValueError):
        return default


def system_context(report_path="/run/probeos/report.json"):
    report = read_json(report_path, {}) or {}
    cpus = report.get("cpu") or []
    cpu = cpus[0] if cpus else {}
    memory = report.get("memory") or {}
    probeos = report.get("probeos") or {}
    context = {
        "probeos_version": probeos.get("version") or os.environ.get("PROBEOS_VERSION", "development"),
        "architecture": probeos.get("architecture") or platform.machine(),
        "logical_cpu_count": os.cpu_count(),
        "cpu_model": cpu.get("model") or cpu.get("model_name") or platform.processor() or None,
        "memory_total_bytes": memory.get("total_usable_bytes"),
        "cpu_power": cpu_power_context(),
        "timestamp_reliability": "unknown" if dt.datetime.now(dt.timezone.utc).year < 2024 else "system_clock",
    }
    return redact(context)


def cpu_power_context():
    def first(pattern):
        for path in Path("/sys/devices/system/cpu").glob(pattern):
            try: return path.read_text().strip()
            except OSError: pass
        return None
    ac = None
    for path in Path("/sys/class/power_supply").glob("*/online"):
        try:
            ac = path.read_text().strip() == "1"
            break
        except OSError: pass
    return {"governor": first("cpu*/cpufreq/scaling_governor"),
            "reported_frequency_khz": first("cpu*/cpufreq/scaling_cur_freq"), "ac_online": ac}


def tool_version(tool, runner=None):
    command = [tool, "--version"]
    try:
        if runner:
            code, output, _, timed_out = runner(command, 5)
        else:
            run = subprocess.run(command, capture_output=True, text=True, timeout=5, check=False)
            code, output, timed_out = run.returncode, (run.stdout + run.stderr), False
        if timed_out or code != 0: return None
        return output.strip().splitlines()[0][:200] if output.strip() else None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


class Cancelled(Exception):
    pass


class ProcessRunner:
    def __init__(self):
        self.process = None
        self.cancelled = False

    def cancel(self):
        self.cancelled = True
        if self.process and self.process.poll() is None:
            try: os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError: pass

    def __call__(self, command, timeout, progress=None, thermal_monitor=None):
        started = time.monotonic()
        self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, start_new_session=True)
        output = ""
        try:
            while self.process.poll() is None:
                elapsed = time.monotonic() - started
                if self.cancelled:
                    self.cancel()
                    try: output, _ = self.process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.process.pid, signal.SIGKILL); output, _ = self.process.communicate()
                    raise Cancelled()
                if elapsed >= timeout:
                    os.killpg(self.process.pid, signal.SIGTERM)
                    try: output, _ = self.process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.process.pid, signal.SIGKILL); output, _ = self.process.communicate()
                    return 124, output, int(elapsed * 1000), True
                if thermal_monitor and thermal_monitor.sample():
                    os.killpg(self.process.pid, signal.SIGTERM)
                    try: output, _ = self.process.communicate(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.process.pid, signal.SIGKILL); output, _ = self.process.communicate()
                    return 125, output, int(elapsed * 1000), False
                if progress: progress(elapsed)
                time.sleep(min(1, max(.05, timeout - elapsed)))
            output, _ = self.process.communicate()
            if self.cancelled:
                raise Cancelled()
            return self.process.returncode, output, int((time.monotonic() - started) * 1000), False
        finally:
            self.process = None


def benchmark_result(benchmark_id, status, parameters, started, duration_ms=0, measurements=None,
                     tool_version_value=None, error=None, context=None):
    spec = REGISTRY[benchmark_id]
    value = {"benchmark_id": benchmark_id, "category": spec["category"], "benchmark_name": spec["name"],
             "benchmark_version": spec["version"], "workload_tool": spec["tool"],
             "tool_version": tool_version_value, "parameters": parameters, "started_at": started,
             "duration_ms": int(duration_ms), "status": status, "measurements": measurements or [],
             "units": sorted({m["unit"] for m in measurements or []}), "environment": context or {}}
    if error: value["error"] = str(error)[:1000]
    return redact(value)


def parse_sysbench_cpu(output):
    eps = re.search(r"events per second:\s*([0-9.]+)", output, re.I)
    latency = re.search(r"avg:\s*([0-9.]+)", output, re.I)
    if not eps: raise ValueError("sysbench CPU output lacks events per second")
    values = [{"name": "events_per_second", "value": float(eps.group(1)), "unit": "events/s"}]
    if latency: values.append({"name": "average_latency", "value": float(latency.group(1)), "unit": "ms"})
    return values


def parse_sysbench_memory(output):
    rate = re.search(r"(?:transferred|MiB transferred).*?\(([0-9.]+)\s+(MiB|GiB)/sec\)", output, re.I)
    if not rate: raise ValueError("sysbench memory output lacks bandwidth")
    return [{"name": "bandwidth", "value": float(rate.group(1)), "unit": rate.group(2) + "/s"}]


def parse_iperf(output):
    data = json.loads(output)
    end = data.get("end") or {}
    sent = end.get("sum_sent") or {}
    received = end.get("sum_received") or {}
    if "bits_per_second" not in received: raise ValueError("iperf3 output lacks received throughput")
    values = [{"name": "sent_throughput", "value": float(sent.get("bits_per_second", 0)), "unit": "bit/s"},
              {"name": "received_throughput", "value": float(received["bits_per_second"]), "unit": "bit/s"}]
    if "retransmits" in sent: values.append({"name": "retransmits", "value": int(sent["retransmits"]), "unit": "count"})
    return values


class Engine:
    def __init__(self, runner=None, report_path="/run/probeos/report.json", progress=None):
        self.runner = runner or ProcessRunner()
        self.context = system_context(report_path)
        self.progress = progress

    def run_one(self, benchmark_id, cpu_seconds=DEFAULT_CPU_SECONDS, memory_seconds=DEFAULT_MEMORY_SECONDS,
                storage_device=None, storage_mib=DEFAULT_STORAGE_MIB, peer=None, network_seconds=10):
        started = utcnow(); spec = REGISTRY[benchmark_id]; tool = spec["tool"]
        version = tool_version(tool, self.runner)
        parameters = {}; command = None; parser = None; timeout = 30
        if not version and tool != "dd":
            return benchmark_result(benchmark_id, "UNSUPPORTED", parameters, started, error=tool + " unavailable", context=self.context)
        if benchmark_id.startswith("cpu."):
            threads = 1 if ".single." in benchmark_id else max(1, os.cpu_count() or 1)
            parameters = {"threads": threads, "duration_seconds": cpu_seconds, "max_prime": 20000}
            command = ["sysbench", "cpu", "--cpu-max-prime=20000", "--threads=%d" % threads,
                       "--time=%d" % cpu_seconds, "run"]; parser = parse_sysbench_cpu; timeout = cpu_seconds + 15
        elif benchmark_id.startswith("memory."):
            operation = "read" if ".read." in benchmark_id else "write"
            threads = min(4, max(1, os.cpu_count() or 1)); block_kib = 1024
            parameters = {"operation": operation, "threads": threads, "duration_seconds": memory_seconds,
                          "block_size_kib": block_kib, "scope": "allocated RAM"}
            command = ["sysbench", "memory", "--memory-oper=" + operation, "--memory-block-size=1M",
                       "--memory-total-size=100T", "--threads=%d" % threads, "--time=%d" % memory_seconds, "run"]
            parser = parse_sysbench_memory; timeout = memory_seconds + 15
        elif benchmark_id.startswith("storage."):
            parameters = {"device": storage_device, "amount_mib": storage_mib, "block_size_mib": 1,
                          "operation": "read", "writes_performed": False}
            if not storage_device:
                return benchmark_result(benchmark_id, "UNSUPPORTED", parameters, started, error="explicit storage device not selected", context=self.context)
            try:
                mode = os.stat(storage_device).st_mode
                if not (stat.S_ISBLK(mode) or stat.S_ISREG(mode)):
                    raise ValueError("target is not a block device or regular fixture file")
            except (OSError, ValueError) as exc:
                return benchmark_result(benchmark_id, "ERROR", parameters, started, error=exc, context=self.context)
            command = ["dd", "if=" + storage_device, "of=/dev/null", "bs=1M", "count=%d" % storage_mib,
                       "iflag=direct", "status=none"]; timeout = max(30, min(900, storage_mib)); parser = None
        elif benchmark_id.startswith("network."):
            parameters = {"peer": peer, "protocol": "TCP", "duration_seconds": network_seconds, "streams": 1}
            if not peer:
                return benchmark_result(benchmark_id, "UNSUPPORTED", parameters, started, error="network benchmark peer not configured", context=self.context)
            command = ["iperf3", "--client", peer, "--json", "--time", str(network_seconds), "--parallel", "1"]
            parser = parse_iperf; timeout = network_seconds + 15
        try:
            code, output, elapsed, timed_out = self.runner(command, timeout, self.progress)
            if timed_out: return benchmark_result(benchmark_id, "ERROR", parameters, started, elapsed, tool_version_value=version, error="workload timed out", context=self.context)
            if code != 0:
                return benchmark_result(benchmark_id, "ERROR", parameters, started, elapsed, tool_version_value=version, error="workload exited %d: %s" % (code, output[-500:]), context=self.context)
            if benchmark_id.startswith("storage."):
                measurements = [{"name": "bytes_read", "value": storage_mib * 1024 * 1024, "unit": "bytes"},
                                {"name": "throughput", "value": (storage_mib * 1024 * 1024) / (elapsed / 1000), "unit": "bytes/s"},
                                {"name": "read_errors", "value": 0, "unit": "count"}]
            else: measurements = parser(output)
            return benchmark_result(benchmark_id, "COMPLETED", parameters, started, elapsed, measurements, version, context=self.context)
        except FileNotFoundError:
            return benchmark_result(benchmark_id, "UNSUPPORTED", parameters, started, tool_version_value=version, error=tool + " unavailable", context=self.context)
        except Cancelled:
            return benchmark_result(benchmark_id, "CANCELLED", parameters, started, tool_version_value=version, error="cancelled by user", context=self.context)
        except (ValueError, json.JSONDecodeError) as exc:
            return benchmark_result(benchmark_id, "ERROR", parameters, started, tool_version_value=version, error=exc, context=self.context)

    def run_profile(self, profile, **kwargs):
        started = utcnow(); begin = time.monotonic(); results = []
        for benchmark_id in PROFILES[profile]:
            if self.progress: self.progress(0, REGISTRY[benchmark_id]["name"])
            item = self.run_one(benchmark_id, **kwargs); results.append(item)
            if item["status"] == "CANCELLED": break
        return {"schema_version": BENCHMARK_SCHEMA, "document_type": "probeos_benchmarks",
                "engine": {"name": "probe-benchmark", "version": ENGINE_VERSION},
                "status_vocabulary": list(STATUSES), "profile": profile, "started_at": started,
                "completed_at": utcnow(), "duration_ms": int((time.monotonic() - begin) * 1000),
                "comparability": "Direct comparison requires matching benchmark ID/version, parameters, and relevant tool methodology/version.",
                "registry": REGISTRY, "profiles": PROFILES, "results": results}


def atomic_outputs(output_dir, base, document):
    target = Path(output_dir); target.mkdir(parents=True, exist_ok=True)
    contents = {base + ".json": json.dumps(redact(document), indent=2, ensure_ascii=False) + "\n",
                base + ".txt": render_text(document), base + ".html": render_html(document)}
    for name, value in contents.items():
        fd, temporary = tempfile.mkstemp(prefix="." + name + ".", dir=str(target), text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream: stream.write(value)
            os.replace(temporary, target / name)
        finally:
            try: os.unlink(temporary)
            except OSError: pass


def refresh_reports(report_path, output_dir):
    renderer = Path(__file__).with_name("report-render.py")
    if Path(report_path).is_file() and renderer.is_file():
        try:
            subprocess.run([sys.executable, str(renderer), report_path, output_dir], check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        except (OSError, subprocess.TimeoutExpired): pass


def render_text(doc):
    if doc.get("document_type") == "probeos_stability":
        lines = ["ProbeOS Stability Test", "======================", "", "Duration: %s seconds" % doc.get("duration_seconds"),
                 "Workload: CPU + memory", "", "Result: " + doc.get("status", "ERROR")]
        if doc.get("message"): lines += ["  " + doc["message"]]
        return "\n".join(lines) + "\n"
    lines = ["ProbeOS %s Benchmark" % doc.get("profile", "").title(), "=======================", ""]
    for item in doc.get("results", []):
        lines += [item["benchmark_name"], "  Status: " + item["status"]]
        for measurement in item.get("measurements", []):
            lines.append("  %s: %s %s" % (measurement["name"].replace("_", " ").title(), measurement["value"], measurement["unit"]))
        if item.get("error"): lines.append("  Detail: " + item["error"])
        lines.append("")
    return "\n".join(lines)


def render_html(doc):
    return "<!doctype html><html><head><meta charset='utf-8'><title>ProbeOS Results</title><style>body{font-family:sans-serif;max-width:900px;margin:2em auto}pre{white-space:pre-wrap}</style></head><body><h1>ProbeOS Results</h1><pre>%s</pre></body></html>\n" % html.escape(render_text(doc))


def thermal_readings(root="/sys/class/thermal"):
    readings = []
    for path in Path(root).glob("thermal_zone*/temp"):
        try:
            raw = float(path.read_text().strip()); zone = path.parent
            critical = None
            for trip_type in zone.glob("trip_point_*_type"):
                try:
                    if trip_type.read_text().strip().lower() == "critical":
                        temp = trip_type.with_name(trip_type.name.replace("_type", "_temp"))
                        value = float(temp.read_text().strip()); critical = value / 1000 if value > 1000 else value; break
                except (OSError, ValueError): pass
            readings.append({"zone": zone.name, "temperature_celsius": raw / 1000 if raw > 1000 else raw,
                             "critical_celsius": critical})
        except (OSError, ValueError): pass
    return readings


class ThermalMonitor:
    def __init__(self, reader=thermal_readings):
        self.reader = reader; self.initial = reader(); self.maximum = {x["zone"]: x["temperature_celsius"] for x in self.initial}
        self.final = self.initial; self.aborted = False

    def sample(self):
        self.final = self.reader()
        for item in self.final:
            self.maximum[item["zone"]] = max(self.maximum.get(item["zone"], item["temperature_celsius"]), item["temperature_celsius"])
            if item.get("critical_celsius") is not None and item["temperature_celsius"] >= item["critical_celsius"]:
                self.aborted = True
        return self.aborted

    def result(self):
        return {"initial": self.initial, "maximum_celsius": self.maximum, "final": self.final,
                "critical_threshold_source": "kernel thermal-zone trip points", "critical_limit_reached": self.aborted}


def diagnostic_snapshot(report_path):
    """Reuse diagnostics' authoritative live interpreters; never reinterpret health here."""
    try:
        import probe_diagnostics as diagnostics
        source = diagnostics.Source(timeout=20); report = source.report(report_path)
        results = diagnostics.check_storage(source, report)
        results += [diagnostics.check_thermal(source, report), diagnostics.kernel_check(source, report)]
        return [{"id": x["id"], "status": x["status"], "summary": x["summary"]} for x in results]
    except (ImportError, AttributeError, OSError, ValueError) as exc:
        return [{"id": "diagnostics.snapshot", "status": "UNKNOWN", "summary": "Diagnostic snapshot unavailable: " + str(exc)}]


def stability_document(duration, runner, report_path, progress=None, thermal_reader=thermal_readings):
    started = utcnow(); begin = time.monotonic(); before = diagnostic_snapshot(report_path); monitor = ThermalMonitor(thermal_reader)
    available_mib = 0
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemAvailable:"): available_mib = int(line.split()[1]) // 1024
    except OSError: pass
    memory_mib = min(2048, max(128, available_mib // 2)) if available_mib else 256
    command = ["stress-ng", "--cpu", "0", "--vm", "1", "--vm-bytes", "%dM" % memory_mib,
               "--timeout", "%ds" % duration, "--metrics-brief"]
    status = "ERROR"; reason = None; output = ""; code = None
    try:
        code, output, _, timed_out = runner(command, duration + 15, progress, monitor)
        if monitor.aborted: status, reason = "ABORTED_HARDWARE_SIGNAL", "aborted_due_to_thermal_limit"
        elif timed_out: status, reason = "ERROR", "workload_timeout"
        elif code != 0: status, reason = "ERROR", "workload_exit_%s" % code
        else: status = "COMPLETED_NO_NEW_ERRORS"
    except FileNotFoundError: reason = "stress-ng unavailable"
    except Cancelled: status, reason = "CANCELLED", "cancelled_by_user"
    after = diagnostic_snapshot(report_path)
    adverse = {"WARN", "FAIL", "ERROR"}
    before_map = {x["id"]: x["status"] for x in before}
    new_indicators = [x for x in after if x["status"] in adverse and before_map.get(x["id"]) not in adverse]
    if status == "COMPLETED_NO_NEW_ERRORS" and new_indicators: status = "COMPLETED_WITH_WARNINGS"
    message = ("No new monitored hardware-error indicators were detected during the test." if status == "COMPLETED_NO_NEW_ERRORS"
               else "New monitored diagnostic indicators require review." if status == "COMPLETED_WITH_WARNINGS" else reason or status)
    return {"schema_version": STABILITY_SCHEMA, "document_type": "probeos_stability",
            "engine": {"name": "probe-benchmark", "version": ENGINE_VERSION}, "status_vocabulary": list(STABILITY_STATUSES),
            "started_at": started, "duration_seconds": duration, "actual_duration_ms": int((time.monotonic() - begin) * 1000),
            "status": status, "message": message, "abort_reason": reason if status == "ABORTED_HARDWARE_SIGNAL" else None,
            "workload": {"tool": "stress-ng", "tool_version": tool_version("stress-ng", runner), "cpu_workers": "all",
                         "memory_workers": 1, "memory_mib": memory_mib, "storage_writes": False, "command_parameters": command[1:]},
            "thermal": monitor.result(), "diagnostics": {"before": before, "after": after, "new_adverse_indicators": new_indicators},
            "environment": system_context(report_path), "workload_exit_code": code, "output_tail": output[-1000:]}


def main(argv=None):
    parser = argparse.ArgumentParser(description="ProbeOS benchmark and stability engine")
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run"); run.add_argument("profile", choices=sorted(PROFILES)); run.add_argument("--device"); run.add_argument("--peer")
    run.add_argument("--cpu-seconds", type=int, default=DEFAULT_CPU_SECONDS); run.add_argument("--memory-seconds", type=int, default=DEFAULT_MEMORY_SECONDS)
    run.add_argument("--storage-mib", type=int, default=DEFAULT_STORAGE_MIB); run.add_argument("--network-seconds", type=int, default=10)
    run.add_argument("--output-dir", default=DEFAULT_OUTPUT); run.add_argument("--report", default="/run/probeos/report.json")
    stability = sub.add_parser("stability"); stability.add_argument("--duration", type=int, required=True)
    stability.add_argument("--output-dir", default=DEFAULT_OUTPUT); stability.add_argument("--report", default="/run/probeos/report.json")
    view = sub.add_parser("view"); view.add_argument("kind", choices=("benchmarks", "stability")); view.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    args = parser.parse_args(argv); runner = ProcessRunner(); last_progress = {"second": -5}
    def progress(elapsed, phase=None):
        second = int(elapsed)
        if phase or second - last_progress["second"] >= 5:
            last_progress["second"] = second
            print("%s: elapsed %ds" % (phase or "Current workload", second), file=sys.stderr, flush=True)
    signal.signal(signal.SIGINT, lambda *_: runner.cancel()); signal.signal(signal.SIGTERM, lambda *_: runner.cancel())
    if args.command == "view":
        try: print(Path(args.output_dir, args.kind + ".txt").read_text(), end=""); return 0
        except OSError: print(args.kind.title() + " results are unavailable.", file=sys.stderr); return 1
    if args.command == "stability":
        if not MIN_STABILITY_SECONDS <= args.duration <= MAX_STABILITY_SECONDS:
            parser.error("stability duration must be between 60 seconds and 24 hours")
        print("Stability workload: planned %ds; temperatures sampled periodically" % args.duration, file=sys.stderr)
        doc = stability_document(args.duration, runner, args.report, progress); atomic_outputs(args.output_dir, "stability", doc); refresh_reports(args.report, args.output_dir)
        print(render_text(doc), end=""); return 0 if doc["status"].startswith("COMPLETED") else 1
    if not (1 <= args.cpu_seconds <= 300 and 1 <= args.memory_seconds <= 300 and 1 <= args.storage_mib <= 4096 and 1 <= args.network_seconds <= 300):
        parser.error("benchmark resource bounds are invalid")
    engine = Engine(runner, args.report, progress)
    doc = engine.run_profile(args.profile, cpu_seconds=args.cpu_seconds, memory_seconds=args.memory_seconds,
                             storage_device=args.device, storage_mib=args.storage_mib, peer=args.peer, network_seconds=args.network_seconds)
    atomic_outputs(args.output_dir, "benchmarks", doc); refresh_reports(args.report, args.output_dir); print(render_text(doc), end="")
    return 1 if any(x["status"] in ("ERROR", "CANCELLED") for x in doc["results"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
