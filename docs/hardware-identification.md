# Hardware Identification v1

`probe-identify` is the authoritative ProbeOS hardware inventory. The TUI and
GUI are presentation layers over its reports; they do not run their own
hardware-discovery command sets.

## Operation and safety

Running `probe-identify` writes `/run/probeos/report.txt` and
`/run/probeos/report.json`. Individual command failures and absent hardware are
represented by empty arrays, `null`, `unknown`, or an explicit status and do
not abort other probe sections. External commands have a 20-second default
limit. Override it with `PROBE_COMMAND_TIMEOUT` when diagnosing unusually slow
firmware.

The collector uses read-only sources and commands: `lscpu`, `/proc`, `/sys`,
`dmidecode`, `lspci -Dnnk`, `lsusb`, `lsblk`, `ip`, `ethtool`, `sensors`,
`smartctl` information/health queries, `nvme list`, `acpidump`, and `mokutil`.
It does not start SMART tests, stress tests, filesystem repair, firmware
operations, or storage benchmarks.

Candidate Windows filesystems are mounted only when needed and only with
`ro,nosuid,nodev,noexec`. Mounts are temporary and unmounted on exit. Use
`--no-windows-mount` to disable this discovery. ProbeOS never uses filesystem
repair or writes a Windows hive.

## Report schema 1.0

The JSON document has stable top-level keys:

```text
schema_version
probeos
system
firmware
motherboard
cpu[]
memory
pci[]
usb[]
graphics[]
storage[]
network[]
sensors
power
windows.firmware_license
windows.installations[]
```

`probeos` records tool/version, UTC generation time, host name, kernel, and
architecture. System and motherboard objects contain DMI identity. CPU entries
contain exact model, topology, family/model/stepping, frequency/cache fields,
flags, virtualization, and microcode when available. Memory records usable RAM,
slot counts, and populated DIMMs. Device arrays retain numeric IDs and drivers
where their data sources expose them. Missing scalar values are JSON `null`;
missing collections are empty arrays.

Schema additions may occur in compatible v1 releases. Existing keys will not
change meaning without a schema-version change.

## Windows licensing

The firmware OEM key source is the ACPI `MSDM` table—not the CPU. Normal reports
contain only the final five characters:

```text
*****-*****-*****-*****-AB123
```

`probe-identify --reveal-key` prints the complete key to the current terminal.
`probe-identify --export-key FILE` writes it with mode 0600. Neither option
places the complete key in the normal reports.

Offline Windows inspection reads the `SOFTWARE` registry hive with
`hivexregedit` when available. Product name, display version, build, Product ID,
and edition/channel hints are registry metadata. A Product ID is not a product
key. ProbeOS does not claim a generic registry value is the activation key and
reports activation status and firmware-key relationship as indeterminate when
they cannot be established reliably offline.

## Privacy

Reports can contain machine, board, storage, DIMM and battery serial numbers;
system UUIDs; and network MAC addresses. Treat reports as sensitive before
sharing them. Full OEM keys exported explicitly are credentials and require
stronger handling.

## Known limitations

- DMI and ACPI quality depends on firmware and privileges.
- Secure Boot detection may be unknown without UEFI variables or `mokutil`.
- SMART/NVMe access can be blocked by USB bridges or device permissions.
- Display EDID, sensor labels, link capabilities, and Windows architecture are
  hardware/tool dependent and may remain unknown.
- Offline registry metadata cannot prove activation status.
- BitLocker and unsupported filesystems are not unlocked or modified.

## Tests

`tests/run-tests.sh` uses command-output fixtures. It covers CPU, DMI, PCI,
storage, missing commands/hardware, malformed output, MSDM presence/absence,
key masking/export, absent Windows volumes, report generation, and JSON
validation without requiring particular physical hardware.
