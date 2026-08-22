#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fixture-level qualification for the ProbeOS diagnostics result model."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("probe_diagnostics", ROOT / "src/lib/probe_diagnostics.py")
diag = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag)


class DiagnosticsTests(unittest.TestCase):
    def test_aggregation(self):
        make = lambda status: diag.result("test." + status.lower(), "system", "Test", status, status)
        self.assertEqual(diag.aggregate([make("PASS")]), "PASS")
        self.assertEqual(diag.aggregate([make("PASS"), make("WARN")]), "WARN")
        self.assertEqual(diag.aggregate([make("WARN"), make("FAIL")]), "FAIL")
        self.assertEqual(diag.aggregate([make("ERROR")]), "ERROR")
        self.assertEqual(diag.aggregate([make("UNKNOWN"), make("SKIPPED")]), "UNKNOWN")

    def test_storage_states(self):
        cases = (
            ({"smart_supported": True, "smart_passed": True}, "PASS"),       # healthy SATA SSD/HDD
            ({"smart_supported": True, "smart_passed": False}, "FAIL"),
            ({"smart_supported": True, "smart_passed": True, "pending_sectors": 12}, "WARN"),
            ({"smart_supported": True, "smart_passed": True, "reallocated_sectors": 2}, "WARN"),
            ({"smart_supported": True, "smart_passed": True, "temperature_celsius": 75,
              "temperature_limit_celsius": 70}, "WARN"),
            ({"smart_supported": True, "critical_warning": 0, "media_errors": 0}, "PASS"),
            ({"smart_supported": True, "critical_warning": 2}, "FAIL"),
            ({"smart_supported": True, "critical_warning": 0, "percentage_used": 95}, "WARN"),
            ({"smart_supported": False}, "WARN"),                            # unsupported / USB passthrough
        )
        for evidence, expected in cases:
            with self.subTest(evidence=evidence):
                self.assertEqual(diag.storage_interpret("/dev/test", evidence)[0], expected)

    def test_nvme_and_ata_normalization(self):
        nvme = diag.smart_normalize({"smart_support": {"available": True},
            "nvme_smart_health_information_log": {"critical_warning": 0, "temperature": 310,
            "percentage_used": 22, "media_errors": 0}})
        self.assertEqual(nvme["temperature_celsius"], 37)
        ata = diag.smart_normalize({"smart_status": {"passed": True}, "ata_smart_attributes": {"table": [
            {"name": "Current_Pending_Sector", "raw": {"value": 4}}]}})
        self.assertEqual(ata["pending_sectors"], 4)

    def test_thermal_fixtures(self):
        report = {"sensors": {"readings": {}}}
        for values, expected in (([{"sensor": "cpu", "temperature_celsius": 50, "critical_celsius": 100}], "PASS"),
                                 ([{"sensor": "cpu", "temperature_celsius": 96, "critical_celsius": 100}], "WARN"),
                                 ([{"sensor": "cpu", "temperature_celsius": 101, "critical_celsius": 100}], "FAIL"),
                                 ([{"sensor": "board", "temperature_celsius": 70}], "PASS")):
            with tempfile.TemporaryDirectory() as directory:
                Path(directory, "thermal.json").write_text(json.dumps(values))
                self.assertEqual(diag.check_thermal(diag.Source(directory), report)["status"], expected)
        self.assertEqual(diag.check_thermal(diag.Source(), report)["status"], "UNKNOWN")
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "thermal.json").write_text("malformed")
            self.assertEqual(diag.check_thermal(diag.Source(directory), report)["status"], "UNKNOWN")

    def test_kernel_targeted_severity(self):
        cases = (("EDAC MC0: 1 CE corrected ECC error\n", "WARN"),
                 ("EDAC MC0: UE uncorrected ECC\n", "FAIL"),
                 ("nvme0: I/O error\n", "FAIL"), ("ata1: hard resetting link\n", "WARN"),
                 ("usb 1-1: USB disconnect\n", "WARN"), ("AER: Corrected error received\n", "WARN"),
                 ("AER: Uncorrected (Fatal) error received\n", "FAIL"))
        for message, expected in cases:
            with tempfile.TemporaryDirectory() as directory:
                Path(directory, "kernel.log").write_text(message)
                self.assertEqual(diag.kernel_check(diag.Source(directory), {})["status"], expected)

    def test_network_disconnected_is_not_failure(self):
        report = {"network": [{"interface": "eth0", "state": "down", "driver": "virtio_net"}]}
        self.assertEqual(diag.check_network(diag.Source(), report)["status"], "WARN")

    def test_battery_health_is_derived(self):
        report = {"power": {"supplies": [{"name": "BAT0", "type": "Battery",
                  "design_capacity": 80000000, "full_charge_capacity": 68000000}]}}
        value = diag.check_battery(diag.Source(), report)
        self.assertEqual(value["evidence"][0]["health_percent"], 85.0)

    def test_schema_and_privacy(self):
        item = diag.result("system.test", "system", "Test", "PASS", "ok",
                           {"serial_number": "secret", "mac_address": "secret"})
        doc = diag.document("quick", [item], diag.utcnow(), 1)
        self.assertEqual(doc["schema_version"], "1.0")
        self.assertEqual(item["evidence"]["serial_number"], "[redacted]")
        self.assertFalse(item["destructive"])
        self.assertEqual(set(diag.STATUSES), {"PASS", "WARN", "FAIL", "UNKNOWN", "SKIPPED", "ERROR"})


if __name__ == "__main__":
    unittest.main()
