# Live ISO build audit

Audit baseline: branch `main`, commit
`e4ded173f2938a91dad52f61453811d0923e78cd` (`Implement Hardware
Identification v1`). Hardware Identification v1 and its single
`probe-identify` implementation are unchanged.

The SYSLINUX legacy BIOS milestone started from branch `main`, clean at commit
`9926a832817b90a99196006adbd5b9555f0a7053`. No SYSLINUX configuration was
present in that tree or in relevant repository history.

## Original failure and diagnosis

The baseline Alpine builder installed a complete system into
`build/alpine/work`, generated an ordinary `mkinitfs`, and copied only the
kernel and initramfs into the ISO. The staged root was never represented as an
Alpine live root: the ISO had no offline APK repository, `.boot_repository`,
apkovl, or modloop. GRUB could therefore load the kernel, but the Alpine
initramfs had no material from which to construct userspace. Kernel launch was
not evidence of a bootable live system.

During restoration, the first Alpine-diskless build was booted in QEMU and
captured at `/tmp/probeos-current-bios.log`. The observed stage chain was:

```text
SeaBIOS -> GRUB -> Linux -> Alpine Init -> boot-media mount -> live package
installation -> /sbin/init -> OpenRC -> local service -> login prompt
```

That intermediate image exposed two further concrete faults. APK reported 32
`package mentioned in index not found` errors because `noarch` APK entries had
not been rewritten to the media architecture. The incomplete root also lacked
`/var/log` when the local service tried to redirect probe output there, so the
shell failed before invoking `probe-identify`. At the console, invoking the
unchanged probe directly succeeded and produced valid reports.

## Repair and live architecture

The repair uses Alpine's diskless/live conventions and keeps the existing GRUB
architecture:

This layout follows Alpine's documented
[diskless mode](https://wiki.alpinelinux.org/wiki/Diskless_Mode) and
[boot-repository discovery](https://wiki.alpinelinux.org/wiki/Local_APK_cache)
behavior.

- `/.alpine-release` identifies Alpine media.
- `/apks/.boot_repository` selects the on-media repository; packages reside in
  `/apks/<arch>` with a locally signed `APKINDEX.tar.gz`.
- The repository contains every package recorded in the staged apk database,
  including conditional `install_if` packages. `apk index --rewrite-arch`
  makes `noarch` entries usable through the architecture-specific live repo.
- `/boot/modloop-lts` is a SquashFS image of the matching kernel modules.
- `/probeos.apkovl.tar.gz` supplies configured `/etc`, ProbeOS scripts and
  assets. Alpine Init discovers it from the boot media and constructs the
  tmpfs root; `/sbin/init` is installed by `alpine-base` and starts OpenRC.
- GRUB passes the upstream-style `modules=loop,squashfs,sd-mod,usb-storage` and
  `modloop=/boot/modloop-lts` parameters. Media discovery is automatic, so no
  device-specific `alpine_dev` is hard-coded. `alpine_repo` is likewise
  unnecessary because `.boot_repository` identifies the ISO repository.
- SYSLINUX passes the same modules and modloop parameters. It likewise leaves
  `alpine_dev` and `alpine_repo` unset so Alpine discovers the `PROBEOS` media,
  root-level apkovl, and `/apks/.boot_repository`. Kernel and initramfs paths
  remain `/boot/vmlinuz` and `/boot/initramfs` for both loaders.
- A serial-capable text entry retains `tty0` and adds `ttyS0,115200` for test
  automation. It is the conservative default for this milestone.
- OpenRC's local service runs the existing `/usr/local/bin/probe-identify`,
  validates JSON with `jq`, verifies the text report is non-empty, and emits a
  serial marker including the report's detected firmware mode. Logs and
  reports are kept under `/run/probeos`.

GRUB and GRUB EFI are builder dependencies, not guest packages. Keeping them
out of the diskless root avoids a GRUB install trigger attempting to probe a
tmpfs as a persistent boot disk. The build container supplies `grub-mkrescue`.

The ISO volume label is `PROBEOS`. Kernel, initramfs, modloop, release marker,
apkovl, and APK repository are all on the ISO; boot qualification runs QEMU
with `-nic none`, proving the default identification path has no network
dependency.

## SYSLINUX BIOS construction

The version-controlled menu is `boot/syslinux/isolinux.cfg`. During a
`BOOTLOADER=syslinux` build, Alpine's `syslinux` package supplies
`isolinux.bin`, `ldlinux.c32`, `menu.c32`, `libcom32.c32`, and `libutil.c32`;
these generated build inputs are copied beside the config and are not committed.
Placing `isolinux.cfg` beside `isolinux.bin` provides standard ISOLINUX config
discovery.

`xorriso -as mkisofs` creates a no-emulation BIOS El Torito image using
`boot/syslinux/isolinux.bin`, patches its boot info table, and installs the
standard `isohdpfx.bin` MBR with a partition offset of 16. The result has
optical and isohybrid structures intended for optical media and raw USB
writing. Actual physical boot success is evidence-recorded separately; build
structure alone is not a physical compatibility claim. No EFI image is added:
GRUB owns the implemented UEFI path.

## Reproduction and qualification

From a clean checkout with Docker, QEMU, xorriso, and (for UEFI) OVMF:

```sh
build/alpine/build-container.sh
BOOTLOADER=syslinux build/alpine/build-container.sh
ARCH=x86 build/alpine/build-container.sh
ARCH=x86 BOOTLOADER=syslinux build/alpine/build-container.sh
tests/iso-layout.sh out/probeos-x86_64-grub.iso
PROBEOS_QEMU_TIMEOUT=120 tests/qemu-smoke.sh \
  out/probeos-x86_64-grub.iso bios /tmp/probeos-bios.log
PROBEOS_QEMU_TIMEOUT=140 tests/qemu-smoke.sh \
  out/probeos-x86_64-grub.iso uefi /tmp/probeos-uefi.log
tests/run-tests.sh
bash -n build/alpine/*.sh tests/*.sh src/scripts/* src/lib/*.sh
shellcheck build/alpine/*.sh tests/*.sh src/scripts/* src/lib/*.sh
```

The layout test requires a non-empty ISO plus all Alpine live components and
the offline APK index. The smoke test requires the guest-side marker proving
`/sbin/init`, `probe-identify`, non-empty text output, valid JSON, and the
expected BIOS/UEFI value from `.firmware.boot_mode`. Serial logs are retained
as test artifacts at the requested paths.

QEMU-qualified artifacts: `out/probeos-x86_64-grub.iso` and
`out/probeos-x86-grub.iso`.

| Architecture | Bootloader | Firmware | Result |
| --- | --- | --- | --- |
| x86_64 | GRUB | SeaBIOS | Userspace, root login, probe and reports pass |
| x86_64 | GRUB | OVMF | Userspace, root login, probe and UEFI report pass |
| x86 | GRUB | SeaBIOS (`qemu-system-i386`) | Userspace, root login, probe and reports pass |
| x86_64 | SYSLINUX | SeaBIOS | Userspace, root login, probe and reports pass |
| x86 | SYSLINUX | SeaBIOS (`qemu-system-i386`) | Userspace, root login, probe and reports pass |

Memtest86+ v8.10 also starts under every row above; see [memtest.md](memtest.md).
All QEMU qualification uses `-nic none`. SYSLINUX commands are:

```sh
tests/qemu-smoke.sh out/probeos-x86_64-syslinux.iso bios
QEMU=qemu-system-i386 tests/qemu-smoke.sh out/probeos-x86-syslinux.iso bios
```

## Known limitations and next work

- SYSLINUX artifacts support legacy BIOS only. UEFI, including the separately
  unqualified IA32 UEFI path, remains a GRUB responsibility.
- Automatic GUI startup is not required or qualified here. The stable root
  console/login path is the accepted startup behavior.
- The ISO includes an El Torito EFI image produced by `grub-mkrescue`; it does
  not mirror an `/EFI/BOOT` directory into the visible ISO filesystem. OVMF
  boot qualification passes.
- Open-source Memtest86+ v8.10 is now integrated as a direct GRUB standalone
  entry; see [memtest.md](memtest.md) for its provenance and qualification.

## CI and release engineering

GitHub Actions now reproduces this architecture through the same Alpine builder
container. The fast validation job runs before ISO work; the expensive job
builds and layout-checks all four architecture/loader variants, runs the five
qualified offline QEMU Linux paths, exercises x86_64 DHCP/Web/API, and starts
Memtest86+ v8.10 on its five qualified paths. Temporary LAN- and
Memtest-default images are never published: the four normal-default artifacts
are rebuilt before checksums and provenance metadata are generated.

Hosted runners use QEMU TCG when KVM is unavailable. Ubuntu's `ovmf` package
provides the validated 4M firmware paths. See [releasing.md](releasing.md) for
workflow structure, runner limitations, local reproduction, and tag releases.
