#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build fail-closed package inventories and a corresponding-source bundle."""

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APORTS_URL = "https://gitlab.alpinelinux.org/alpine/aports.git"
MEMTEST_URL = "https://github.com/memtest86plus/memtest86plus.git"
MEMTEST_COMMIT = "494689a7acbd95db8bf41cd74830b60690c9d33d"
MEMTEST_BINARY_URL = "https://memtest.org/download/v8.10/mt86plus_8.10.binaries.zip"
MEMTEST_BINARY_SHA256 = "7e6c5162cb84ab959aeb9d13c9cfd6976b0dec3b34936b73820b20c55eb26c29"


def run(*args, cwd=None, capture=False):
    result = subprocess.run(args, cwd=cwd, check=True, text=capture,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else ""


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_pkginfo(apk):
    with tarfile.open(apk, "r:gz") as archive:
        data = archive.extractfile(".PKGINFO").read().decode("utf-8")
    values = {}
    for line in data.splitlines():
        key, separator, value = line.partition(" = ")
        if separator and key not in values:
            values[key] = value
    required = ("pkgname", "pkgver", "arch", "origin", "commit", "license", "url")
    missing = [key for key in required if not values.get(key)]
    if missing:
        raise RuntimeError(f"{apk.name}: missing .PKGINFO fields: {', '.join(missing)}")
    return values


def parse_installed_database(path):
    fields = {"P": "pkgname", "V": "pkgver", "A": "arch", "o": "origin",
              "c": "commit", "L": "license", "U": "url"}
    records = []
    for paragraph in path.read_text().split("\n\n"):
        values = {}
        for line in paragraph.splitlines():
            key, separator, value = line.partition(":")
            if separator and key in fields:
                values[fields[key]] = value
        if values:
            records.append(values)
    return records


def safe(value):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", value)


def clone_or_update(url, branch, destination):
    if not destination.exists():
        run("git", "clone", "--filter=blob:none", "--single-branch", "--branch", branch,
            url, str(destination))
    else:
        run("git", "-C", str(destination), "fetch", "--force", "origin", branch)


def export_recipe(aports, origin, commit, destination):
    paths = run("git", "-C", str(aports), "ls-tree", "-r", "--name-only", commit,
                capture=True).splitlines()
    matches = [p for p in paths if p.endswith(f"/{origin}/APKBUILD")]
    if len(matches) != 1:
        raise RuntimeError(f"{origin}@{commit}: expected one APKBUILD, found {matches}")
    recipe_path = str(Path(matches[0]).parent)
    destination.mkdir(parents=True)
    archive = subprocess.run(("git", "-C", str(aports), "archive", commit, recipe_path),
                             check=True, stdout=subprocess.PIPE).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        source.extractall(destination, filter="data")
    exported = destination / recipe_path
    if not (exported / "APKBUILD").is_file():
        raise RuntimeError(f"failed to export {origin}@{commit}")
    return exported


def download(url, destination, expected=None):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, open(destination, "wb") as output:
        shutil.copyfileobj(response, output)
    actual = sha256(destination)
    if expected and actual != expected:
        raise RuntimeError(f"checksum mismatch for {url}: {actual}")
    return actual


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "out"))
    parser.add_argument("--work", default=str(ROOT / "out" / "compliance-work"))
    args = parser.parse_args()
    out = Path(args.out).resolve()
    work = Path(args.work).resolve()
    release = json.loads((out / "release-manifest.json").read_text())
    version = release["probeos_version"]
    commit = release["git_commit"]
    if run("git", "-C", str(ROOT), "rev-parse", "HEAD", capture=True).strip() != commit:
        raise RuntimeError("release manifest commit does not match HEAD")

    stage = work / "stage"
    if stage.exists():
        shutil.rmtree(stage)
    bundle = stage / "source"
    manifests = bundle / "manifests"
    manifests.mkdir(parents=True)
    extracted = work / "apks"
    if extracted.exists():
        shutil.rmtree(extracted)
    packages = []
    for arch in ("x86", "x86_64"):
        artifact = next(item for item in release["artifacts"]
                        if item["architecture"] == arch and item["bootloader"] == "grub")
        apk_dir = extracted / arch
        apk_dir.mkdir(parents=True)
        run("xorriso", "-osirrox", "on", "-indev", str(out / artifact["filename"]),
            "-extract", f"/apks/{arch}", str(apk_dir))
        for apk in sorted(apk_dir.glob("*.apk")):
            info = parse_pkginfo(apk)
            packages.append({
                "role": "live-apk", "name": info["pkgname"], "version": info["pkgver"],
                "architecture": info["arch"], "release_architecture": arch,
                "apk_filename": apk.name,
                "apk_sha256": sha256(apk), "apk_data_sha256": info.get("datahash"),
                "source_package": info["origin"], "aports_commit": info["commit"],
                "license": info["license"], "upstream": info["url"],
            })

    builder_metadata = work / "builder-installed"
    builder_metadata.mkdir(parents=True, exist_ok=True)
    installed_db = builder_metadata / "installed"
    run("docker", "run", "--rm", "-v", f"{builder_metadata}:/output",
        "probeos-builder:alpine-3.19", "cp", "/lib/apk/db/installed", "/output/installed")
    installed = {item.get("pkgname"): item for item in parse_installed_database(installed_db)}
    boot_components = []
    for name in ("grub", "grub-bios", "grub-efi", "syslinux"):
        info = installed.get(name)
        missing = [key for key in ("pkgname", "pkgver", "arch", "origin", "commit",
                                    "license", "url") if not info or not info.get(key)]
        if missing:
            raise RuntimeError(f"builder package {name}: missing installed metadata {missing}")
        bootloader = "syslinux" if name == "syslinux" else "grub"
        binary_artifacts = [{"filename": item["filename"], "sha256": item["sha256"],
                             "architecture": item["architecture"]}
                            for item in release["artifacts"]
                            if item["bootloader"] == bootloader]
        boot_components.append({
            "role": "bootloader-build-input", "name": info["pkgname"],
            "version": info["pkgver"], "architecture": info["arch"],
            "binary_artifacts": binary_artifacts, "source_package": info["origin"],
            "aports_commit": info["commit"], "license": info["license"],
            "upstream": info["url"],
        })

    third_party = {
        "manifest_version": 1, "probeos_version": version, "git_commit": commit,
        "alpine_branch": "3.19-stable", "packages": packages,
        "bootloader_components": boot_components,
    }
    inventory_path = out / "THIRD-PARTY-MANIFEST.json"
    inventory_path.write_text(json.dumps(third_party, indent=2) + "\n")
    shutil.copy2(inventory_path, manifests / inventory_path.name)

    aports = work / "aports"
    clone_or_update(APORTS_URL, "3.19-stable", aports)
    records = []
    jobs = []
    by_source = {}
    for package in packages + boot_components:
        key = (package["source_package"], package["aports_commit"])
        by_source.setdefault(key, set()).add(package["architecture"])
    alpine_root = bundle / "alpine"
    for (origin, aports_commit), arches in sorted(by_source.items()):
        record_id = safe(f"{origin}-{aports_commit[:12]}")
        root = alpine_root / record_id
        recipe = export_recipe(aports, origin, aports_commit, root / "recipe-tree")
        source_dir = root / "distfiles"
        source_dir.mkdir(parents=True)
        relative_recipe = recipe.relative_to(bundle)
        for arch in sorted(arches):
            jobs.append((str(relative_recipe), str(source_dir.relative_to(bundle)), arch))
        records.append({"id": record_id, "component": origin,
                        "aports_commit": aports_commit,
                        "architectures": sorted(arches), "recipe_path": str(relative_recipe),
                        "source_path": str(source_dir.relative_to(bundle)),
                        "upstream": APORTS_URL})

    jobs_path = bundle / "metadata" / "alpine-source-jobs.tsv"
    jobs_path.parent.mkdir(parents=True)
    jobs_path.write_text("".join("\t".join(job) + "\n" for job in jobs))
    run("docker", "run", "--rm", "-v", f"{bundle}:/bundle",
        "probeos-builder:alpine-3.19", "sh", "-ec",
        "while IFS=$(printf '\\t') read -r recipe sources arch; do "
        "echo source-fetch:$recipe:$arch; cd /bundle/$recipe; export CARCH=$arch; "
        ". ./APKBUILD; for item in $source; do case $item in *://*) "
        "case $item in *::*) name=${item%%::*};; *) name=${item##*/}; name=${name%%\\?*};; esac; "
        "if [ ! -f /bundle/$sources/$name ]; then "
        "curl -fL --retry 3 -o /bundle/$sources/$name "
        "https://distfiles.alpinelinux.org/distfiles/v3.19/$name || rm -f /bundle/$sources/$name; fi;; esac; done; "
        "abuild -F -s /bundle/$sources fetch verify; done < /bundle/metadata/alpine-source-jobs.tsv")

    memtest = bundle / "memtest86plus"
    memtest.mkdir(parents=True)
    binary_checksum = download(MEMTEST_BINARY_URL, memtest / "mt86plus_8.10.binaries.zip",
                               MEMTEST_BINARY_SHA256)
    memtest_repo = work / "memtest86plus"
    if not memtest_repo.exists():
        run("git", "clone", MEMTEST_URL, str(memtest_repo))
    else:
        run("git", "-C", str(memtest_repo), "fetch", "--tags", "origin")
    resolved = run("git", "-C", str(memtest_repo), "rev-parse", "v8.10^{commit}", capture=True).strip()
    if resolved != MEMTEST_COMMIT:
        raise RuntimeError(f"Memtest86+ v8.10 resolved to {resolved}")
    memtest_source = memtest / "memtest86plus-v8.10.tar"
    with open(memtest_source, "wb") as output:
        subprocess.run(("git", "-C", str(memtest_repo), "archive", "--format=tar",
                        "--prefix=memtest86plus-v8.10/", MEMTEST_COMMIT), check=True, stdout=output)

    probeos = bundle / "probeos"
    probeos.mkdir()
    probeos_source = probeos / f"probeos-{version}.tar"
    with open(probeos_source, "wb") as output:
        subprocess.run(("git", "-C", str(ROOT), "archive", "--format=tar",
                        f"--prefix=probeos-{version}/", commit), check=True, stdout=output)
    shutil.copy2(ROOT / "LICENSE", bundle / "LICENSE.GPL-3.0-or-later")

    for record in records:
        record_root = bundle / Path(record["recipe_path"]).parents[2]
        record["files"] = [{"path": str(path.relative_to(bundle)), "sha256": sha256(path)}
                           for path in sorted(record_root.rglob("*")) if path.is_file()]
        if not record["files"]:
            raise RuntimeError(f"no corresponding source files for {record['id']}")
    source_mappings = [{
        "role": package["role"], "component": package["name"],
        "binary_version": package["version"],
        "binary_architecture": package["architecture"],
        "binary_artifacts": ([{"filename": package["apk_filename"],
                               "sha256": package["apk_sha256"],
                               "architecture": package["release_architecture"]}]
                             if package["role"] == "live-apk"
                             else package["binary_artifacts"]),
        "license": package["license"],
        "source_package": package["source_package"],
        "aports_commit": package["aports_commit"],
        "source_record": safe(f"{package['source_package']}-{package['aports_commit'][:12]}"),
        "upstream": package["upstream"],
    } for package in packages + boot_components]
    license_index = {
        "manifest_version": 1, "probeos_version": version, "git_commit": commit,
        "licenses": [{"expression": expression,
                      "components": sorted({item["name"] for item in packages + boot_components
                                            if item["license"] == expression})}
                     for expression in sorted({item["license"] for item in packages + boot_components})],
        "notice": ("License expressions are preserved verbatim from Alpine package metadata. "
                   "The corresponding recipe trees and upstream source distfiles contain the "
                   "authoritative license and notice files supplied by each project."),
    }
    license_index_path = bundle / "metadata" / "LICENSE-INDEX.json"
    license_index_path.write_text(json.dumps(license_index, indent=2) + "\n")
    source_manifest = {
        "manifest_version": 1, "probeos_version": version, "git_commit": commit,
        "binary_manifest_version": release["manifest_version"],
        "probeos_source": {"artifact": str(probeos_source.relative_to(bundle)),
                           "sha256": sha256(probeos_source)},
        "package_source_mappings": source_mappings,
        "license_index": {"artifact": str(license_index_path.relative_to(bundle)),
                          "sha256": sha256(license_index_path)},
        "alpine_sources": records,
        "memtest86plus": {"version": "8.10", "license": "GPL-2.0-only",
            "upstream": MEMTEST_URL, "source_commit": MEMTEST_COMMIT,
            "source_artifact": str(memtest_source.relative_to(bundle)),
            "source_sha256": sha256(memtest_source),
            "binary_archive": str((memtest / "mt86plus_8.10.binaries.zip").relative_to(bundle)),
            "binary_archive_sha256": binary_checksum},
    }
    source_path = out / "SOURCE-MANIFEST.json"
    source_path.write_text(json.dumps(source_manifest, indent=2) + "\n")
    shutil.copy2(source_path, manifests / source_path.name)
    (bundle / "README.md").write_text(
        "# ProbeOS corresponding source\n\n"
        f"Release identity: {version}, commit `{commit}`.\n\n"
        "This bundle contains the exact ProbeOS source archive, Alpine aports recipe trees "
        "and verified distfiles for every redistributed APK and bootloader build input, and "
        "the exact Memtest86+ 8.10 source and binary archives. See `manifests/`.\n")

    archive = out / f"probeos-{version}-source.tar.zst"
    if archive.exists():
        archive.unlink()
    run("tar", "--sort=name", "--mtime=@0", "--owner=0", "--group=0", "--numeric-owner",
        "-C", str(stage), "--zstd", "-cf", str(archive), "source")

    notes_version = version.split("-rc.", 1)[0]
    notes_source = ROOT / "docs" / "releases" / f"v{notes_version}.md"
    if not notes_source.is_file():
        raise RuntimeError(f"reviewed release notes missing: {notes_source}")
    notes = out / "release-notes.md"
    shutil.copy2(notes_source, notes)
    public = [out / item["filename"] for item in release["artifacts"]]
    public += [archive, out / "release-manifest.json", source_path, inventory_path, notes]
    with open(out / "SHA256SUMS", "w", encoding="utf-8") as checksums:
        for path in public:
            checksums.write(f"{sha256(path)}  {path.name}\n")
    run("sha256sum", "-c", "SHA256SUMS", cwd=out)
    print(f"ok - source compliance bundle generated: {archive.name}")


if __name__ == "__main__":
    main()
