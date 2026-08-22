#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-web-test.XXXXXX")
PORT=${PROBEOS_WEB_TEST_PORT:-18080}
SERVER_PID=""
trap 'if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT

PROBE_FIXTURE_DIR="$ROOT/tests/fixtures/full" \
  "$ROOT/src/scripts/probe-identify" --output-dir "$WORK/report" --no-windows-mount >/dev/null
PROBEOS_REPORT_DIR="$WORK/report" PROBEOS_WEB_QUIET=1 \
  PROBEOS_RELEASE_FILE="$WORK/probeos-release" \
  python3 "$ROOT/src/web/probeos_web.py" --bind 127.0.0.1 --port "$PORT" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do
    curl -fsS "http://127.0.0.1:$PORT/api/v1/health" >/dev/null 2>&1 && break
    sleep 0.1
done

health=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/health")
jq -e '.service=="running" and .api_version=="1" and .product_version=="development" and .build_channel=="development" and .report_available==true and (.report_generated_at|type)=="string"' <<<"$health" >/dev/null
report=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/report")
jq empty <<<"$report"
jq -e '.schema_version=="1.1" and .default_human_profile=="sale" and (.cpu|type)=="array" and (.windows|type)=="object"' <<<"$report" >/dev/null
for section in system cpu memory firmware motherboard pci usb graphics storage network sensors power windows; do
    curl -fsS "http://127.0.0.1:$PORT/api/v1/$section" | jq empty >/dev/null
done
html=$(curl -fsS "http://127.0.0.1:$PORT/")
grep -Fq 'ProbeOS' <<<"$html"
if grep -Eiq '<script|javascript:' <<<"$html"; then exit 1; fi
grep -Fq '/api/v1/report' <<<"$html"
grep -Fq 'Fixture Workstation' <<<"$html"
profiles=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/profiles")
jq -e '.default=="sale" and .available==["sale","detailed","full"]' <<<"$profiles" >/dev/null
sale=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/report/sale")
jq -e '.profile=="sale" and .system.model=="Fixture Workstation"' <<<"$sale" >/dev/null
sale_html=$(curl -fsS "http://127.0.0.1:$PORT/sale-report")
grep -Fq 'privacy-safe specification sheet' <<<"$sale_html"

grep -Fq '"serial_number": "[redacted]"' <<<"$report"
grep -Fq '"mac_address": "[redacted]"' <<<"$report"
if grep -Fq 'XXXXX-XXXXX-XXXXX-XXXXX-AB234' <<<"$report"; then exit 1; fi
for payload in "$report" "$html" "$sale" "$sale_html"; do
    if grep -Eq 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE|W269N-WFGWX-YVC9B-4J6C9-T83GX' <<<"$payload"; then exit 1; fi
done

full=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/report?privacy=full")
grep -Fq '"serial_number": "SYS123"' <<<"$full"
grep -Fq '"mac_address": "02:00:00:00:00:01"' <<<"$full"
if grep -Fq 'XXXXX-XXXXX-XXXXX-XXXXX-AB234' <<<"$full"; then exit 1; fi

printf '{malformed\n' >"$WORK/report/report.json"
missing=$(curl -sS -w '\n%{http_code}' "http://127.0.0.1:$PORT/api/v1/report")
grep -Fq '"error": "report_unavailable"' <<<"$missing"
grep -Fq '503' <<<"$missing"
health_missing=$(curl -fsS "http://127.0.0.1:$PORT/api/v1/health")
jq -e '.report_available==false' <<<"$health_missing" >/dev/null
echo 'ok - retro web UI/API, privacy redaction, and malformed-report handling passed'
