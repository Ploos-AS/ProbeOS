#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}

docker build -t "$IMAGE" -f "$ROOT/build/alpine/Dockerfile" "$ROOT"
for arch in x86 x86_64; do
    docker run --rm -v "$ROOT:/workspace:ro" "$IMAGE" sh -eu -c '
        arch=$1
        packages=$(sed -e "/^[[:space:]]*#/d" -e "/^[[:space:]]*$/d" /workspace/build/alpine/packages.txt)
        # Resolve exactly the repositories and architecture used by the ISO builder.
        apk add --simulate --no-cache --arch "$arch" $packages >/dev/null
    ' sh "$arch"
    echo "ok - Alpine 3.19 package resolution passed for $arch"
done
