#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-diagnostics.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tests/diagnostics.py"
mkdir -p "$WORK/report"
"$ROOT/src/scripts/probe-identify" --fixture-dir "$ROOT/tests/fixtures/full" --output-dir "$WORK/report" --no-windows-mount >/dev/null
"$ROOT/src/scripts/probe-diagnostics" quick --fixture-dir "$ROOT/tests/fixtures/full" --report "$WORK/report/report.json" --output-dir "$WORK/report" >/dev/null
jq -e '.schema_version=="1.0" and .run.mode=="quick" and (.results|length)>=12 and
  ([.results[].status] | all(.=="PASS" or .=="WARN" or .=="FAIL" or .=="UNKNOWN" or .=="SKIPPED" or .=="ERROR")) and
  ([.results[] | select(.destructive==true)] | length)==0' "$WORK/report/diagnostics.json" >/dev/null
for file in diagnostics.txt diagnostics.json diagnostics.html; do test -s "$WORK/report/$file"; done
grep -Fq 'Hardware Check' "$WORK/report/sale.txt"
jq -e '.hardware_check.status != "Not run"' "$WORK/report/sale.json" >/dev/null
jq -e '.diagnostics.schema_version=="1.0"' "$WORK/report/detailed.json" >/dev/null
if grep -Eiq '[A-Z0-9]{5}(-[A-Z0-9]{5}){4}|SSD123|NVME-SECRET|52:54:00:' "$WORK/report/diagnostics."*; then
    echo 'diagnostics output leaked sensitive fixture data' >&2; exit 1
fi
# Cancellation must terminate the complete workload group and persist SKIPPED.
mkdir -p "$WORK/fake-bin" "$WORK/cancelled"
printf '%s\n' '#!/bin/sh' 'trap "exit 0" TERM INT' 'while :; do sleep 1; done' > "$WORK/fake-bin/stress-ng"
chmod +x "$WORK/fake-bin/stress-ng"
PATH="$WORK/fake-bin:$PATH" "$ROOT/src/scripts/probe-diagnostics" cpu --duration 60 --output-dir "$WORK/cancelled" >/dev/null 2>&1 &
diagnostic_pid=$!
sleep 1
kill -INT "$diagnostic_pid"
wait "$diagnostic_pid"
jq -e '.results[0].status=="SKIPPED" and (.results[0].summary|contains("cancelled"))' "$WORK/cancelled/diagnostics.json" >/dev/null
echo 'ok - diagnostics engine, fixtures, result JSON, profiles, and privacy passed'
