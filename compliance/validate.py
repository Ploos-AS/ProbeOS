#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate release binaries against the complete source/compliance archive."""

import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_file(root, record):
    path = root / record["path"]
    if not path.is_file() or sha256(path) != record["sha256"]:
        raise RuntimeError(f"missing or mismatched source file: {record['path']}")


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "out").resolve()
    release = json.loads((out / "release-manifest.json").read_text())
    sources = json.loads((out / "SOURCE-MANIFEST.json").read_text())
    packages = json.loads((out / "THIRD-PARTY-MANIFEST.json").read_text())
    identity = (release["probeos_version"], release["git_commit"])
    if (sources["probeos_version"], sources["git_commit"]) != identity or \
            (packages["probeos_version"], packages["git_commit"]) != identity:
        raise RuntimeError("binary/source/package manifest identity mismatch")
    archive = out / f"probeos-{identity[0]}-source.tar.zst"
    # Source bundles commonly exceed small RAM-backed /tmp filesystems. Keep
    # validation scratch space beside the release output, where the archive was
    # successfully created and free-space expectations are already established.
    with tempfile.TemporaryDirectory(prefix=".compliance-validate-", dir=out) as temporary:
        temporary = Path(temporary)
        subprocess.run(("tar", "--zstd", "-xf", str(archive), "-C", str(temporary)), check=True)
        root = temporary / "source"
        for name in ("SOURCE-MANIFEST.json", "THIRD-PARTY-MANIFEST.json"):
            if (root / "manifests" / name).read_bytes() != (out / name).read_bytes():
                raise RuntimeError(f"embedded {name} differs from public manifest")
        probeos = root / sources["probeos_source"]["artifact"]
        if not probeos.is_file() or sha256(probeos) != sources["probeos_source"]["sha256"]:
            raise RuntimeError("ProbeOS source archive missing or mismatched")
        license_index = root / sources["license_index"]["artifact"]
        if not license_index.is_file() or sha256(license_index) != sources["license_index"]["sha256"]:
            raise RuntimeError("license index missing or mismatched")
        for source in sources["alpine_sources"]:
            for record in source["files"]:
                require_file(root, record)
        memtest = sources["memtest86plus"]
        checks = (("source_artifact", "source_sha256"),
                  ("binary_archive", "binary_archive_sha256"))
        for path_key, hash_key in checks:
            path = root / memtest[path_key]
            if not path.is_file() or sha256(path) != memtest[hash_key]:
                raise RuntimeError(f"Memtest86+ {path_key} missing or mismatched")

        source_keys = {(item["component"], item["aports_commit"])
                       for item in sources["alpine_sources"]}
        package_keys = {(item["source_package"], item["aports_commit"])
                        for item in packages["packages"] + packages["bootloader_components"]}
        if source_keys != package_keys:
            raise RuntimeError("APK-to-corresponding-source mapping is incomplete")
        mappings = {(item["role"], item["component"], item["binary_version"]): item
                    for item in sources["package_source_mappings"]}
        all_components = packages["packages"] + packages["bootloader_components"]
        expected_mappings = {(item["role"], item["name"], item["version"]): item
                             for item in all_components}
        if set(mappings) != set(expected_mappings):
            raise RuntimeError("SOURCE-MANIFEST package mapping is incomplete")
        for key, package in expected_mappings.items():
            mapping = mappings[key]
            if (mapping["license"] != package["license"] or
                    (mapping["source_package"], mapping["aports_commit"]) not in source_keys):
                raise RuntimeError(f"invalid package/source relationship: {key}")
            if mapping["role"] == "bootloader-build-input":
                for artifact in mapping["binary_artifacts"]:
                    binary = out / artifact["filename"]
                    if not binary.is_file() or sha256(binary) != artifact["sha256"]:
                        raise RuntimeError(f"missing or mismatched mapped binary: {artifact['filename']}")
        if not {"grub", "syslinux"}.issubset({item["source_package"]
                                               for item in packages["bootloader_components"]}):
            raise RuntimeError("GRUB/SYSLINUX builder provenance is incomplete")

        inventory = {(item["release_architecture"], item["apk_filename"]): item
                     for item in packages["packages"] if item["role"] == "live-apk"}
        observed = set()
        for artifact in release["artifacts"]:
            if artifact["bootloader"] != "grub":
                continue
            arch = artifact["architecture"]
            destination = temporary / f"apks-{arch}"
            destination.mkdir()
            subprocess.run(("xorriso", "-osirrox", "on", "-indev", str(out / artifact["filename"]),
                            "-extract", f"/apks/{arch}", str(destination)),
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for apk in destination.glob("*.apk"):
                key = (arch, apk.name)
                if key not in inventory or sha256(apk) != inventory[key]["apk_sha256"]:
                    raise RuntimeError(f"uninventoried or mismatched APK: {arch}/{apk.name}")
                observed.add(key)
        if observed != set(inventory):
            raise RuntimeError("inventory contains APKs absent from release ISOs")
    serialized = json.dumps({"sources": sources, "packages": packages}).lower()
    if any(word in serialized for word in ("placeholder", "todo", "unresolved")):
        raise RuntimeError("unresolved placeholder in compliance manifests")
    print("ok - archive contents, APK inventory, and source mappings verified")


if __name__ == "__main__":
    main()
