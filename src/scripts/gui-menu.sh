#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# ProbeOS GUI launcher. Hardware views consume probe-identify reports.
REPORT_DIR=${PROBE_OUTPUT_DIR:-/run/probeos}
REPORT_JSON="$REPORT_DIR/report.json"
refresh_probe() { probe-identify --output-dir "$REPORT_DIR" >/tmp/probeos-gui-probe.log 2>&1 || zenity --error --title="ProbeOS hardware probe" --text="The probe could not complete. See /tmp/probeos-gui-probe.log"; }
show_file() { zenity --text-info --title="$1" --width=800 --height=600 --filename="$2"; }
show_json() { tmp=$(mktemp /tmp/probeos-gui.XXXXXX) || return; jq "$2" "$REPORT_JSON" >"$tmp" 2>&1 || echo 'Information unavailable.' >"$tmp"; show_file "$1" "$tmp"; rm -f "$tmp"; }
run_diagnostic() { tmp=$(mktemp /tmp/probeos-gui-diagnostic.XXXXXX) || return; probe-diagnostics "$@" --output-dir "$REPORT_DIR" >"$tmp" 2>&1 || true; show_file "Diagnostic Results" "$tmp"; rm -f "$tmp"; }
diagnostics_menu() {
    diagnostic=$(zenity --list --title="Diagnostics" --column="Diagnostic" "Quick Check" "CPU Diagnostic" "Userspace Memory Test" "Storage Health" "Storage Read Test" "Network Diagnostic" "View Results" "Export Results" "Memtest86+ information") || return
    case "$diagnostic" in
        "Quick Check") run_diagnostic quick ;;
        "CPU Diagnostic") zenity --question --text="Runs a CPU workload for 60 seconds and stops it on cancellation." && run_diagnostic cpu --duration 60 ;;
        "Userspace Memory Test") zenity --question --text="Tests a conservative amount of available RAM. This is not boot-time Memtest86+." && run_diagnostic memory ;;
        "Storage Health") run_diagnostic storage-health ;;
        "Storage Read Test") device=$(zenity --entry --text="Device to read (example /dev/nvme0n1):") || return; zenity --question --text="Reads 4 GiB from $device. No data will be written." && run_diagnostic storage-read --device "$device" --read-mib 4096 ;;
        "Network Diagnostic") run_diagnostic network ;;
        "View Results") if [ -s "$REPORT_DIR/diagnostics.txt" ]; then show_file "Diagnostic Results" "$REPORT_DIR/diagnostics.txt"; else zenity --info --text="Diagnostics have not been run."; fi ;;
        "Export Results") destination=$(zenity --file-selection --directory --title="Export diagnostic results") || return; stamp=$(date +%Y%m%d-%H%M%S); for extension in txt json html; do cp "$REPORT_DIR/diagnostics.$extension" "$destination/probeos-diagnostics-$stamp.$extension" || return; done ;;
        "Memtest86+ information") zenity --info --text="For deeper full-memory testing, reboot into Memtest86+ from the ProbeOS boot menu." ;;
    esac
}
export_report() { profile=$1; destination=$(zenity --file-selection --directory --title="Export ProbeOS $profile report") || return; stamp=$(date +%Y%m%d-%H%M%S); cp "$REPORT_DIR/$profile.txt" "$destination/probeos-$profile-$stamp.txt" && cp "$REPORT_DIR/$profile.json" "$destination/probeos-$profile-$stamp.json" || return; [ "$profile" != sale ] || cp "$REPORT_DIR/sale.html" "$destination/probeos-sale-$stamp.html"; zenity --info --text="$profile report exported to $destination"; }
reveal_key() { zenity --question --text="Show Windows Product Key? This is sensitive; reuse and activation are not guaranteed." || return; tmp=$(mktemp /tmp/probeos-gui-key.XXXXXX) || return; probe-identify --output-dir "$REPORT_DIR" --reveal-key >"$tmp" 2>&1; show_file "Sensitive Windows Product Key" "$tmp"; rm -f "$tmp"; }
export_license() { destination=$(zenity --file-selection --save --confirm-overwrite --filename="probeos-windows-license.txt" --title="Export sensitive Windows license information") || return; probe-identify --output-dir "$REPORT_DIR" --export-key "$destination" >/dev/null 2>&1 && zenity --info --text="Sensitive export written with mode 0600."; }
benchmark_menu() {
    benchmark=$(zenity --list --title="Benchmarks (explicit opt-in)" --column="Benchmark" "Quick Benchmark" "CPU Benchmark" "Memory Benchmark" "Storage Read Benchmark" "Network Benchmark" "Full Benchmark" "View Results" "Export Results") || return
    case "$benchmark" in
        "Quick Benchmark") run_benchmark quick ;;
        "CPU Benchmark") run_benchmark cpu ;;
        "Memory Benchmark") run_benchmark memory ;;
        "Storage Read Benchmark") device=$(zenity --entry --text="Device to READ (example /dev/nvme0n1):") || return; run_benchmark storage --device "$device" ;;
        "Network Benchmark") peer=$(zenity --entry --text="Explicit LAN iperf3 server address:") || return; run_benchmark network --peer "$peer" ;;
        "Full Benchmark") run_benchmark full ;;
        "View Results") if [ -s "$REPORT_DIR/benchmarks.txt" ]; then show_file "Benchmark Results" "$REPORT_DIR/benchmarks.txt"; else zenity --info --text="Benchmarks have not been run."; fi ;;
        "Export Results") export_results benchmarks ;;
    esac
}
run_benchmark() { profile=$1; shift; zenity --question --text="Run $profile benchmark? Workloads are bounded and cancellable; storage is read-only." || return; tmp=$(mktemp /tmp/probeos-gui-benchmark.XXXXXX) || return; probe-benchmark run "$profile" "$@" --output-dir "$REPORT_DIR" >"$tmp" 2>&1 || true; show_file "Benchmark Results" "$tmp"; rm -f "$tmp"; }
export_results() { kind=$1; destination=$(zenity --file-selection --directory --title="Export $kind results") || return; stamp=$(date +%Y%m%d-%H%M%S); for extension in txt json html; do cp "$REPORT_DIR/$kind.$extension" "$destination/probeos-$kind-$stamp.$extension" || return; done; }
stability_menu() { choice=$(zenity --list --title="Stability / Burn-in" --column="Test" "15-minute Stability Test" "60-minute Burn-in Test" "Custom Duration" "View Results" "Export Results") || return; case "$choice" in "15-minute Stability Test") seconds=900;; "60-minute Burn-in Test") seconds=3600;; "Custom Duration") minutes=$(zenity --entry --text="Duration in minutes (1-1440):" --entry-text="15") || return; seconds=$((minutes * 60));; "View Results") [ -s "$REPORT_DIR/stability.txt" ] && show_file "Stability Results" "$REPORT_DIR/stability.txt"; return;; "Export Results") export_results stability; return;; esac; zenity --question --text="ProbeOS Stability Test\n\nDuration: $((seconds / 60)) minutes\nCPU load: high\nMemory load: bounded\nStorage writes: none\n\nTemperatures will be monitored where supported." || return; tmp=$(mktemp /tmp/probeos-gui-stability.XXXXXX) || return; probe-benchmark stability --duration "$seconds" --output-dir "$REPORT_DIR" >"$tmp" 2>&1 || true; show_file "Stability Results" "$tmp"; rm -f "$tmp"; }
qualification_menu() {
    action=$(zenity --list --title="Compatibility / Qualification" --column="Local action" "Start Physical Qualification" "View Qualification Status" "Record Console PASS" "Record Keyboard PASS" "Record Memtest Startup" "Export Privacy-safe Bundle") || return
    case "$action" in
        "Start Physical Qualification") medium=$(zenity --list --title="Actual boot medium" --column="Medium" optical usb virtual_cd virtual_disk other) || return; probe-qualify start --boot-medium "$medium" --output-dir "$REPORT_DIR" --report-dir "$REPORT_DIR" >/tmp/probeos-gui-qualification.log 2>&1; show_file "Physical Qualification" "$REPORT_DIR/qualification.txt" ;;
        "View Qualification Status") if [ -s "$REPORT_DIR/qualification.txt" ]; then show_file "Physical Qualification" "$REPORT_DIR/qualification.txt"; else zenity --info --text="Qualification has not been started."; fi ;;
        "Record Console PASS") probe-qualify observe console_display PASS >/dev/null ;;
        "Record Keyboard PASS") probe-qualify observe keyboard PASS >/dev/null ;;
        "Record Memtest Startup") probe-qualify memtest PASS >/dev/null ;;
        "Export Privacy-safe Bundle") destination=$(zenity --file-selection --directory --title="Export privacy-safe qualification bundle") || return; if probe-qualify export "$destination" >/tmp/probeos-gui-qualification-export.log 2>&1; then zenity --info --text="Privacy-safe bundle exported to $destination"; else show_file "Export error" /tmp/probeos-gui-qualification-export.log; fi ;;
    esac
}
refresh_probe
while :; do
    choice=$(zenity --list --title="ProbeOS" --text="Hardware Inspection & Diagnostics" --width=480 --height=600 --column="Action" "View Sale Report" "View Detailed Report" "View Full Report" "CPU" "Memory" "Motherboard / Firmware" "PCI Devices" "USB Devices" "Graphics" "Storage" "Network" "Sensors / Power" "Windows License Summary" "Show Windows Product Key" "Export Windows License Information" "Run Diagnostics" "Run Benchmarks" "Stability / Burn-in" "Compatibility / Qualification" "Refresh Probe" "Export Sale Report" "Export Detailed Report" "Export Full Report" "Open Terminal" "Reboot" "Power Off") || exit 0
    case "$choice" in
        "View Sale Report") show_file "$choice" "$REPORT_DIR/sale.txt" ;; "View Detailed Report") show_file "$choice" "$REPORT_DIR/detailed.txt" ;; "View Full Report") show_file "$choice" "$REPORT_DIR/full.txt" ;; "CPU") show_json "$choice" '.cpu' ;; "Memory") show_json "$choice" '.memory' ;;
        "Motherboard / Firmware") show_json "$choice" '{motherboard,firmware}' ;; "PCI Devices") show_json "$choice" '.pci' ;; "USB Devices") show_json "$choice" '.usb' ;;
        "Graphics") show_json "$choice" '.graphics' ;; "Storage") show_json "$choice" '.storage' ;; "Network") show_json "$choice" '.network' ;;
        "Sensors / Power") show_json "$choice" '{sensors,power}' ;; "Windows License Summary") show_json "$choice" '.windows' ;; "Show Windows Product Key") reveal_key ;; "Export Windows License Information") export_license ;; "Run Diagnostics") diagnostics_menu ;; "Run Benchmarks") benchmark_menu ;; "Stability / Burn-in") stability_menu ;; "Compatibility / Qualification") qualification_menu ;; "Refresh Probe") refresh_probe ;;
        "Export Sale Report") export_report sale ;; "Export Detailed Report") export_report detailed ;; "Export Full Report") export_report full ;; "Open Terminal") rxvt & ;; "Reboot") reboot ;; "Power Off") poweroff ;;
    esac
done
