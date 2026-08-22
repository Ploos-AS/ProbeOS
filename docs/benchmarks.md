<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Benchmark Framework v1

`probe-benchmark` is the single authoritative performance-testing engine. It is architecturally separate from `probe-diagnostics`: benchmarks answer how quickly a defined workload ran, while diagnostics interpret evidence of malfunction. Benchmark statuses (`COMPLETED`, `SKIPPED`, `CANCELLED`, `ERROR`, and `UNSUPPORTED`) describe execution only. ProbeOS does not rate speed, infer health from throughput, or calculate an overall score.

## Result schema and reproducibility

The engine atomically writes `/run/probeos/benchmarks.json`, `benchmarks.txt`, and standalone, printable, JavaScript-free `benchmarks.html`. JSON schema 1.0 records the engine and benchmark versions, stable registry, selected profile, timestamps and monotonic duration, tool version, parameters, native typed measurements and units, architecture, CPU model/count, memory amount, CPU governor/frequency and AC context where exposed. A timestamp is marked uncertain when the system clock is implausible.

Results are directly comparable only when benchmark ID/version, workload parameters, and relevant tool methodology/version match. Workloads never change silently under an existing ID:

- `cpu.sysbench.single.v1` and `cpu.sysbench.multi.v1`: sysbench prime workload (`max-prime=20000`), 10 seconds by default, one or all logical CPUs.
- `memory.sysbench.read.v1` and `memory.sysbench.write.v1`: 1 MiB sequential blocks in allocated RAM, up to four threads, 10 seconds. “Write” means allocated memory only, never user storage.
- `storage.seq-read.v1`: explicit selected block device, 1 GiB bounded read by default, 1 MiB blocks, direct I/O. Unsupported direct I/O is reported honestly; no buffered methodology substitution is hidden.
- `network.iperf3-tcp.v1`: TCP to an explicitly supplied LAN peer, 10 seconds and one stream. No peer produces `UNSUPPORTED`, not `ERROR`; no Internet service is contacted.

Profiles are registry-driven: `quick`, `cpu`, `memory`, `storage`, `network`, and `full`. Quick attempts CPU and memory and attempts storage only when the local user explicitly selected a device. Full preserves completed results when another component is unsupported, errors, or is cancelled. Defaults keep Quick below five minutes in ordinary conditions; actual duration is always recorded.

## Storage safety

Storage v1 is read-only. It accepts an explicitly selected existing block device (regular files are accepted only to support safe fixture qualification), invokes `dd` with the device solely as `if=`, and sends output to `/dev/null`. The default is bounded to 1 GiB and the CLI maximum is 4 GiB. There is no raw-device write, formatting, filesystem creation, discard/TRIM, write-mode badblocks, endurance test, or automatic all-disk run.

A storage write benchmark is deliberately deferred. ProbeOS live root currently provides no designated workspace whose backing and benchmark meaning can be defended across boot variants. The old ad-hoc temporary-file/fio UI action has been removed.

## Execution policy

Every external command has a bounded timeout and runs in its own process group. SIGINT/SIGTERM stops the group, escalates to SIGKILL after a grace period, and persists `CANCELLED`; completed profile components remain in the result. No benchmark starts at boot, from Quick Check, or through Web/API. TUI/GUI require local opt-in. Web `/benchmarks` and `GET /api/v1/benchmarks[/summary|/cpu|/memory|/storage|/network]` only display files.

CPU, memory, storage, and result rendering are offline. Network needs only the configured LAN peer. No telemetry, cloud upload, serial, UUID, MAC address, or Windows key is retained. Device model may be recorded through privacy-safe inventory context; raw serials are redacted.

Limitations and deferred work include performance scoring/rankings/databases, GPU workloads, destructive disk testing, authenticated remote execution, telemetry, ARM, tuning/overclocking/voltage/fan changes, and write benchmarking.
