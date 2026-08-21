#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
IMAGE=${PROBEOS_BUILD_IMAGE:-probeos-builder:alpine-3.19}
ARCH=${ARCH:-x86_64}
BOOTLOADER=${BOOTLOADER:-grub}

if [[ ${PROBEOS_SKIP_DOCKER_BUILD:-0} != 1 ]]; then
    docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$REPO_ROOT"
fi
docker run --rm --privileged \
    -e ARCH="$ARCH" \
    -e BOOTLOADER="$BOOTLOADER" \
    -e GRUB_DEFAULT="${GRUB_DEFAULT:-}" \
    -e SYSLINUX_DEFAULT="${SYSLINUX_DEFAULT:-}" \
    -e PROBEOS_WEB_BIND="${PROBEOS_WEB_BIND:-}" \
    -v "$REPO_ROOT:/workspace" \
    -w /workspace \
    "$IMAGE" build/alpine/build-iso.sh
