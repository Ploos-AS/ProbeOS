<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Windows License Discovery v2

ProbeOS performs read-only, offline discovery for the machine owner. It never
activates Windows, installs a key, writes a registry hive, changes EFI state,
or mounts a candidate Windows filesystem read-write.

## Sources and meanings

- `firmware_msdm` is a key found in the ACPI MSDM table. ProbeOS identifies it
  as `OEM_DM` with high source confidence. It may help reinstall the matching
  Windows edition.
- `offline_registry` is decoded from `DigitalProductId` in a discovered
  installation's SOFTWARE hive when the stored value is structurally valid.
  ProbeOS keeps edition/build/Product ID metadata associated with that
  installation.
- Product ID is licensing metadata, not a Product Key. The UI and schema keep
  the fields separate and regression tests enforce this invariant.

Every recovered-key record has a source, semantic type, confidence,
reuse hint, and edition/installation context where known. Known Microsoft
generic/default installation keys are classified as `generic` with high
confidence and `not_established` reuse status. They are not described as a
unique or valuable recovered license. Unknown non-generic registry values are
reported conservatively; their source can be known while their retail/OEM/
volume semantics remain unknown.

The generic-volume list follows Microsoft's published KMS client key table:
<https://learn.microsoft.com/windows-server/get-started/kms-client-activation-keys>.

## Digital licenses and limitations

A digital license may be tied to hardware or a Microsoft account without a
standalone unique key recoverable from disk. ProbeOS cannot reliably establish
offline activation state or predict Microsoft's future activation decision.
Finding a key is therefore not a guarantee that Microsoft will accept it, and
finding only a generic key does not imply that Windows was unlicensed.

Encrypted, damaged, unsupported, or incomplete filesystems/hives may yield
metadata only or no result. ProbeOS does not unlock BitLocker volumes. Multiple
Windows installations are evaluated independently rather than assuming the
first NTFS filesystem is Windows.

## Sensitive display and export

Complete keys never enter normal TXT/JSON/HTML reports, logs, filenames, the
Web UI, or ordinary API responses. The local TUI and GUI provide explicit
**Show Windows Product Key** and **Export Windows License Information** actions.
The reveal includes source, type, confidence, edition context, and a reuse
warning. Sensitive exports are separate from sale-report export and use mode
0600. Command-line equivalents remain `probe-identify --reveal-key` and
`probe-identify --export-key FILE`.
