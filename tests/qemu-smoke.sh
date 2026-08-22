#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ISO=${1:?usage: qemu-smoke.sh ISO [bios|uefi] [LOG]}
MODE=${2:-bios}
LOG=${3:-"${TMPDIR:-/tmp}/$(basename "${ISO%.iso}")-${MODE}.log"}
TIMEOUT=${PROBEOS_QEMU_TIMEOUT:-240}
QEMU=${QEMU:-qemu-system-x86_64}
ACCEL=${PROBEOS_QEMU_ACCEL:-tcg}
ARCH=${PROBEOS_TEST_ARCH:-unknown}
BOOTLOADER=${PROBEOS_TEST_BOOTLOADER:-unknown}
TEST_TYPE=${PROBEOS_TEST_TYPE:-linux-offline}
qemu_args=(-accel "$ACCEL" -m 2048 -smp 2 -cdrom "$ISO" -boot d -display none -serial stdio -no-reboot -nic none)
vars=""
qemu_pid=""

case "$MODE" in
    bios) expected_firmware=BIOS ;;
    uefi)
        expected_firmware=UEFI
        code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
        vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
        [[ -r "$code" && -r "$vars_template" ]] || { echo 'OVMF firmware not found' >&2; exit 1; }
        vars=$(mktemp "${TMPDIR:-/tmp}/probeos-ovmf-vars.XXXXXX.fd")
        cp "$vars_template" "$vars"
        qemu_args+=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
        ;;
    *) echo "unknown firmware mode: $MODE" >&2; exit 2 ;;
esac
marker="PROBEOS_BOOT_OK init=/sbin/init probe-identify=present report_txt=present report_json=valid diagnostics_json=valid"
cleanup() {
    [[ -z $qemu_pid ]] || kill "$qemu_pid" 2>/dev/null || true
    [[ -z $vars ]] || rm -f "$vars"
}
trap cleanup EXIT

rm -f "$LOG"
timeout "$TIMEOUT" "$QEMU" "${qemu_args[@]}" >"$LOG" 2>&1 &
qemu_pid=$!
found=0
for _ in $(seq 1 "$TIMEOUT"); do
    if grep -Fq "$marker" "$LOG" 2>/dev/null; then found=1; break; fi
    kill -0 "$qemu_pid" 2>/dev/null || break
    sleep 1
done
[[ $found == 1 ]] || {
    echo "FAIL: architecture=$ARCH bootloader=$BOOTLOADER firmware=$MODE test=$TEST_TYPE timeout=${TIMEOUT}s log=$LOG" >&2
    echo "ProbeOS userspace marker not found" >&2
    tail -n 120 "$LOG" >&2
    exit 1
}
grep -Eq "quick_seconds=[0-9]+ firmware=$expected_firmware" "$LOG" || {
    echo "Quick Check runtime or firmware marker missing; see $LOG" >&2
    exit 1
}
case $(basename "$ISO") in
    *-syslinux.iso)
        grep -Fq 'ProbeOS - Legacy BIOS' "$LOG" || {
            echo "ProbeOS SYSLINUX menu marker not found; see $LOG" >&2
            exit 1
        }
        ;;
esac
echo "ok - $MODE reached ProbeOS userspace and generated valid hardware and Quick Check reports"
