<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Stability and Burn-in Testing v1

Stability testing is a separate workflow built on the benchmark engine's bounded process execution. It is not a performance benchmark. Results live in separate schema 1.0 `/run/probeos/stability.json` (plus TXT/HTML), preventing performance measurements, diagnostic health statuses, and stability outcomes from becoming ambiguous.

Local profiles provide a 15-minute Stability Test, 60-minute Burn-in Test, or custom 1-minute-to-24-hour duration. Every run requires a precise local confirmation: high CPU load, bounded allocated-memory load, no storage writes, and thermal monitoring where supported. `stress-ng` uses all logical CPUs and one VM worker capped at the smaller of 2 GiB or half currently available RAM. Nothing starts automatically or remotely.

The engine samples kernel thermal zones and their firmware/kernel-exposed critical trip points. It records initial, maximum, and final temperatures. It does not invent universal temperature limits. When a reported critical trip point is reached, the complete workload process group is stopped and `ABORTED_HARDWARE_SIGNAL` with `aborted_due_to_thermal_limit` is recorded. Missing sensors or thresholds are reported by omission, not guessed. CPU governor and power state are observed, never changed.

Before and after load, the engine calls the Diagnostics Framework's existing storage, thermal, and kernel-signal checks. Thus SMART/NVMe, ECC, machine-check, PCIe, storage-error, and thermal interpretation remains authoritative in diagnostics. Stability compares those interpreted statuses and records new adverse indicators. Its outcomes are `COMPLETED_NO_NEW_ERRORS`, `COMPLETED_WITH_WARNINGS`, `ABORTED_HARDWARE_SIGNAL`, `CANCELLED`, or `ERROR`.

“No new monitored hardware-error indicators were detected during the test” is deliberately bounded evidence, not a guarantee of stability. Cancellation and timeout terminate the process group and preserve a result. The workflow never performs raw storage writes or generates benchmark scores. Web `/stability` and `GET /api/v1/stability` are read-only.
