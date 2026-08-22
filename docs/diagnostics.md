<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Diagnostics Framework v1

`probe-diagnostics` is the single authoritative diagnostics engine for ProbeOS.
The TUI and GUI are clients of it; reports and the Web/API only render its most
recent result set. The unauthenticated Web/API cannot start checks.

## Documents and compatibility

Hardware inventory remains the authoritative schema 1.1 `report.json` document.
Diagnostics use a separate, additive `diagnostics.json` schema 1.0 document in
`/run/probeos`. This avoids changing existing hardware report/API consumers.
When diagnostic results exist, the report renderer links a concise summary into
the sale profile and redacted evidence into detailed/full profiles. When no
check has run, reports say `Hardware Check: Not run`; report generation never
silently runs diagnostics.

The engine also writes `diagnostics.txt` and standalone `diagnostics.html`.
Only the most recent result set is retained in v1.

## Result model

Every result contains a stable `id`, category, name, status, severity, precise
summary, evidence/measurements, UTC timestamp, duration, safety class,
`destructive`, `requires_user_action`, and an `unavailable_reason` when useful.
Categories are system, CPU, memory, storage, network, thermal, battery,
firmware, PCI, USB, and graphics.

The bounded statuses are:

- `PASS`: available evidence met the check's defined conditions.
- `WARN`: evidence warrants review but does not prove hardware failure.
- `FAIL`: clear hardware-failure evidence was observed.
- `UNKNOWN`: the condition could not be determined.
- `SKIPPED`: policy, cancellation, or an unsafe requested allocation prevented a run.
- `ERROR`: the check itself failed to execute correctly; this is not automatically a hardware failure.

Aggregation is deterministic: any FAIL makes the group FAIL; otherwise any WARN
makes it WARN; otherwise an execution ERROR makes it ERROR; one or more PASS
results with only PASS/SKIPPED companions make it PASS; all other combinations
are UNKNOWN. Individual results are always retained.

ProbeOS deliberately prefers UNKNOWN or WARN over a false FAIL. Missing tools,
missing metadata, disconnected cables, unsupported health passthrough, and
unbound optional drivers do not prove broken hardware.

## Safety and execution policy

Each registered check is one of:

- `passive`: reads existing data only.
- `safe_active`: bounded activity that does not modify user data.
- `stress`: intentionally loads hardware and requires explicit local action.
- `destructive`: could modify/delete data and is prohibited in v1.

Quick Check uses passive checks. CPU, userspace memory, and raw-device read tests
are explicit local actions. External commands have bounded timeouts. Active
children run in their own process group; interruption terminates the complete
group and records cancellation as SKIPPED. No raw-device write test, filesystem
repair, format operation, destructive `fio`, or `badblocks -w` exists.

## Quick Check

`probe-diagnostics quick` is offline, non-destructive, and normally completes in
seconds, although firmware and drive queries vary. Each external query has a
20-second default timeout. It inspects:

The diskless live startup runs this default passive workflow after inventory and
records the observed whole-second duration in the QEMU boot marker. Generating a
report later does not itself run Quick Check; outside normal live startup, a
missing diagnostics document is rendered as `Not run`.

On 2026-08-22 the five offline QEMU/TCG qualification paths observed Quick Check
durations of 2–3 seconds (the complete ISO boots took substantially longer).
Physical drive firmware queries may take longer and remain protected by command
timeouts.

- system identity availability;
- firmware identity/date/version, BIOS/UEFI mode, Secure Boot state when known,
  SMBIOS and ACPI access;
- CPU topology consistency, online visibility, architecture, capabilities and
  virtualization metadata;
- usable memory, DIMM/slot consistency, and exposed ECC metadata without
  claiming full RAM verification;
- device-aware ATA SMART and NVMe health, error counters, wear, spare,
  temperature, and power-on evidence;
- interface/controller/driver/link state without requiring Internet or treating
  an unplugged cable as FAIL;
- sensor temperatures using reported critical/max limits. With no reliable
  limit, ProbeOS reports the reading without inventing a FAIL threshold;
- battery charge, state, cycle count, and health percentage only when derived
  from full-charge/design capacity;
- PCI, USB, and graphics enumeration/driver presence conservatively;
- targeted kernel signals for ECC, storage I/O/reset/timeout, PCIe AER, USB, and
  thermal throttling. It does not match the generic word “error.”

## Explicit active diagnostics

`probe-diagnostics cpu --duration 60` runs a bounded `stress-ng` CPU workload.
It records duration, workers, termination, and tool evidence. This is a
diagnostic workload, not a benchmark score.

`probe-diagnostics memory` uses `memtester`, reserves at least 512 MiB and at
least one quarter of available RAM, defaults to no more than 2 GiB, and refuses
an override that violates the reserve. It records the amount tested. A userspace
memory test is not boot-time Memtest86+: for deeper full-memory testing, reboot
into the separately qualified Memtest86+ v8.10 boot option.

`probe-diagnostics storage-read --device /dev/nvme0n1 --read-mib 4096` reads a
bounded amount directly to `/dev/null`. It performs no writes, does not mount a
filesystem, records read errors and throughput as evidence only, and never
automatically scans a whole drive.

SMART firmware self-tests are deferred from v1. Read-only health collection is
implemented; integrating start/poll semantics safely would expand this
milestone, and inability to start such a test must never become a hardware FAIL.

Network active mode reports local interface state. DHCP configuration remains a
separate explicit runtime network function. Gateway or explicitly configured
local `iperf3` checks can be added later; Internet access is never a health
requirement.

## Privacy and interfaces

Diagnostics evidence is redacted independently of hardware reports. Serial
numbers, UUIDs, MAC addresses, and Windows product keys are excluded. Normal
sale/detailed/full exports and LAN Web/API remain privacy-safe. The local TUI
and GUI can run and export diagnostics as TXT/JSON/HTML. Web `/diagnostics` and
`GET /api/v1/diagnostics[/summary|/cpu|/memory|/storage|/network|/thermal|/battery]`
only display the latest files. There is no remote execution endpoint, shell,
upload, authentication bypass, or cloud reporting.

## Limitations

Availability and quality depend on firmware, kernel drivers, device health
interfaces, and architecture-specific Alpine packages. USB bridges frequently
block SMART passthrough. Sensor labels and thresholds vary. Passive checks do
not certify hardware, userspace memory testing cannot cover memory reserved by
the kernel, and a successful bounded read is not proof that every sector is
readable. GPU stress, burn-in, benchmark scoring, destructive storage testing,
history databases, remote control, and arbitrary health percentages are
intentionally deferred.
