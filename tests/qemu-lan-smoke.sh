#!/usr/bin/env bash
set -euo pipefail
ISO=${1:?usage: qemu-lan-smoke.sh ISO [LOG]}
LOG=${2:-"${TMPDIR:-/tmp}/$(basename "${ISO%.iso}")-lan.log"}
TIMEOUT=${PROBEOS_LAN_TIMEOUT:-${PROBEOS_QEMU_TIMEOUT:-300}}
PORT=${PROBEOS_LAN_PORT:-18080}
QEMU=${QEMU:-qemu-system-x86_64}
ACCEL=${PROBEOS_QEMU_ACCEL:-tcg}
ARCH=${PROBEOS_TEST_ARCH:-x86_64}
BOOTLOADER=${PROBEOS_TEST_BOOTLOADER:-grub}
FIRMWARE=${PROBEOS_TEST_FIRMWARE:-bios}
TEST_TYPE=${PROBEOS_TEST_TYPE:-lan-web-api}
qemu_pid=
cleanup() { [ -z "$qemu_pid" ] || kill "$qemu_pid" 2>/dev/null || true; }
trap cleanup EXIT

rm -f "$LOG"
timeout "$TIMEOUT" "$QEMU" -accel "$ACCEL" -m 2048 -smp 2 -cdrom "$ISO" -boot d -display none \
    -serial "file:$LOG" -no-reboot -nic "user,model=e1000,hostfwd=tcp:127.0.0.1:$PORT-10.0.2.15:8080" &
qemu_pid=$!
health=
for _ in $(seq 1 "$TIMEOUT"); do
    health=$(curl -fsS --max-time 2 "http://127.0.0.1:$PORT/api/v1/health" 2>/dev/null || true)
    if [ -n "$health" ] && jq -e '.service=="running" and .report_available==true' <<<"$health" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
[ -n "$health" ] || {
    echo "FAIL: architecture=$ARCH bootloader=$BOOTLOADER firmware=$FIRMWARE test=$TEST_TYPE timeout=${TIMEOUT}s log=$LOG" >&2
    echo "LAN web service did not respond" >&2
    tail -n 120 "$LOG" >&2
    exit 1
}
jq -e '.service=="running" and .api_version=="1" and .report_available==true' <<<"$health" >/dev/null
report=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/report")
jq -e '(.schema_version=="1.0") and ([.network[]? | select(.interface!="lo")] | length >= 1)' <<<"$report" >/dev/null
jq -e '[.. | objects | .serial_number? // empty] | all(. == "[redacted]")' <<<"$report" >/dev/null
jq -e '[.. | objects | .mac_address? // empty] | all(. == "[redacted]")' <<<"$report" >/dev/null
if grep -Eq '[A-Z0-9]{5}(-[A-Z0-9]{5}){4}' <<<"$report"; then
    echo 'product-key-shaped value exposed by LAN API' >&2
    exit 1
fi
curl -fsS "http://127.0.0.1:$PORT/" | grep -Fq 'ProbeOS'
grep -Fq 'PROBEOS_BOOT_OK' "$LOG"
echo "ok - QEMU DHCP/user-network and forwarded ProbeOS Web/API passed"
