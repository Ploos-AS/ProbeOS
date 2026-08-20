#!/usr/bin/env bash
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PROBE="$ROOT/src/scripts/probe-identify"
LIB="$ROOT/src/lib/probe-identify-lib.sh"
FIXTURES="$ROOT/tests/fixtures"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Resolved repository path above.
# shellcheck disable=SC1090
. "$LIB"

fail() { echo "not ok - $*" >&2; exit 1; }
assert_jq() { jq -e "$2" "$1" >/dev/null || fail "$3"; }

cpu=$(parse_cpu "$FIXTURES/full/lscpu")
jq -e '.[0].vendor=="GenuineIntel" and .[0].cores==8 and .[0].threads=="16" and .[0].virtualization=="VT-x"' <<<"$cpu" >/dev/null || fail 'CPU parsing'
[[ $(dmi_value "$FIXTURES/full/dmidecode" 'System Information' 'Product Name') == 'Fixture Workstation' ]] || fail 'DMI parsing'
pci=$(parse_pci "$FIXTURES/full/lspci")
jq -e 'length==2 and .[0].vendor_id=="8086" and .[0].driver=="i915"' <<<"$pci" >/dev/null || fail 'PCI parsing'
storage=$(parse_storage "$FIXTURES/full/lsblk")
jq -e 'length==1 and .[0].device=="/dev/sda" and .[0].capacity_bytes==1000204886016' <<<"$storage" >/dev/null || fail 'storage parsing'
PROBE_FIXTURE_DIR="$FIXTURES/full"; export PROBE_FIXTURE_DIR
storage=$(enrich_storage "$storage" /dev/null)
jq -e '.[0].smart.capable==true and .[0].smart.status==true' <<<"$storage" >/dev/null || fail 'SMART parsing'

[[ $(parse_pci /dev/null) == '[]' ]] || fail 'missing hardware'
[[ $(parse_storage "$FIXTURES/malformed/lsblk") == '[]' ]] || fail 'malformed storage output'
PROBE_FIXTURE_DIR="$FIXTURES/empty"; export PROBE_FIXTURE_DIR
[[ -z $(run command_that_does_not_exist 2>/dev/null || true) ]] || fail 'missing command behavior'

mkdir -p "$FIXTURES/empty" "$WORK/absent" "$WORK/full" "$WORK/malformed"
"$PROBE" --fixture-dir "$FIXTURES/empty" --output-dir "$WORK/absent" --no-windows-mount >/dev/null
assert_jq "$WORK/absent/report.json" '.windows.firmware_license.msdm_present==false and (.windows.installations|length)==0' 'MSDM/Windows absence'

"$PROBE" --fixture-dir "$FIXTURES/full" --output-dir "$WORK/full" --no-windows-mount >/dev/null
assert_jq "$WORK/full/report.json" '.windows.firmware_license.oem_key_found==true and .windows.firmware_license.key_masked=="*****-*****-*****-*****-AB234"' 'MSDM/key masking'
! grep -q 'XXXXX-XXXXX-XXXXX-XXXXX-AB234' "$WORK/full/report.json" || fail 'full key leaked into JSON'
assert_jq "$WORK/full/report.json" '.schema_version=="1.0" and (.cpu|length)==1 and (.pci|length)==2 and (.windows.installations|length)==1' 'report generation'
jq empty "$WORK/full/report.json" || fail 'valid JSON'
[[ -s "$WORK/full/report.txt" ]] || fail 'text report generation'

"$PROBE" --fixture-dir "$FIXTURES/malformed" --output-dir "$WORK/malformed" --no-windows-mount >/dev/null
jq empty "$WORK/malformed/report.json" || fail 'malformed inputs still produce valid JSON'

keyfile="$WORK/key"
"$PROBE" --fixture-dir "$FIXTURES/full" --output-dir "$WORK/full" --no-windows-mount --export-key "$keyfile" >/dev/null
[[ $(cat "$keyfile") == 'XXXXX-XXXXX-XXXXX-XXXXX-AB234' ]] || fail 'explicit key export'
[[ $(stat -c %a "$keyfile") == 600 ]] || fail 'key export permissions'

echo 'ok - all probe-identify tests passed'
