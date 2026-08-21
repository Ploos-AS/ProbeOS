#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${PROBEOS_OUT_DIR:-$ROOT/out}
eval "$("$ROOT/ci/version.sh" shell)"
TIMESTAMP=${PROBEOS_BUILD_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

mkdir -p "$OUT"
: > "$OUT/SHA256SUMS"
artifacts='[]'
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        source_name="probeos-$arch-$bootloader.iso"
        if [[ $PROBEOS_BUILD_CHANNEL == development ]]; then
            filename=$source_name
        else
            filename="probeos-$PROBEOS_VERSION-$arch-$bootloader.iso"
            cp -f "$OUT/$source_name" "$OUT/$filename"
        fi
        path="$OUT/$filename"
        [[ -s $path ]] || { echo "missing release artifact: $filename" >&2; exit 1; }
        checksum=$(sha256sum "$path" | awk '{print $1}')
        size=$(stat -c %s "$path")
        printf '%s  %s\n' "$checksum" "$filename" >> "$OUT/SHA256SUMS"
        if [[ $bootloader == grub && $arch == x86_64 ]]; then firmware='["BIOS","UEFI"]'; else firmware='["BIOS"]'; fi
        artifacts=$(jq -c --arg filename "$filename" --arg architecture "$arch" \
            --arg bootloader "$bootloader" --arg sha256 "$checksum" --argjson size "$size" \
            --argjson firmware "$firmware" \
            '. + [{filename:$filename,architecture:$architecture,bootloader:$bootloader,firmware_capabilities:$firmware,size_bytes:$size,sha256:$sha256}]' \
            <<<"$artifacts")
    done
done

jq -n --arg version "$PROBEOS_VERSION" --arg channel "$PROBEOS_BUILD_CHANNEL" \
    --arg git_commit "$PROBEOS_GIT_COMMIT" --arg git_short_sha "$PROBEOS_GIT_SHORT_SHA" \
    --arg build_timestamp "$TIMESTAMP" --arg alpine_version "3.19" \
    --arg memtest_version "8.10" --argjson artifacts "$artifacts" \
    '{manifest_version:1,probeos_version:$version,build_channel:$channel,git_commit:$git_commit,git_short_sha:$git_short_sha,
      build_timestamp:$build_timestamp,alpine_version:$alpine_version,memtest86plus_version:$memtest_version,
      artifacts:$artifacts}' > "$OUT/release-manifest.json"
(cd "$OUT" && sha256sum -c SHA256SUMS)
jq -e --arg sha "$PROBEOS_GIT_COMMIT" \
    '.manifest_version==1 and .git_commit==$sha and (.artifacts|length)==4 and
     ([.artifacts[].filename]|length==4) and ([.artifacts[].sha256]|unique|length==4)' \
    "$OUT/release-manifest.json" >/dev/null
echo "ok - release metadata generated for $PROBEOS_VERSION ($PROBEOS_GIT_SHORT_SHA)"
