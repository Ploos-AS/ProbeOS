# Release source compliance

ProbeOS-authored copyrightable material is distributed under
GPL-3.0-or-later. The repository `LICENSE` contains the canonical GPLv3 text.
This does not change or replace the licenses of Alpine packages, Linux, GRUB,
SYSLINUX, Memtest86+, or any other redistributed third-party component.

## Release records

Each public release is accompanied by:

- `release-manifest.json`: the qualified binary ISO identities;
- `THIRD-PARTY-MANIFEST.json`: every exact resolved x86/x86_64 APK plus the
  GRUB and SYSLINUX builder APKs, including version, architecture, license,
  upstream URL, APK SHA-256, source origin, and Alpine aports commit;
- `SOURCE-MANIFEST.json`: the matching ProbeOS source revision, every unique
  Alpine source recipe and verified distfile, and exact Memtest86+ source;
- `probeos-<version>-source.tar.zst`: the complete source/compliance tree; and
- `SHA256SUMS`: all four ISOs and the three public compliance artifacts.

The source archive contains the exact ProbeOS Git archive, Alpine 3.19 aports
recipe trees at each APK's recorded build commit, recipe source inputs verified
by `abuild fetch verify`, the exact Memtest86+ v8.10 Git source archive and
official binary archive (GPL-2.0-only), machine-readable manifests, and the
ProbeOS license.
Its `metadata/LICENSE-INDEX.json` maps every preserved Alpine license
expression to the affected components; authoritative upstream license and
notice files remain in the corresponding recipe/source trees.
Recipes and distfiles are retained locally in the bundle so current upstream
branches or future website changes are not substituted for release source.

Inspect the source mapping with, for example:

```sh
jq '.alpine_sources[] | {component,aports_commit,source_path}' SOURCE-MANIFEST.json
jq '.packages[] | {name,version,architecture,license,source_package,aports_commit}' THIRD-PARTY-MANIFEST.json
sha256sum -c SHA256SUMS
```

## Gates and workflow

Fast PR/main CI checks licensing assertions and generator syntax without
downloading the complete source set. A tag release builds and qualifies the
four normal ISOs, generates binary metadata, fetches and verifies complete
source, creates the source archive, and runs `ci/validate-compliance.sh
release`. Any missing package metadata, aports recipe, source input, checksum,
manifest relationship, archive, or checksum entry stops publication.

The build/qualification job has read-only repository permission. Its completed
binary and source artifacts are transferred unchanged to the separate
publication job; only that final job has `contents: write`.

## Limits

The mechanism conservatively supplies source for every redistributed APK, not
only packages identified by automated license-expression parsing. It preserves
upstream license expressions and source trees rather than attempting to
reinterpret them. It is a technical compliance and provenance mechanism, not
a guarantee of legal compliance; unusual upstream notices or license terms
still merit human review.
