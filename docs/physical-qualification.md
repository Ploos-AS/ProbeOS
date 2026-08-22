<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Physical hardware qualification

`probe-qualify` runs locally and entirely offline. Standard qualification is a
short compatibility procedure, not hardware certification, performance
comparison, a long stability claim, or a full Memtest pass.

## Technician checklist

1. Verify the ISO checksum on the preparation computer and boot ProbeOS.
2. Record the actual architecture, bootloader, firmware path, and boot medium.
3. Run `probe-qualify start --boot-medium usb` (choose the true medium).
4. Confirm the visible boot menu, console, keyboard, GUI, and pointer where tested.
5. Confirm Quick Check ran; inspect health WARN separately from compatibility.
6. Test wired DHCP only when a cable and DHCP LAN are available; Internet is unnecessary.
7. Optionally check the read-only Web/API from the trusted LAN.
8. Optionally run a short benchmark/stability smoke test. Do not treat it as a burn-in.
9. Optionally reboot into Memtest86+ and record startup separately from completion.
10. Confirm the record, export the privacy-safe bundle, then test reboot/poweroff if desired.

Useful local commands:

```sh
probe-qualify status
probe-qualify observe console_display PASS --note "Console readable"
probe-qualify observe keyboard PASS
probe-qualify memtest PASS
probe-qualify confirm
probe-qualify export /media/usb
```

Operator observations are labelled `operator_observed`; no typed content is
captured. Notes are sanitized and never override a status. Missing Ethernet,
UEFI, ACPI, DMI, NVMe, SMART, sensors, battery, USB 3, or other modern features
does not itself fail an old machine. Storage qualification enumerates devices
and reads health only; it never writes to user disks. Secure Boot state is
recorded when known, but Secure Boot is not supported. IA32 UEFI is not claimed.

Memtest `startup` and `test_completed` are distinct. A normal record does not
require either. Benchmark smoke is a short engine/CPU-result check; standard
qualification never starts a 15/60-minute stability run. A brief optional
stability-engine smoke test is not evidence of long-term stability.

## Booting from USB safely

ProbeOS ISO-hybrid images may be written raw on Linux. This destroys all data
on the selected target device. Identify the removable device with `lsblk`,
unmount its partitions, verify the name and size twice, and substitute the
whole device—not a partition—in this example:

```sh
sudo dd if=probeos-x86_64-grub.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Never copy the example `/dev/sdX` blindly. ProbeOS itself has no automatic
image-writing feature. Optical and USB successes are recorded separately.

## Early boot failures

If userspace is never reached, use a developer machine to create a manual
record with provenance `manual_early_boot`. Record machine make/model when
safe, exact ISO filename and verified SHA-256, bootloader/firmware/medium,
each stage actually reached, last visible message, structured FAIL/NOT_TESTED
statuses, firmware quirks, and concise operator notes. Do not invent a runtime
report. An optional textual photo/screenshot reference may point to evidence
maintained elsewhere; photos are neither embedded in Git nor mandatory.

Observed quirks may include CSM required, UEFI-only mode, boot ordering,
removable-media path, boot-menu hotkey, optical-only, USB 2 port required, or
Secure Boot disabled. Record only what was actually observed.

## Limitations

An exact ISO SHA-256 often cannot be recovered reliably from a running USB or
optical filesystem. The workflow stores it when supplied; otherwise it records
the embedded release commit/build identity and explicitly marks that limitation.
No telemetry, account, cloud, upload, API key, public submission, or RAB runtime
dependency exists. The exported bundle remains under the operator's control.
