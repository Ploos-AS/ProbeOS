#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SHA=$(git -C "$ROOT" rev-parse HEAD)
SHORT_SHA=$(git -C "$ROOT" rev-parse --short=12 HEAD)
ARCH=${ARCH:-unknown}
TAG=$(git -C "$ROOT" describe --tags --exact-match HEAD 2>/dev/null || true)

if [[ $TAG =~ ^v(0|[1-9][0-9]*)\.([0-9]+)\.([0-9]+)$ ]]; then
    VERSION=${TAG#v}
    CHANNEL=release
elif [[ -n ${PROBEOS_RC_VERSION:-} ]]; then
    [[ $PROBEOS_RC_VERSION =~ ^(0|[1-9][0-9]*)\.([0-9]+)\.([0-9]+)-rc\.([1-9][0-9]*)$ ]] || {
        echo "invalid release-candidate version: $PROBEOS_RC_VERSION" >&2
        exit 2
    }
    VERSION=$PROBEOS_RC_VERSION
    CHANNEL=release-candidate
else
    VERSION=development
    CHANNEL=development
fi

case ${1:-shell} in
    shell)
        printf 'PROBEOS_VERSION=%q\nPROBEOS_BUILD_CHANNEL=%q\nPROBEOS_GIT_COMMIT=%q\nPROBEOS_GIT_SHORT_SHA=%q\nPROBEOS_ARCHITECTURE=%q\n' \
            "$VERSION" "$CHANNEL" "$SHA" "$SHORT_SHA" "$ARCH"
        ;;
    release-file)
        printf 'PROBEOS_VERSION=%s\n' "$VERSION"
        printf 'PROBEOS_BUILD_CHANNEL=%s\n' "$CHANNEL"
        printf 'PROBEOS_GIT_COMMIT=%s\n' "$SHA"
        printf 'PROBEOS_GIT_SHORT_SHA=%s\n' "$SHORT_SHA"
        printf 'PROBEOS_ARCHITECTURE=%s\n' "$ARCH"
        ;;
    *) echo "usage: $0 [shell|release-file]" >&2; exit 2 ;;
esac
