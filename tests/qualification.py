#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Qualification engine, evidence separation, bundle, and import tests."""

import importlib.util
import io
import json
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("probe_qualification", ROOT / "src/lib/probe_qualification.py")
QUAL = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(QUAL)


class Args:
    report_dir = ""; release_file = ""; cmdline = ""; identify = "false"; diagnostics = "false"
    environment = "synthetic"; boot_medium = "usb"; iso_sha256 = "a" * 64; artifact_identity = "fixture"; no_run = True; benchmark_smoke = False; stability_smoke = False; benchmark = "false"


class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.work = Path(self.tmp.name)
        report = {"schema_version":"1.1", "probeos":{}, "system":{"manufacturer":"Fixture Co","model":"Laptop","serial_number":"SECRET-SERIAL","uuid":"123e4567-e89b-42d3-a456-426614174000"}, "motherboard":{"manufacturer":"Fixture Board","model":"B1","serial_number":"BOARD-SECRET"}, "firmware":{"boot_mode":"UEFI","secure_boot":"disabled"}, "cpu":[{"model":"Fixture CPU"}], "memory":{"total_bytes":8589934592,"available_bytes":6442450944}, "pci":[], "usb":[], "graphics":[], "storage":[], "network":[]}
        diagnostics = {"schema_version":"1.0", "overall_status":"WARN", "results":[]}
        (self.work/"report.json").write_text(json.dumps(report)); (self.work/"diagnostics.json").write_text(json.dumps(diagnostics))
        (self.work/"release").write_text("PROBEOS_VERSION=development\nPROBEOS_GIT_COMMIT=" + "1"*40 + "\nPROBEOS_ARCHITECTURE=x86_64\nPROBEOS_BOOTLOADER=grub\n")
        (self.work/"cmdline").write_text("quiet")
        Args.report_dir=str(self.work); Args.release_file=str(self.work/"release"); Args.cmdline=str(self.work/"cmdline")
        self.record = QUAL.create_record(Args)
        QUAL.atomic_json(self.work/"qualification.json", self.record)

    def tearDown(self): self.tmp.cleanup()

    def test_schema_aggregation_health_and_identity(self):
        self.assertEqual(self.record["overall_status"], "PASS")
        self.assertEqual(self.record["results"]["diagnostics_health"]["health_status"], "WARN")
        self.assertEqual(self.record["environment_type"], "synthetic")
        serialized = json.dumps(self.record)
        self.assertNotIn("SECRET-SERIAL", serialized); self.assertNotIn("BOARD-SECRET", serialized); self.assertNotIn("123e4567-e89b", serialized)
        self.assertTrue(self.record["machine"]["fingerprint"].startswith("sha256:"))
        self.assertEqual(QUAL.validate_record(self.record), [])
        partial = dict(self.record["results"]); partial["networking"] = QUAL.result("FAIL")
        self.assertEqual(QUAL.aggregate(partial), "PARTIAL")

    def test_fixture_catalog_is_synthetic(self):
        fixture = json.loads((ROOT/"compatibility/fixtures/qualification-cases.json").read_text())
        self.assertEqual(fixture["fixture_type"], "synthetic"); self.assertGreaterEqual(len(fixture["cases"]), 8)

    def test_bundle_manifest_and_import_rejects_synthetic(self):
        bundle = QUAL.export_bundle(self.work/"qualification.json", self.work, self.work)
        with tarfile.open(bundle, "r:gz") as archive:
            names = archive.getnames(); self.assertIn("SHA256SUMS", names); self.assertIn("qualification-manifest.json", names)
            self.assertIn("hardware-report.json", names)
            bundled = json.load(archive.extractfile("qualification.json")); hardware = archive.extractfile("hardware-report.json").read()
            self.assertEqual(bundled["document_links"]["hardware-report.json"]["sha256"], __import__("hashlib").sha256(hardware).hexdigest())
            self.assertTrue(all(not member.issym() for member in archive.getmembers()))
        run = subprocess.run([str(ROOT/"tools/import-qualification"), str(bundle), "--candidate-dir", str(self.work)], text=True, capture_output=True)
        self.assertNotEqual(run.returncode, 0); self.assertIn("must have environment_type physical", run.stderr)

    def test_import_security_path_and_symlink(self):
        for name, member_name, kind in (("traversal.tar.gz", "../qualification.json", "file"), ("link.tar.gz", "qualification.json", "link")):
            path = self.work/name
            with tarfile.open(path, "w:gz") as archive:
                item=tarfile.TarInfo(member_name); data=b"{}"
                if kind == "link": item.type=tarfile.SYMTYPE; item.linkname="/etc/passwd"; item.size=0; archive.addfile(item)
                else: item.size=len(data); archive.addfile(item, io.BytesIO(data))
            run=subprocess.run([str(ROOT/"tools/import-qualification"), str(path)], text=True, capture_output=True)
            self.assertNotEqual(run.returncode,0); self.assertIn("rejected",run.stderr)

    def test_physical_import_candidate_and_duplicate_id(self):
        physical = dict(self.record); physical["environment_type"] = "physical"; physical["provenance"] = "probeos_runtime"
        QUAL.atomic_json(self.work/"qualification.json", physical)
        bundle = QUAL.export_bundle(self.work/"qualification.json", self.work, self.work)
        candidates=self.work/"candidates"; candidates.mkdir(); database=self.work/"database"; database.mkdir()
        run=subprocess.run([str(ROOT/"tools/import-qualification"),str(bundle),"--physical-dir",str(database),"--candidate-dir",str(candidates)],text=True,capture_output=True)
        self.assertEqual(run.returncode,0,run.stderr); candidate=next(candidates.glob("*.json")); value=json.loads(candidate.read_text())
        self.assertEqual(value["review"]["status"],"pending"); self.assertEqual(value["provenance"],"imported_physical_bundle")
        (database/"reviewed.json").write_text(candidate.read_text())
        duplicate=subprocess.run([str(ROOT/"tools/import-qualification"),str(bundle),"--physical-dir",str(database),"--candidate-dir",str(candidates)],text=True,capture_output=True)
        self.assertNotEqual(duplicate.returncode,0); self.assertIn("duplicate qualification_id",duplicate.stderr)

    def test_emulator_never_counts_as_physical(self):
        output=self.work/"compatibility.md"
        subprocess.run([str(ROOT/"tools/generate-compatibility"), "--physical-dir", str(self.work/"empty"), "--output", str(output)], check=True)
        text=output.read_text(); self.assertIn("Reviewed physical machines: 0",text); self.assertIn("PASS (QEMU)",text); self.assertIn("No physical evidence yet",text)


if __name__ == "__main__": unittest.main()
