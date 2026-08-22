#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixture and safety qualification for benchmark/stability framework."""
import importlib.util
import json
import os
import signal
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("probe_benchmark", ROOT / "src/lib/probe_benchmark.py")
bench = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(bench)


class FixtureRunner:
    def __init__(self, malformed=False, fail=None, timeout=False):
        self.commands = []; self.malformed = malformed; self.fail = fail; self.timeout = timeout
    def __call__(self, command, timeout, *unused):
        self.commands.append(command)
        if command[1:] == ["--version"]: return 0, command[0] + " 1.0", 1, False
        if self.timeout: return 124, "", 12, True
        if self.fail and command[0] == self.fail: return 2, "fixture failure", 12, False
        if command[0] == "sysbench" and command[1] == "cpu":
            return 0, "events per second: 4812.50\nLatency (ms):\n avg: 0.21", 1000, False
        if command[0] == "sysbench": return 0, ("broken" if self.malformed else "1024.00 MiB transferred (18400.00 MiB/sec)"), 1000, False
        if command[0] == "iperf3":
            return 0, json.dumps({"end": {"sum_sent": {"bits_per_second": 900000000, "retransmits": 2}, "sum_received": {"bits_per_second": 890000000}}}), 1000, False
        if command[0] == "dd": return 0, "", 1000, False
        if command[0] == "stress-ng": return 0, "metrics", 1000, False
        raise FileNotFoundError(command[0])


class BenchmarkTests(unittest.TestCase):
    def engine(self, runner): return bench.Engine(runner=runner, report_path="/nonexistent")

    def test_schema_registry_profiles_and_status_model(self):
        doc = self.engine(FixtureRunner()).run_profile("cpu", cpu_seconds=1)
        self.assertEqual(doc["schema_version"], "1.0")
        self.assertEqual({x["status"] for x in doc["results"]}, {"COMPLETED"})
        self.assertNotIn("PASS", bench.STATUSES); self.assertIn("cpu.sysbench.single.v1", doc["registry"])

    def test_cpu_single_multi_native_measurements(self):
        doc = self.engine(FixtureRunner()).run_profile("cpu", cpu_seconds=2)
        self.assertEqual([x["parameters"]["threads"] for x in doc["results"]][0], 1)
        self.assertGreaterEqual(doc["results"][1]["parameters"]["threads"], 1)
        self.assertEqual(doc["results"][0]["measurements"][0]["unit"], "events/s")

    def test_memory_success_and_malformed(self):
        good = self.engine(FixtureRunner()).run_one("memory.sysbench.read.v1", memory_seconds=1)
        bad = self.engine(FixtureRunner(malformed=True)).run_one("memory.sysbench.read.v1", memory_seconds=1)
        self.assertEqual(good["status"], "COMPLETED"); self.assertEqual(good["measurements"][0]["unit"], "MiB/s")
        self.assertEqual(bad["status"], "ERROR")

    def test_storage_read_only_and_permission_failure(self):
        with tempfile.NamedTemporaryFile() as target:
            runner = FixtureRunner(); item = self.engine(runner).run_one("storage.seq-read.v1", storage_device=target.name, storage_mib=4)
            command = next(x for x in runner.commands if x[0] == "dd" and x[1:] != ["--version"])
            self.assertEqual(item["status"], "COMPLETED"); self.assertIn("if=" + target.name, command)
            self.assertEqual(command[2], "of=/dev/null"); self.assertNotIn("of=" + target.name, command)
        item = self.engine(FixtureRunner()).run_one("storage.seq-read.v1", storage_device="/root/not-readable", storage_mib=4)
        self.assertEqual(item["status"], "ERROR")

    def test_no_write_benchmark_and_unsafe_targets(self):
        source = (ROOT / "src/lib/probe_benchmark.py").read_text()
        self.assertFalse(any(x.startswith("storage") and "write" in x for x in bench.REGISTRY))
        self.assertNotIn("--rw=write", source); self.assertNotIn("badblocks", source)
        with tempfile.TemporaryDirectory() as directory:
            regular = Path(directory, "regular"); regular.write_bytes(b"x")
            link = Path(directory, "link"); link.symlink_to(regular)
            # Symlink is refused by policy before any workload is executed.
            with mock.patch.object(bench.os, "stat", side_effect=OSError("refused")):
                self.assertEqual(self.engine(FixtureRunner()).run_one("storage.seq-read.v1", storage_device=str(link))["status"], "ERROR")

    def test_network_absent_success_and_malformed(self):
        self.assertEqual(self.engine(FixtureRunner()).run_one("network.iperf3-tcp.v1")["status"], "UNSUPPORTED")
        self.assertEqual(self.engine(FixtureRunner()).run_one("network.iperf3-tcp.v1", peer="192.0.2.1")["status"], "COMPLETED")
        runner = FixtureRunner(); runner.__class__ = type("Bad", (FixtureRunner,), {"__call__": lambda self, command, timeout, *x: (0, command[0] + " 1.0", 1, False) if command[1:] == ["--version"] else (0, "{}", 1, False)})
        self.assertEqual(self.engine(runner).run_one("network.iperf3-tcp.v1", peer="192.0.2.1")["status"], "ERROR")

    def test_timeout_missing_tool_failure_and_partial_full(self):
        self.assertEqual(self.engine(FixtureRunner(timeout=True)).run_one("cpu.sysbench.single.v1")["status"], "ERROR")
        missing = lambda command, timeout, *x: (_ for _ in ()).throw(FileNotFoundError())
        self.assertEqual(self.engine(missing).run_one("cpu.sysbench.single.v1")["status"], "UNSUPPORTED")
        doc = self.engine(FixtureRunner(fail="iperf3")).run_profile("full", peer="192.0.2.1")
        self.assertTrue(any(x["status"] == "COMPLETED" for x in doc["results"])); self.assertEqual(doc["results"][-1]["status"], "ERROR")

    def test_json_txt_html_and_privacy(self):
        doc = self.engine(FixtureRunner()).run_profile("cpu", cpu_seconds=1)
        doc["secret"] = {"serial_number": "SSD123", "mac_address": "52:54:00:00:00:01"}
        with tempfile.TemporaryDirectory() as directory:
            bench.atomic_outputs(directory, "benchmarks", doc)
            value = json.loads(Path(directory, "benchmarks.json").read_text())
            self.assertEqual(value["secret"]["serial_number"], "[redacted]")
            self.assertNotIn("SSD123", Path(directory, "benchmarks.html").read_text())

    def test_thermal_abort_at_kernel_threshold(self):
        samples = iter(([{"zone": "z0", "temperature_celsius": 90, "critical_celsius": 100}],
                        [{"zone": "z0", "temperature_celsius": 100, "critical_celsius": 100}]))
        monitor = bench.ThermalMonitor(lambda: next(samples))
        self.assertTrue(monitor.sample()); self.assertTrue(monitor.result()["critical_limit_reached"])

    def test_stability_semantics_and_bounded_memory(self):
        with mock.patch.object(bench, "diagnostic_snapshot", return_value=[{"id": "system.kernel_signals", "status": "PASS", "summary": "ok"}]):
            doc = bench.stability_document(60, FixtureRunner(), "/nonexistent", thermal_reader=lambda: [])
        self.assertEqual(doc["status"], "COMPLETED_NO_NEW_ERRORS"); self.assertFalse(doc["workload"]["storage_writes"])
        self.assertLessEqual(doc["workload"]["memory_mib"], 2048)

    def test_process_group_cancellation_cleanup(self):
        runner = bench.ProcessRunner()
        pid_file = tempfile.NamedTemporaryFile(delete=False); pid_file.close()
        command = ["sh", "-c", "echo $$ > '%s'; trap 'exit 0' TERM; while :; do sleep 1; done" % pid_file.name]
        import threading
        result = []
        thread = threading.Thread(target=lambda: result.append(self._cancel_run(runner, command)))
        thread.start(); time.sleep(.2); runner.cancel(); thread.join(5)
        self.assertFalse(thread.is_alive()); self.assertEqual(result, ["cancelled"])
        pid = int(Path(pid_file.name).read_text()); os.unlink(pid_file.name)
        with self.assertRaises(ProcessLookupError): os.kill(pid, 0)

    @staticmethod
    def _cancel_run(runner, command):
        try: runner(command, 10)
        except bench.Cancelled: return "cancelled"


if __name__ == "__main__": unittest.main()
