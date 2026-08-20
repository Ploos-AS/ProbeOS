#!/usr/bin/env bash
set -euo pipefail

ISO=${1:?usage: memtest-smoke.sh ISO [bios|uefi] [LOG]}
MODE=${2:-bios}
LOG=${3:-"${TMPDIR:-/tmp}/$(basename "${ISO%.iso}")-memtest-${MODE}.log"}
TIMEOUT=${PROBEOS_MEMTEST_TIMEOUT:-30}
QEMU=${QEMU:-qemu-system-x86_64}
qemu_args=(-m 2048 -smp 2 -cdrom "$ISO" -boot d -display none -serial stdio -no-reboot -nic none)
vars=""

case "$MODE" in
    bios) ;;
    uefi)
        code=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
        vars_template=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
        [[ -r "$code" && -r "$vars_template" ]] || { echo 'OVMF firmware not found' >&2; exit 1; }
        vars=$(mktemp "${TMPDIR:-/tmp}/probeos-memtest-ovmf-vars.XXXXXX.fd")
        cp "$vars_template" "$vars"
        qemu_args+=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
        ;;
    *) echo "unknown firmware mode: $MODE" >&2; exit 2 ;;
esac
trap '[[ -z "$vars" ]] || rm -f "$vars"' EXIT

set +e
timeout "$TIMEOUT" "$QEMU" "${qemu_args[@]}" >"$LOG" 2>&1
qemu_status=$?
set -e
[[ $qemu_status -eq 0 || $qemu_status -eq 124 ]] || { tail -n 80 "$LOG" >&2; exit "$qemu_status"; }
grep -Fq 'Memtest86+ v8.10' "$LOG" || {
    echo "Memtest86+ did not start; see $LOG" >&2
    tail -n 120 "$LOG" >&2
    exit 1
}
! grep -Fqi 'PassMark' "$LOG" || { echo 'PassMark payload detected' >&2; exit 1; }
echo "ok - Memtest86+ v8.10 started under $MODE"
