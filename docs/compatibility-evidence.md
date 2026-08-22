<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Compatibility evidence architecture

ProbeOS compatibility claims derive from explicit reviewed evidence, never
architecture labels, theoretical Linux support, similar models, synthetic
fixtures, or QEMU success. Evidence environments are `physical`, `emulator`,
and `synthetic`. Only approved records under `compatibility/physical` count as
physical machines or physical runs. QEMU records remain separate regression
evidence under `compatibility/emulator`.

## Record and procedure

Qualification records use schema `1.0` in
`compatibility/schema/qualification-1.0.json`. Standard physical collection
uses procedure `physical-qualification-v1`. A change to the meaning or required
checks requires a new procedure version; older evidence remains tied to its
original ProbeOS version, commit, artifact, procedure, and boot path.

Statuses are bounded:

- `PASS`: the defined test ran and its compatibility condition succeeded.
- `PARTIAL`: ProbeOS operates, but a relevant area failed or was unavailable.
- `FAIL`: an expected, performed feature demonstrably failed.
- `NOT_TESTED`: the test was not performed; unavailability is never PASS.
- `UNSUPPORTED`: ProbeOS explicitly does not support the feature/path.
- `ERROR`: the qualification procedure itself malfunctioned.

Bootloader, kernel, initramfs, userspace, services, inventory, and Quick Check
execution are independent core stages. An `ERROR` in a core stage aggregates
to ERROR and a core `FAIL` to FAIL. All core stages passing produces PASS unless
a tested relevant integration has FAIL/ERROR/PARTIAL, which produces PARTIAL.
Some core progress with incomplete core checks produces PARTIAL; no performed
core checks produces NOT_TESTED. Optional NOT_TESTED/UNSUPPORTED areas do not
prevent useful PASS evidence. Diagnostic health is explicitly excluded from
compatibility aggregation: a battery or disk WARN describes the machine's
health, not ProbeOS compatibility.

Every result names its evidence source: `probeos_runtime`, `operator_observed`,
`qemu_ci`, `imported_physical_bundle`, `synthetic_fixture`, or
`manual_early_boot`. Manual notes cannot replace structured statuses.

## Privacy-preserving machine identity

Fingerprint version 1 normalizes available DMI system manufacturer/model,
system serial/UUID, board manufacturer/model/serial, and CPU model; joins the
values unambiguously; prepends the domain separator `ProbeOS physical machine
fingerprint v1`; and computes SHA-256. Only the digest is exported. A separate
random UUIDv4 identifies each qualification run.

The fingerprint permits repeated-test detection but is not guaranteed stable
across firmware/board changes, can collide when old firmware exposes little
identity, and is neither globally anonymous nor cryptographically untrackable.
Raw inputs remain local and are never published in a share-safe bundle.

## Bundle and trust model

The common, offline bundle is
`probeos-qualification-<qualification-id>.tar.gz`. It contains redacted
qualification JSON/TXT/HTML, a redacted authoritative `hardware-report.json`,
privacy-safe presentation and test results when present,
`qualification-manifest.json`, and `SHA256SUMS`. Both manifests link exact
included files with SHA-256 and sizes. Inputs are bounded; raw system logs,
Windows keys, serials, UUIDs, MAC/IP addresses, credentials, and raw fingerprint
inputs are excluded. Relevant logs may be added in future only as bounded,
sanitized text with truncation recorded.

Trust classes are: automated QEMU CI; locally collected physical runtime
evidence; explicitly operator-observed evidence; and external imported
evidence. A valid checksum proves bundle integrity, not truth. The importer
treats archives as hostile and produces a pending review candidate; a
maintainer must verify provenance and explicitly approve a record before it is
copied into the reviewed database. It never commits, pushes, executes archive
content, or uploads anything.

`tools/import-qualification BUNDLE --candidate-dir DIR` rejects traversal,
links/non-regular members, unexpected content, decompression size surprises,
malformed JSON, checksum/manifest mismatches, privacy leaks, duplicate test IDs,
and non-physical records. Repeated fingerprints are reported for review rather
than rejected because multiple boot paths and ProbeOS versions are valuable.

`tools/generate-compatibility` deterministically creates
`docs/compatibility.md`. CI uses `--check`. Unique fingerprints determine the
physical-machine count; qualification IDs determine the run count. Emulator
and synthetic records are never included in either physical count. Failures,
partial results, boot-path differences, component observations, and ProbeOS
versions remain visible rather than being collapsed into “machine supported.”
