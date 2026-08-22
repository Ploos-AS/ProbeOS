# ProbeOS

ProbeOS is a lightweight, bootable Linux environment for hardware inspection,
diagnostics, and performance benchmarking.

It is designed to boot quickly from USB or CD and provide clear, trustworthy
insight into system hardware without requiring installation or modifying disks.

Project homepage: https://probeos.eu

---

## Goals

- Hardware-first user experience
- Fast boot, minimal footprint
- Fully redistributable and open
- GUI and text-based (TUI) operation
- Suitable for diagnostics, verification, and benchmarking

---

## ProbeOS v0.1.0

v0.1.0 is the first qualified public ProbeOS release. It provides Hardware
Identification v1, authoritative text and JSON reports, local TUI/GUI access,
an optional trusted-LAN Web UI and read-only `/api/v1` API, offline operation,
and open-source Memtest86+ 8.10. It is an initial qualified release, not a
claim of universal physical-hardware compatibility or certification.

## Hardware reports

`probe-identify` is the central read-only hardware inventory. It generates a
privacy-safe sale report by default, detailed/full profiles, standalone HTML,
and stable-schema JSON under `/run/probeos`. Development after v0.1.0 adds
conservative offline Windows key recovery with explicit local reveal/export;
normal reports, Web UI, and API never contain complete product keys. The optional
retro-friendly local Web UI/API presents that same report without probing again.

ProbeOS v0.2 development adds one central, offline diagnostics engine with a
safe Quick Check, explicit bounded CPU/userspace-memory/storage-read tests, and
read-only result presentation. See [Diagnostics Framework v1](docs/diagnostics.md).

The development branch also includes the separate Benchmark Framework v1 and
opt-in Stability/Burn-in workflow. They record native measurements and bounded
stability evidence without performance scoring or destructive storage writes.
See [benchmarks](docs/benchmarks.md) and [stability testing](docs/stability-testing.md).
See
[`docs/hardware-identification.md`](docs/hardware-identification.md) for data
sources and limitations, [docs/reporting.md](docs/reporting.md) for report
profiles, and [docs/windows-license-discovery.md](docs/windows-license-discovery.md)
for Windows licensing semantics and privacy.
See [docs/web-api.md](docs/web-api.md) and [docs/networking.md](docs/networking.md)
for Web/API and LAN operation.

ProbeOS v0.2 development provides an offline physical-hardware qualification
framework and privacy-safe evidence bundles. Compatibility claims are generated
from reviewed evidence, with physical, emulator, and synthetic results kept
strictly separate. **Real physical machines qualified: 0.** The framework is
available, but no physical-machine compatibility claim is made until reviewed
real evidence is collected. See the generated [compatibility evidence matrix](docs/compatibility.md),
the [technician procedure](docs/physical-qualification.md), and the
[evidence/trust architecture](docs/compatibility-evidence.md).

## Choose an image

| Image | Choose it for | Emulator-qualified firmware |
| --- | --- | --- |
| `probeos-0.1.0-x86_64-grub.iso` | Preferred general x86_64 image | BIOS (SeaBIOS), x86_64 UEFI (OVMF) |
| `probeos-0.1.0-x86_64-syslinux.iso` | x86_64 Linux on the legacy BIOS path | BIOS (SeaBIOS) |
| `probeos-0.1.0-x86-grub.iso` | 32-bit x86 ProbeOS | BIOS (SeaBIOS) |
| `probeos-0.1.0-x86-syslinux.iso` | 32-bit x86 on the SYSLINUX legacy BIOS path | BIOS (SeaBIOS) |

These are QEMU qualifications, not physical-hardware qualifications and not
proof that every physical PC will boot.
There is no IA32 UEFI or Secure Boot claim. See
[the compatibility matrix](docs/release-readiness.md#qualification-matrix)
and [known limitations](docs/release-readiness.md#known-limitations).

Write the selected ISO to USB using an image-writing tool, or attach it as
virtual optical media. Normal ProbeOS is the default; Memtest86+ is an explicit
menu choice. Text mode opens the TUI; GUI mode starts the local desktop.

## Build and boot

The supported live-ISO build runs in Docker and pins Alpine 3.19. GRUB is the
modern BIOS/UEFI path; SYSLINUX is retained as a BIOS-only compatibility path
for legacy systems:

```sh
build/alpine/build-container.sh
BOOTLOADER=syslinux build/alpine/build-container.sh
ARCH=x86 build/alpine/build-container.sh
ARCH=x86 BOOTLOADER=syslinux build/alpine/build-container.sh
tests/iso-layout.sh out/probeos-x86_64-grub.iso
tests/iso-layout.sh out/probeos-x86_64-syslinux.iso
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso bios
tests/qemu-smoke.sh out/probeos-x86_64-grub.iso uefi
# Optional legacy x86 qualification:
ARCH=x86 build/alpine/build-container.sh
QEMU=qemu-system-i386 tests/qemu-smoke.sh out/probeos-x86-grub.iso bios
```

Development builds produce `probeos-x86_64-grub.iso`,
`probeos-x86_64-syslinux.iso`, `probeos-x86-grub.iso`, and
`probeos-x86-syslinux.iso` under `out/`. SYSLINUX configuration is maintained
at [`boot/syslinux/isolinux.cfg`](boot/syslinux/isolinux.cfg).

The BIOS smoke test needs `qemu-system-x86_64`. The UEFI test additionally
needs OVMF at `/usr/share/OVMF`, or `OVMF_CODE` and `OVMF_VARS` set to suitable
firmware files. Both tests disable guest networking and write their serial logs
under `${TMPDIR:-/tmp}` unless a log path is passed as the third argument.

The resulting root login password is `probeos`. See
[`docs/build-audit.md`](docs/build-audit.md) for the live-media architecture,
qualification evidence, and current limitations.

ProbeOS also includes the offline, open-source Memtest86+ v8.10 boot option;
see [`docs/memtest.md`](docs/memtest.md) for provenance, licensing, and
qualification details. It is distinct from the proprietary PassMark MemTest86.

ProbeOS first attempts wired DHCP but remains usable with no network. The Web
UI starts on `http://127.0.0.1:8080/`; LAN binding is an explicit runtime choice
for trusted networks only. See [networking](docs/networking.md).

Release downloads include `SHA256SUMS`. From the download directory run:

```sh
sha256sum -c SHA256SUMS
```

## Continuous integration and releases

GitHub Actions validates source and fixtures, builds all four ISO variants with
the same containerized builder used locally, checks their layouts, and runs the
qualified Linux, offline, LAN/Web/API, and Memtest86+ QEMU smoke tests. Successful
CI runs provide a 14-day `probeos-isos-<commit SHA>` development artifact with
the ISOs, `SHA256SUMS`, and `release-manifest.json`.

Strict SemVer tags such as `v0.1.0` run the same pipeline and create versioned
public filenames. Development artifacts retain stable names and identify
themselves as development builds; only an exact tag is an official release.
Tags create a GitHub Release only after qualification succeeds. See [docs/releasing.md](docs/releasing.md)
for the artifact matrix, hosted-runner limitations, checksum verification,
local reproduction, and release procedure.

---

## License and provenance

ProbeOS-authored source is licensed under GPL-3.0-or-later. Redistributed
Alpine packages, bootloaders, Linux, Memtest86+, and other third-party
components retain their own licenses; ProbeOS does not relicense them.
Public releases include exact package inventories, source manifests, and a
corresponding-source archive. See [release compliance](docs/release-compliance.md)
and [third-party provenance](third_party/README.md).

Copyright © 2026 Ploos AS

---

## Links

- Project site: https://probeos.eu
- Source code: https://github.com/ploos-as/probeos
