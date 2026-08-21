#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[[ $(sha256sum "$ROOT/LICENSE" | awk '{print $1}') == \
    3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986 ]]
while IFS= read -r file; do
    grep -Fqm1 'SPDX-License-Identifier: GPL-3.0-or-later' "$ROOT/$file" || {
        echo "missing ProbeOS SPDX header: $file" >&2
        exit 1
    }
done < <(git -C "$ROOT" ls-files \
    'assets/scripts/*' 'assets/openbox/autostart' 'build/**/*.sh' \
    'build/alpine/conf.d/*' 'build/alpine/init.d/*' 'ci/*.sh' 'compliance/*.py' \
    'src/lib/*' 'src/scripts/*' 'src/web/*.py' 'tests/*.sh')
grep -Fq 'Memtest86+ is GPLv2' "$ROOT/third_party/README.md"
grep -Fq 'GPL-2.0-only' "$ROOT/docs/release-compliance.md"
stale_pattern='ProbeOS-authored.*M''IT|ProbeOS .*licensed under the M''IT'
if git -C "$ROOT" grep -nE "$stale_pattern" -- .; then
    echo 'stale ProbeOS MIT claim found' >&2
    exit 1
fi
echo 'ok - ProbeOS and third-party license regression checks passed'
