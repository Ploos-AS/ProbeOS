#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

shell_files=(
    build/alpine/*.sh
    build/alpine/init.d/*
    ci/*.sh
    tests/*.sh
    src/scripts/*
    src/lib/*.sh
)
bash -n "${shell_files[@]}"
shellcheck "${shell_files[@]}"
git diff --check HEAD
git show --check --format= HEAD
tests/run-tests.sh
tests/diagnostics.sh
tests/web-api.sh
tests/network.sh
tests/package-resolution.sh
tests/release-metadata.sh
tests/license.sh
ci/validate-compliance.sh fast
