# Live ISO build audit

Audit baseline: branch `main`, commit
`e4ded173f2938a91dad52f61453811d0923e78cd` (`Implement Hardware
Identification v1`). Hardware Identification v1 and its single
`probe-identify` implementation are unchanged.

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

## Reproduction and qualification

From a clean checkout with Docker, QEMU, xorriso, and (for UEFI) OVMF:

```sh
build/alpine/build-container.sh
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

Qualified artifacts: `out/probeos-x86_64-grub.iso` and
`out/probeos-x86-grub.iso`.

| Architecture | Bootloader | Firmware | Result |
| --- | --- | --- | --- |
| x86_64 | GRUB | SeaBIOS | Userspace, root login, probe and reports pass |
| x86_64 | GRUB | OVMF | Userspace, root login, probe and UEFI report pass |
| x86 | GRUB | SeaBIOS (`qemu-system-i386`) | Userspace, root login, probe and reports pass |

## Known limitations and next work

- There was no checked-in SYSLINUX configuration at the baseline commit.
  SYSLINUX has not been removed, but its artifact variants remain a later
  qualification task once a source configuration is restored or added.
- Automatic GUI startup is not required or qualified here. The stable root
  console/login path is the accepted startup behavior.
- The ISO includes an El Torito EFI image produced by `grub-mkrescue`; it does
  not mirror an `/EFI/BOOT` directory into the visible ISO filesystem. OVMF
  boot qualification passes.
- Memtest86+ remains deliberately outside this live-root milestone.
