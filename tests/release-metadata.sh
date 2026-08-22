#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-metadata-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TEST_REPO="$WORK/repo"
OUT="$WORK/out"
mkdir -p "$TEST_REPO/ci" "$OUT"
cp "$ROOT/ci/version.sh" "$ROOT/ci/generate-release-metadata.sh" "$TEST_REPO/ci/"
git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" config user.name 'ProbeOS metadata test'
git -C "$TEST_REPO" config user.email 'metadata-test@probeos.invalid'
git -C "$TEST_REPO" add ci
git -C "$TEST_REPO" commit -qm 'Create metadata test context'

assert_identity() {
    local description=$1 expected_version=$2 expected_channel=$3
    shift 3
    local identity
    if ! identity=$("$@" "$TEST_REPO/ci/version.sh" release-file); then
        echo "not ok - $description: version.sh failed" >&2
        exit 1
    fi
    if ! grep -Fxq "PROBEOS_VERSION=$expected_version" <<<"$identity" ||
        ! grep -Fxq "PROBEOS_BUILD_CHANNEL=$expected_channel" <<<"$identity"; then
        printf 'not ok - %s\nexpected version=%s channel=%s\nactual identity:\n%s\n' \
            "$description" "$expected_version" "$expected_channel" "$identity" >&2
        exit 1
    fi
    if ! grep -Eq '^PROBEOS_GIT_COMMIT=[0-9a-f]{40}$' <<<"$identity" ||
        ! grep -Fxq 'PROBEOS_ARCHITECTURE=unknown' <<<"$identity"; then
        printf 'not ok - %s: malformed common identity fields:\n%s\n' \
            "$description" "$identity" >&2
        exit 1
    fi
}

assert_identity 'untagged development identity' development development env
assert_identity 'explicit release-candidate identity' 0.1.0-rc.1 release-candidate \
    env PROBEOS_RC_VERSION=0.1.0-rc.1

if invalid_output=$(PROBEOS_RC_VERSION=v0.1.0 "$TEST_REPO/ci/version.sh" release-file 2>&1); then
    echo 'not ok - invalid release-candidate identity accepted' >&2
    exit 1
elif [[ $invalid_output != *'invalid release-candidate version: v0.1.0'* ]]; then
    printf 'not ok - invalid release candidate lacked a useful diagnostic:\n%s\n' \
        "$invalid_output" >&2
    exit 1
fi
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        printf '%s-%s\n' "$arch" "$bootloader" > "$OUT/probeos-$arch-$bootloader.iso"
    done
done
PROBEOS_OUT_DIR="$OUT" PROBEOS_RC_VERSION=0.1.0-rc.1 \
    PROBEOS_BUILD_TIMESTAMP=2026-08-21T00:00:00Z \
    "$TEST_REPO/ci/generate-release-metadata.sh" >/dev/null
(cd "$OUT" && sha256sum -c SHA256SUMS >/dev/null)
if ! jq -e '
    .manifest_version==1 and .probeos_version=="0.1.0-rc.1" and
    .build_channel=="release-candidate" and (.artifacts|length)==4 and
    all(.artifacts[]; (.filename|startswith("probeos-0.1.0-rc.1-")) and
        (.firmware_capabilities|type)=="array" and (.size_bytes|type)=="number")
' "$OUT/release-manifest.json" >/dev/null; then
    echo 'not ok - release-candidate manifest has unexpected metadata' >&2
    jq . "$OUT/release-manifest.json" >&2
    exit 1
fi

git -C "$TEST_REPO" tag v0.1.0
assert_identity 'exact SemVer tag identity' 0.1.0 release \
    env PROBEOS_RC_VERSION=0.1.0-rc.1

echo 'ok - release identity semantics passed'
