#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
python3 "$ROOT/tests/qualification.py"
"$ROOT/tools/generate-compatibility" --check
jq -e '.schema_version=="1.0" and .environment_type=="emulator" and .provenance=="qemu_ci"' "$ROOT/compatibility/emulator/qemu-current.json" >/dev/null
jq -e '.fixture_type=="synthetic" and (.cases|length)>=8' "$ROOT/compatibility/fixtures/qualification-cases.json" >/dev/null
echo 'ok - qualification schema, aggregation, bundle, importer security, privacy, and evidence separation passed'
