#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR=${PROBEOS_LOG_DIR:-$ROOT/ci-logs/qemu}
BACKUP_DIR=$(mktemp -d "$ROOT/out/.probeos-release-isos.XXXXXX")
mkdir -p "$LOG_DIR"

artifacts=(
    probeos-x86_64-grub.iso
    probeos-x86_64-syslinux.iso
    probeos-x86-grub.iso
    probeos-x86-syslinux.iso
)

restore_artifacts() {
    local artifact restore_path
    for artifact in "${artifacts[@]}"; do
        if [[ -f $BACKUP_DIR/$artifact ]]; then
            restore_path="$ROOT/out/.$artifact.restore.$$"
            cp --reflink=auto --preserve=mode,timestamps "$BACKUP_DIR/$artifact" "$restore_path"
            mv -f "$restore_path" "$ROOT/out/$artifact"
        fi
    done
}
cleanup() {
    restore_artifacts
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

for artifact in "${artifacts[@]}"; do
    [[ -s $ROOT/out/$artifact ]] || { echo "missing built artifact: $ROOT/out/$artifact" >&2; exit 1; }
    cp --reflink=auto --preserve=mode,timestamps "$ROOT/out/$artifact" "$BACKUP_DIR/$artifact"
done
(cd "$BACKUP_DIR" && sha256sum "${artifacts[@]}") > "$BACKUP_DIR/SHA256SUMS"

run_timed() {
    local label=$1 arch=$2 bootloader=$3 firmware=$4 test_type=$5 log=$6
    shift 6
    local start end elapsed status=0
    echo "=== QUALIFY $label ==="
    echo "configuration: architecture=$arch bootloader=$bootloader firmware=$firmware test=$test_type timeout=${PROBEOS_ACTIVE_TIMEOUT}s accel=${PROBEOS_QEMU_ACCEL:-tcg} log=$log"
    start=$(date +%s)
    PROBEOS_TEST_ARCH="$arch" PROBEOS_TEST_BOOTLOADER="$bootloader" \
        PROBEOS_TEST_FIRMWARE="$firmware" PROBEOS_TEST_TYPE="$test_type" \
        "$@" || status=$?
    end=$(date +%s)
    elapsed=$((end - start))
    echo "=== RESULT $label: status=$status elapsed=${elapsed}s log=$log ==="
    if (( status != 0 )); then
        echo "FAIL: architecture=$arch bootloader=$bootloader firmware=$firmware test=$test_type timeout=${PROBEOS_ACTIVE_TIMEOUT}s elapsed=${elapsed}s log=$log" >&2
        return "$status"
    fi
}

run_linux() {
    local arch=$1 bootloader=$2 firmware=$3 qemu=qemu-system-x86_64
    local log="$LOG_DIR/probeos-$arch-$bootloader-$firmware.log"
    if [[ $arch == x86 ]]; then
        qemu='qemu-system-i386'
    fi
    PROBEOS_ACTIVE_TIMEOUT=${PROBEOS_QEMU_TIMEOUT:-240} run_timed \
        "$arch ${bootloader^^} ${firmware^^} Linux" "$arch" "$bootloader" "$firmware" \
        linux-offline "$log" env QEMU="$qemu" "$ROOT/tests/qemu-smoke.sh" \
        "$ROOT/out/probeos-$arch-$bootloader.iso" "$firmware" "$log"
}

run_memtest() {
    local arch=$1 bootloader=$2 firmware=$3 qemu=qemu-system-x86_64
    local log="$LOG_DIR/probeos-$arch-$bootloader-memtest-$firmware.log"
    if [[ $arch == x86 ]]; then
        qemu='qemu-system-i386'
    fi
    PROBEOS_ACTIVE_TIMEOUT=${PROBEOS_MEMTEST_TIMEOUT:-${PROBEOS_QEMU_TIMEOUT:-60}} run_timed \
        "$arch ${bootloader^^} ${firmware^^} Memtest86+" "$arch" "$bootloader" "$firmware" \
        memtest86+ "$log" env QEMU="$qemu" "$ROOT/tests/memtest-smoke.sh" \
        "$ROOT/out/probeos-$arch-$bootloader.iso" "$firmware" "$log"
}

run_linux x86_64 grub bios
run_linux x86_64 grub uefi
run_linux x86 grub bios
run_linux x86_64 syslinux bios
run_linux x86 syslinux bios

# LAN mode is an explicit runtime build choice. Keep the distributable ISO in
# BACKUP_DIR and restore it immediately after testing this qualification-only
# derivative.
ARCH=x86_64 BOOTLOADER=grub PROBEOS_WEB_BIND=0.0.0.0 PROBEOS_SKIP_DOCKER_BUILD=1 \
    "$ROOT/build/alpine/build-container.sh"
lan_log="$LOG_DIR/probeos-x86_64-grub-lan.log"
PROBEOS_ACTIVE_TIMEOUT=${PROBEOS_LAN_TIMEOUT:-${PROBEOS_QEMU_TIMEOUT:-300}} run_timed \
    "x86_64 GRUB BIOS LAN/Web/API" x86_64 grub bios lan-web-api "$lan_log" \
    "$ROOT/tests/qemu-lan-smoke.sh" "$ROOT/out/probeos-x86_64-grub.iso" "$lan_log"
restore_artifacts

# Memtest qualification uses controlled default-menu derivatives. The four
# normal artifacts above remain in BACKUP_DIR and are restored after each build.
for arch in x86_64 x86; do
    for bootloader in grub syslinux; do
        if [[ $bootloader == grub ]]; then
            ARCH="$arch" BOOTLOADER=grub GRUB_DEFAULT=2 PROBEOS_SKIP_DOCKER_BUILD=1 \
                "$ROOT/build/alpine/build-container.sh"
        else
            ARCH="$arch" BOOTLOADER=syslinux SYSLINUX_DEFAULT=memtest PROBEOS_SKIP_DOCKER_BUILD=1 \
                "$ROOT/build/alpine/build-container.sh"
        fi
        run_memtest "$arch" "$bootloader" bios
        if [[ $arch == x86_64 && $bootloader == grub ]]; then
            run_memtest x86_64 grub uefi
        fi
        restore_artifacts
    done
done

(cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
for artifact in "${artifacts[@]}"; do
    cmp -s "$BACKUP_DIR/$artifact" "$ROOT/out/$artifact" || {
        echo "qualified release artifact changed: $artifact" >&2
        exit 1
    }
done
echo 'ok - exact Linux-qualified release ISOs preserved for metadata and publication'
