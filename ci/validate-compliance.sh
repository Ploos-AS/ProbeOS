#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${PROBEOS_OUT_DIR:-$ROOT/out}
LICENSE_TEXT="$ROOT/LICENSE"

grep -Fq 'GNU GENERAL PUBLIC LICENSE' "$LICENSE_TEXT"
grep -Fq 'Version 3, 29 June 2007' "$LICENSE_TEXT"
stale_pattern='ProbeOS-authored.*M''IT|ProbeOS .*licensed under the M''IT'
if git -C "$ROOT" grep -nE "$stale_pattern" -- \
        ':!docs/build-audit.md'; then
    echo 'stale ProbeOS MIT licensing claim' >&2
    exit 1
fi
grep -Fq 'Memtest86+ is GPLv2' "$ROOT/third_party/README.md"

if [[ ${1:-fast} == fast ]]; then
    python3 -m py_compile "$ROOT/compliance/generate.py" "$ROOT/compliance/validate.py"
    echo 'ok - fast license/compliance validation passed'
    exit 0
fi
[[ ${1:-} == release ]] || { echo "usage: $0 [fast|release]" >&2; exit 2; }
for file in release-manifest.json SOURCE-MANIFEST.json THIRD-PARTY-MANIFEST.json SHA256SUMS; do
    [[ -s $OUT/$file ]] || { echo "missing compliance artifact: $file" >&2; exit 1; }
done
version=$(jq -er '.probeos_version' "$OUT/release-manifest.json")
commit=$(jq -er '.git_commit' "$OUT/release-manifest.json")
jq -e --arg version "$version" --arg commit "$commit" \
    '.manifest_version==1 and .probeos_version==$version and .git_commit==$commit and
     .binary_manifest_version==1 and (.probeos_source.sha256|test("^[0-9a-f]{64}$")) and
     (.license_index.sha256|test("^[0-9a-f]{64}$")) and
     (.package_source_mappings|length)>0 and
     all(.package_source_mappings[]; (.binary_version|length)>0 and
         (.binary_artifacts|length)>0 and
         all(.binary_artifacts[]; .sha256|test("^[0-9a-f]{64}$")) and
         (.license|length)>0 and
         (.source_record|length)>0) and
     (.alpine_sources|length)>0 and
     all(.alpine_sources[]; (.files|length)>0 and all(.files[]; .sha256|test("^[0-9a-f]{64}$"))) and
     .memtest86plus.version=="8.10" and .memtest86plus.license=="GPL-2.0-only" and
     .memtest86plus.source_commit=="494689a7acbd95db8bf41cd74830b60690c9d33d"' \
    "$OUT/SOURCE-MANIFEST.json" >/dev/null
jq -e --arg version "$version" --arg commit "$commit" \
    '.manifest_version==1 and .probeos_version==$version and .git_commit==$commit and
     ([.packages[]|select(.role=="live-apk" and .release_architecture=="x86")]|length)>0 and
     ([.packages[]|select(.role=="live-apk" and .release_architecture=="x86_64")]|length)>0 and
     all(.packages[]; (.license|length)>0 and (.apk_sha256|test("^[0-9a-f]{64}$")) and
         (.aports_commit|test("^[0-9a-f]{40}$")) and (.source_package|length)>0) and
     ([.bootloader_components[].source_package]|index("grub"))!=null and
     ([.bootloader_components[].source_package]|index("syslinux"))!=null and
     all(.bootloader_components[]; (.binary_artifacts|length)>0 and
         all(.binary_artifacts[]; .sha256|test("^[0-9a-f]{64}$")))' \
    "$OUT/THIRD-PARTY-MANIFEST.json" >/dev/null
archive="$OUT/probeos-$version-source.tar.zst"
[[ -s $archive ]] || { echo "source archive missing: $archive" >&2; exit 1; }
(cd "$OUT" && sha256sum -c SHA256SUMS)
listed=$(jq '.artifacts|length' "$OUT/release-manifest.json")
[[ $(wc -l < "$OUT/SHA256SUMS") -eq $((listed + 5)) ]] || {
    echo 'SHA256SUMS does not cover the complete public artifact set' >&2; exit 1;
}
python3 "$ROOT/compliance/validate.py" "$OUT"
echo 'ok - release compliance validation passed'
