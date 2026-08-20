#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}
ARCH=${ARCH:-x86_64}

docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"
docker run --rm --privileged \
    -e ARCH="$ARCH" \
    -e GRUB_DEFAULT="${GRUB_DEFAULT:-}" \
    -v "$REPO_ROOT:/workspace" \
    -w /workspace \
    "$IMAGE" build/alpine/build-iso.sh
