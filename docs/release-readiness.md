# ProbeOS v0.1.0 release definition

ProbeOS v0.1.0 is the first qualified public release of the lightweight,
bootable Linux environment for hardware inspection, diagnostics, and
performance benchmarking. Its scope is the functionality described in the
README; it is not certified, exhaustive, production-guaranteed, or universally
compatible.

## Build identity and artifact policy

`ci/version.sh` is the identity source. An exact strict SemVer Git tag produces
an official release identity (`ProbeOS 0.1.0`, channel `release`). Any untagged
commit is `ProbeOS development`, with its commit recorded. A deliberate dry
run may set `PROBEOS_RC_VERSION=0.1.0-rc.1`; its channel remains
`release-candidate` and cannot masquerade as the release.

The same identity is written to `/etc/probeos-release` as newline-separated
`KEY=value` fields: `PROBEOS_VERSION`, `PROBEOS_BUILD_CHANNEL`,
`PROBEOS_GIT_COMMIT`, `PROBEOS_GIT_SHORT_SHA`, and `PROBEOS_ARCHITECTURE`.
It is also presented by reports, Web About, and API health. Alpine's
`/etc/alpine-release` is unchanged.

Development/qualification ISOs retain stable names. Tagged and RC bundles copy
the exact qualified bytes to `probeos-<version>-<architecture>-<bootloader>.iso`.
The manifest and `SHA256SUMS` name those public files exactly.

## Emulator qualification matrix

| Architecture | Bootloader | Firmware | Linux | Memtest86+ startup | Physical hardware |
| --- | --- | --- | --- | --- | --- |
| x86_64 | GRUB | BIOS / SeaBIOS | PASS | PASS | Not systematically qualified |
| x86_64 | GRUB | UEFI / OVMF | PASS | PASS | Not systematically qualified |
| x86_64 | SYSLINUX | BIOS / SeaBIOS | PASS | PASS | Not systematically qualified |
| x86 | GRUB | BIOS / SeaBIOS | PASS | PASS | Not systematically qualified |
| x86 | SYSLINUX | BIOS / SeaBIOS | PASS | PASS | Not systematically qualified |

These tests use QEMU TCG in hosted CI. They prove the listed emulator boot paths and
startup checks, not coverage of every physical machine. Supported by design:
x86/x86_64 Linux, GRUB BIOS, x86_64 GRUB UEFI, and SYSLINUX BIOS variants.
Qualified in QEMU: only the rows above. Physical hardware: no systematic
release qualification record exists yet.

Physical evidence is now tracked separately and generated deterministically in
[the compatibility evidence matrix](compatibility.md). At the v0.2 framework
implementation baseline it contains zero reviewed real physical machines;
QEMU and synthetic fixtures cannot increment that count.

The Alpine 3.19 `x86` repository is used for the 32-bit ISO and Memtest uses an
i586 payload, but the repository does not establish a defensible minimum CPU
generation for the entire kernel/package set. v0.1.0 therefore makes no
80386/80486/Pentium-generation promise. Likewise, `x86_64` is an architecture
label rather than a promise covering every historical x86-64 CPU.

## Known limitations

- ARM is not supported. Secure Boot and IA32 UEFI are not qualified or claimed.
- Physical-hardware coverage is not exhaustive; the canonical matrix is QEMU.
- Networking is wired IPv4. Wi-Fi setup is not provided. Static configuration
  is runtime-only and is lost at shutdown.
- ProbeOS has no installer or persistence facility.
- Benchmarks are a limited interactive tool set, not a certification suite.
- Offline Windows data cannot prove activation status. OEM product keys are
  masked by default; explicit full-key export is local and opt-in.
- Some firmware, SMART/NVMe, sensors, EDID, and Windows metadata may be absent
  or inaccessible; see `hardware-identification.md`.
- The Web UI/API is read-only and intended for local/trusted-LAN use. It has no
  TLS, authentication, remote shell, or remote benchmark execution and must
  not be exposed to the Internet. Its conservative HTML targets older browsers,
  but no exhaustive browser matrix is qualified.
- The build is repeatable and traceable on a clean runner. Bit-for-bit
  reproducibility has not been independently demonstrated.

## Release metadata and verification

`release-manifest.json` manifest version 1 records product version, build
channel, Git commit, UTC build timestamp, Alpine and Memtest86+ versions, and
each ISO's filename, architecture, bootloader, firmware capabilities, size,
and SHA-256. The timestamp is when metadata was generated; it is not a claim
that all embedded upstream files share that timestamp. Verify all four files
with `sha256sum -c SHA256SUMS`.
