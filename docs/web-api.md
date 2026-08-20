# ProbeOS Retro Web/API v1

ProbeOS includes a small Python standard-library HTTP service. It reads the
authoritative /run/probeos/report.json and /run/probeos/report.txt; it does
not run hardware discovery for page requests and has no frontend build,
JavaScript, CDN, cloud, cookie, or WebSocket dependency.

The default port is 8080. Open http://127.0.0.1:8080/ in local-only mode.
The baseline HTML uses ordinary links, lists, tables/preformatted report
content, and conservative CSS. It remains useful with CSS and JavaScript
disabled and targets simple HTML 4-era browsers while retaining normal modern
browser rendering.

## Pages

The root is a summary. Report sections are available at /system, /cpu,
/memory, /firmware, /motherboard, /pci, /usb, /graphics, /storage, /network,
/sensors, /power, and /windows. /benchmarks explains why remote benchmark
execution is deferred, /export shows a redacted JSON export, and /about
describes the service.

## API

All API responses are JSON:

| Endpoint | Report value |
| --- | --- |
| /api/v1/health | Service state, API version, report availability and generation time |
| /api/v1/report | Complete schema 1.0 report object |
| /api/v1/system ... /api/v1/windows | Corresponding top-level report value |

Unknown API paths return a JSON 404. A missing or malformed report returns
503 from report-backed endpoints; health remains lightweight and reports
report_available: false. Health never starts a probe.

## Privacy

Normal UI/API responses redact keys containing system, board, storage, DIMM or
battery serials, UUIDs, and MAC addresses as [redacted]. The already-masked
Windows OEM key remains masked; a complete key is never present in the
authoritative report and is never returned by this service. Product IDs and
Windows metadata remain distinct from product keys.

For local diagnostics only, a loopback request may use the query
privacy=full to retain identifiers already present in report.json. LAN clients
cannot use this view. The explicit probe-identify --reveal-key and
--export-key behavior remains the only complete-key path.

## Binding and security

The OpenRC service starts automatically on 127.0.0.1 (safe default). The TUI
can enable LAN mode, which binds 0.0.0.0 for a trusted local network. LAN mode
is not an Internet security boundary: there is no TLS or authentication in v1.
Stop the service or return it to local-only mode when it is not needed.

The API is read-only. It has no shell, package manager, arbitrary command, or
remote benchmark endpoint. Benchmark execution remains an explicit local TUI
operation.
