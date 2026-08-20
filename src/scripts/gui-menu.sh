#!/bin/sh
# ProbeOS GUI launcher. Hardware views consume probe-identify reports.
REPORT_DIR=${PROBE_OUTPUT_DIR:-/run/probeos}
REPORT_JSON="$REPORT_DIR/report.json"
REPORT_TEXT="$REPORT_DIR/report.txt"
refresh_probe() { probe-identify --output-dir "$REPORT_DIR" >/tmp/probeos-gui-probe.log 2>&1 || zenity --error --title="ProbeOS hardware probe" --text="The probe could not complete. See /tmp/probeos-gui-probe.log"; }
show_file() { zenity --text-info --title="$1" --width=800 --height=600 --filename="$2"; }
show_json() { tmp=$(mktemp /tmp/probeos-gui.XXXXXX) || return; jq "$2" "$REPORT_JSON" >"$tmp" 2>&1 || echo 'Information unavailable.' >"$tmp"; show_file "$1" "$tmp"; rm -f "$tmp"; }
export_report() { destination=$(zenity --file-selection --directory --title="Export ProbeOS report") || return; stamp=$(date +%Y%m%d-%H%M%S); cp "$REPORT_TEXT" "$destination/probeos-report-$stamp.txt" && cp "$REPORT_JSON" "$destination/probeos-report-$stamp.json" && zenity --info --text="Reports exported to $destination"; }
benchmark_menu() {
    benchmark=$(zenity --list --title="Benchmarks (explicit opt-in)" --column="Benchmark" "CPU (30 seconds)" "Memory" "Temporary-file read") || return
    case "$benchmark" in
        "CPU (30 seconds)") zenity --question --text="Run CPU benchmark for 30 seconds?" && stress-ng --cpu 0 --timeout 30s ;;
        "Memory") zenity --question --text="Run sysbench memory benchmark?" && sysbench memory run ;;
        "Temporary-file read") zenity --question --text="Create a 256 MiB file in /tmp and read it with fio? No block device is selected." || return; file=$(mktemp /tmp/probeos-gui-fio.XXXXXX) || return; dd if=/dev/zero of="$file" bs=1M count=256 status=none && fio --name=probeos-read --rw=read --readonly --filename="$file" --direct=1 --size=256M; rm -f "$file" ;;
    esac
}
refresh_probe
while :; do
    choice=$(zenity --list --title="ProbeOS" --text="Hardware Inspection & Diagnostics" --width=440 --height=500 --column="Action" "System Summary" "CPU" "Memory" "Motherboard / Firmware" "PCI Devices" "USB Devices" "Graphics" "Storage" "Network" "Sensors / Power" "Windows / OEM License" "Run Benchmarks" "Refresh Probe" "Export Report" "Open Terminal" "Reboot" "Power Off") || exit 0
    case "$choice" in
        "System Summary") show_file "$choice" "$REPORT_TEXT" ;; "CPU") show_json "$choice" '.cpu' ;; "Memory") show_json "$choice" '.memory' ;;
        "Motherboard / Firmware") show_json "$choice" '{motherboard,firmware}' ;; "PCI Devices") show_json "$choice" '.pci' ;; "USB Devices") show_json "$choice" '.usb' ;;
        "Graphics") show_json "$choice" '.graphics' ;; "Storage") show_json "$choice" '.storage' ;; "Network") show_json "$choice" '.network' ;;
        "Sensors / Power") show_json "$choice" '{sensors,power}' ;; "Windows / OEM License") show_json "$choice" '.windows' ;; "Run Benchmarks") benchmark_menu ;; "Refresh Probe") refresh_probe ;;
        "Export Report") export_report ;; "Open Terminal") rxvt & ;; "Reboot") reboot ;; "Power Off") poweroff ;;
    esac
done
