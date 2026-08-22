#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/probeos-benchmarks.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
python3 "$ROOT/tests/benchmarks.py"
if rg -n 'probe-benchmark (run|stability)|sysbench .* run|stress-ng' "$ROOT/build/alpine/init.d" "$ROOT/src/web" >/dev/null; then exit 1; fi
if rg -n -- '--rw=(write|randwrite)|badblocks.*-w|of=/dev/(sd|nvme|vd)' "$ROOT/src" >/dev/null; then exit 1; fi
PROBE_FIXTURE_DIR="$ROOT/tests/fixtures/full" "$ROOT/src/scripts/probe-identify" --output-dir "$WORK" --no-windows-mount >/dev/null
cp "$ROOT/tests/fixtures/benchmarks.json" "$WORK/benchmarks.json"
cp "$ROOT/tests/fixtures/stability.json" "$WORK/stability.json"
python3 "$ROOT/src/lib/report-render.py" "$WORK/report.json" "$WORK"
jq -e '.performance_tests[0].status=="COMPLETED"' "$WORK/sale.json" >/dev/null
jq -e '.benchmarks.schema_version=="1.0" and .stability.schema_version=="1.0"' "$WORK/full.json" >/dev/null
if grep -Eiq 'SECRET|[A-Z0-9]{5}(-[A-Z0-9]{5}){4}|52:54:00:' "$WORK/benchmarks."* "$WORK/stability."*; then exit 1; fi
echo 'ok - benchmark engine, safety, fixtures, cancellation, and privacy passed'
