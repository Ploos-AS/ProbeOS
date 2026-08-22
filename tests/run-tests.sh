#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
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
WINDOWS_HELPER="$ROOT/src/lib/windows-license.py"

fail() { echo "not ok - $*" >&2; exit 1; }
assert_jq() { jq -e "$2" "$1" >/dev/null || fail "$3"; }

generic=$("$WINDOWS_HELPER" --key W269N-WFGWX-YVC9B-4J6C9-T83GX)
jq -e '.key_type=="generic" and .confidence=="high" and .reusable_hint=="not_established"' <<<"$generic" >/dev/null || fail 'known generic key classification'
[[ $("$WINDOWS_HELPER" --key invalid) == null ]] || fail 'malformed product key rejection'

cpu=$(parse_cpu "$FIXTURES/full/lscpu")
jq -e '.[0].vendor=="GenuineIntel" and .[0].cores==8 and .[0].threads=="16" and .[0].virtualization=="VT-x"' <<<"$cpu" >/dev/null || fail 'CPU parsing'
[[ $(dmi_value "$FIXTURES/full/dmidecode" 'System Information' 'Product Name') == 'Fixture Workstation' ]] || fail 'DMI parsing'
pci=$(parse_pci "$FIXTURES/full/lspci")
jq -e 'length==4 and .[0].vendor_id=="8086" and .[0].driver=="i915"' <<<"$pci" >/dev/null || fail 'PCI parsing/multiple devices'
storage=$(parse_storage "$FIXTURES/full/lsblk")
jq -e 'length==2 and .[0].device=="/dev/sda" and .[0].capacity_bytes==1000204886016 and .[1].transport=="nvme"' <<<"$storage" >/dev/null || fail 'storage parsing/multiple disks'
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
assert_jq "$WORK/full/report.json" '.schema_version=="1.1" and .default_human_profile=="sale" and .report_profiles==["sale","detailed","full"] and (.cpu|length)==1 and (.pci|length)==4 and (.graphics|length)==2 and (.storage|length)==2 and (.windows.installations|length)==3' 'report generation and profiles'
assert_jq "$WORK/full/report.json" '.windows.installations[0].product_id=="12345-67890-12345-AAOEM" and .windows.installations[0].recoverable_key_status=="found" and (.windows.installations[0]|has("recoverable_product_key")|not)' 'Product ID/key separation'
jq empty "$WORK/full/report.json" || fail 'valid JSON'
[[ -s "$WORK/full/report.txt" ]] || fail 'text report generation'
for file in sale.txt sale.json sale.html detailed.txt detailed.json full.txt full.json; do [[ -s "$WORK/full/$file" ]] || fail "$file generation"; done
cmp "$WORK/full/report.txt" "$WORK/full/sale.txt" >/dev/null || fail 'sale report is default text report'
assert_jq "$WORK/full/sale.json" '.profile=="sale" and .system.model=="Fixture Workstation" and (.processor.model|contains("i7-10700")) and .memory.total=="34.4 GB" and (.graphics|length)==2 and (.storage|length)==2 and .storage[0].health=="PASS" and .storage[1].health=="PASS" and (.network|length)==2 and (.firmware.boot_mode=="BIOS" or .firmware.boot_mode=="UEFI") and (.windows.installations|length)==3 and .windows.installations[2].recoverable_key=="not_established" and .windows.firmware_oem_license=="Found" and .batteries[0].health_percent==85' 'sale report quality'
grep -Fq 'ProbeOS System Report' "$WORK/full/sale.txt" || fail 'sale title'
grep -Fq 'Fixture Workstation' "$WORK/full/sale.txt" || fail 'sale system usefulness'
grep -Fq '<!doctype html>' "$WORK/full/sale.html" || fail 'standalone sale HTML'
if grep -Eiq '<script|javascript:' "$WORK/full/sale.html"; then fail 'sale HTML requires script'; fi

"$PROBE" --fixture-dir "$FIXTURES/malformed" --output-dir "$WORK/malformed" --no-windows-mount >/dev/null
jq empty "$WORK/malformed/report.json" || fail 'malformed inputs still produce valid JSON'
assert_jq "$WORK/malformed/report.json" '(.windows.installations|length)==0' 'malformed Windows registry fixture handling'

keyfile="$WORK/key"
"$PROBE" --fixture-dir "$FIXTURES/full" --output-dir "$WORK/full" --no-windows-mount --export-key "$keyfile" >/dev/null
grep -Fq 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' "$keyfile" || fail 'explicit offline key export'
grep -Fq 'W269N-WFGWX-YVC9B-4J6C9-T83GX' "$keyfile" || fail 'explicit generic key export'
grep -Fq 'Type: generic' "$keyfile" || fail 'generic key classification'
[[ $(stat -c %a "$keyfile") == 600 ]] || fail 'key export permissions'

reveal=$("$PROBE" --fixture-dir "$FIXTURES/full" --output-dir "$WORK/full" --no-windows-mount --reveal-key)
grep -Fq 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' <<<"$reveal" || fail 'explicit key reveal'
grep -Fq 'activation acceptance cannot be guaranteed' <<<"$reveal" || fail 'key reuse warning'
for output in "$WORK/full/report.txt" "$WORK/full/report.json" "$WORK/full/sale.txt" "$WORK/full/sale.json" "$WORK/full/sale.html" "$WORK/full/detailed.txt" "$WORK/full/detailed.json" "$WORK/full/full.txt" "$WORK/full/full.json"; do
    ! grep -Fq 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE' "$output" || fail "offline key leaked into $(basename "$output")"
    ! grep -Fq 'W269N-WFGWX-YVC9B-4J6C9-T83GX' "$output" || fail "generic key leaked into $(basename "$output")"
done

echo 'ok - all probe-identify tests passed'
