#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${PROBEOS_OUT_DIR:-$ROOT/out}
VERSION=${PROBEOS_VERSION:-dev-$(git -C "$ROOT" rev-parse --short=12 HEAD)}
SHA=$(git -C "$ROOT" rev-parse HEAD)
SHORT_SHA=$(git -C "$ROOT" rev-parse --short=12 HEAD)
TIMESTAMP=${PROBEOS_BUILD_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}

if [[ ! $VERSION =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
      ! $VERSION =~ ^dev-[0-9a-f]{7,40}$ ]]; then
    echo "invalid ProbeOS version: $VERSION" >&2
    exit 2
fi

mkdir -p "$OUT"
: > "$OUT/SHA256SUMS"
artifacts='[]'
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        filename="probeos-$arch-$bootloader.iso"
        path="$OUT/$filename"
        [[ -s $path ]] || { echo "missing release artifact: $filename" >&2; exit 1; }
        checksum=$(sha256sum "$path" | awk '{print $1}')
        size=$(stat -c %s "$path")
        printf '%s  %s\n' "$checksum" "$filename" >> "$OUT/SHA256SUMS"
        artifacts=$(jq -c --arg filename "$filename" --arg architecture "$arch" \
            --arg bootloader "$bootloader" --arg sha256 "$checksum" --argjson size "$size" \
            '. + [{filename:$filename,architecture:$architecture,bootloader:$bootloader,size_bytes:$size,sha256:$sha256}]' \
            <<<"$artifacts")
    done
done

jq -n --arg version "$VERSION" --arg git_commit "$SHA" --arg git_short_sha "$SHORT_SHA" \
    --arg build_timestamp "$TIMESTAMP" --arg alpine_version "3.19" \
    --arg memtest_version "8.10" --argjson artifacts "$artifacts" \
    '{schema_version:"1",probeos_version:$version,git_commit:$git_commit,git_short_sha:$git_short_sha,
      build_timestamp:$build_timestamp,alpine_version:$alpine_version,memtest86plus_version:$memtest_version,
      artifacts:$artifacts}' > "$OUT/release-manifest.json"
(cd "$OUT" && sha256sum -c SHA256SUMS)
jq -e --arg sha "$SHA" '.git_commit==$sha and (.artifacts|length)==4' "$OUT/release-manifest.json" >/dev/null
echo "ok - release metadata generated for $VERSION ($SHORT_SHA)"
