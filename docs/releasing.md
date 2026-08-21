# CI and release procedure

ProbeOS uses two GitHub Actions workflows. `CI` runs source validation on pull
requests, pushes to `main`, and manual dispatches, then builds and qualifies all
four ISOs. `Release` runs the same repository scripts for a strict SemVer tag
such as `v0.1.0` and publishes only after every check passes.

## Artifacts

| File | Intended systems | Firmware |
| --- | --- | --- |
| `probeos-x86_64-grub.iso` | Modern/general-purpose x86_64 | BIOS and UEFI |
| `probeos-x86_64-syslinux.iso` | Legacy x86_64 compatibility | BIOS |
| `probeos-x86-grub.iso` | 32-bit x86 and older systems | BIOS |
| `probeos-x86-syslinux.iso` | Maximum legacy x86 compatibility | BIOS |

These descriptions state the qualified boot paths, not universal hardware
compatibility. CI development artifacts are retained for 14 days. Open a CI
run in the Actions tab and download `probeos-isos-<commit SHA>`; ordinary
commits never create permanent GitHub Releases.

Every bundle includes `SHA256SUMS` and `release-manifest.json`. Verify it with:

```sh
sha256sum -c SHA256SUMS
```

The JSON manifest records its schema version, ProbeOS version, full and short
git SHA, UTC build timestamp, Alpine and Memtest86+ versions, and each ISO's
filename, byte size, SHA-256, architecture, and bootloader.

## Qualification and hosted-runner limits

CI runs shell syntax and ShellCheck, whitespace checks, hardware fixtures,
schema/privacy/key-leak checks, the no-JavaScript retro Web/API tests,
networking fixtures, and Alpine 3.19 package resolution for x86 and x86_64.
The expensive job builds all four ISOs in the repository builder container and
checks every layout before running QEMU.

Linux userspace qualification covers x86_64 GRUB under SeaBIOS and OVMF, x86
GRUB under SeaBIOS, and both SYSLINUX architectures under SeaBIOS. Each test
uses `-nic none` and requires the deterministic marker proving `/sbin/init`,
`probe-identify`, valid `report.json`, and the expected firmware mode. A
separate x86_64 GRUB test proves QEMU DHCP, the forwarded Web service, health
and report APIs, valid JSON, and redaction. Memtest-default temporary builds
prove that open-source Memtest86+ v8.10 starts on the same five paths; normal
ProbeOS-default artifacts are rebuilt afterward.

GitHub-hosted runners are not assumed to expose KVM. Tests therefore work with
QEMU's software TCG emulation and have explicit timeouts. TCG is materially
slower than local KVM, especially while Alpine constructs its diskless root.
OVMF is installed from Ubuntu's package, and the helpers validate the standard
4M firmware files; `OVMF_CODE` and `OVMF_VARS` can override those paths locally.
Serial and build logs are uploaded even when CI fails. Reports are validated
inside the guest and are not exported, preventing accidental upload of raw
hardware identifiers or OEM keys.

## Reproduce locally

On Ubuntu, install Docker, `curl`, `jq`, `ovmf`, `qemu-system-x86`,
`shellcheck`, and `xorriso`, then run:

```sh
ci/validate.sh
ci/build-all.sh
ci/qualify.sh
ci/build-all.sh
ci/generate-release-metadata.sh
```

The second build restores normal-default distributable ISOs after deterministic
Memtest qualification. The Dockerfile remains the authoritative Alpine build
environment; the workflows do not duplicate it.

## Publish a release

First ensure CI passes for the exact commit. Then create and push a SemVer tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow checks out that tag, rejects non-strict versions, repeats
validation/build/qualification, verifies checksums and manifest provenance,
then creates the GitHub Release with stable variant notes. It uploads four ISOs,
`SHA256SUMS`, and `release-manifest.json`. Do not reuse or move a published tag.

Workflow dependencies use official GitHub actions pinned to stable major
versions. CI has `contents: read`; only the tag-triggered release workflow has
`contents: write`, which is required by `gh release create`.
