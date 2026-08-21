#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-metadata-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
identity=$("$ROOT/ci/version.sh" release-file)
grep -Eq '^PROBEOS_GIT_COMMIT=[0-9a-f]{40}$' <<<"$identity"
grep -Eq '^PROBEOS_ARCHITECTURE=unknown$' <<<"$identity"
if git -C "$ROOT" describe --tags --exact-match HEAD >/dev/null 2>&1; then
    grep -Eq '^PROBEOS_BUILD_CHANNEL=release$' <<<"$identity"
else
    grep -Eq '^PROBEOS_VERSION=development$' <<<"$identity"
    grep -Eq '^PROBEOS_BUILD_CHANNEL=development$' <<<"$identity"
fi
PROBEOS_RC_VERSION=0.1.0-rc.1 "$ROOT/ci/version.sh" release-file |
    grep -Eq '^PROBEOS_BUILD_CHANNEL=release-candidate$'
if PROBEOS_RC_VERSION=v0.1.0 "$ROOT/ci/version.sh" release-file >/dev/null 2>&1; then
    echo 'invalid release-candidate identity accepted' >&2
    exit 1
fi
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        printf '%s-%s\n' "$arch" "$bootloader" > "$WORK/probeos-$arch-$bootloader.iso"
    done
done
PROBEOS_OUT_DIR="$WORK" PROBEOS_RC_VERSION=0.1.0-rc.1 \
    PROBEOS_BUILD_TIMESTAMP=2026-08-21T00:00:00Z \
    "$ROOT/ci/generate-release-metadata.sh" >/dev/null
(cd "$WORK" && sha256sum -c SHA256SUMS >/dev/null)
jq -e '
    .manifest_version==1 and .probeos_version=="0.1.0-rc.1" and
    .build_channel=="release-candidate" and (.artifacts|length)==4 and
    all(.artifacts[]; (.filename|startswith("probeos-0.1.0-rc.1-")) and
        (.firmware_capabilities|type)=="array" and (.size_bytes|type)=="number")
' "$WORK/release-manifest.json" >/dev/null
echo 'ok - release identity semantics passed'
