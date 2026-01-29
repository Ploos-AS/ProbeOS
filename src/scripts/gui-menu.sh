#!/bin/sh

# ProbeOS GUI Menu
# https://probeos.eu
# © 2026 Ploos AS

TITLE="ProbeOS"
FOOTER="https://probeos.eu  © 2026 Ploos AS"

main_menu() {
    CHOICE=$(zenity \
        --list \
        --title="$TITLE" \
        --text="Hardware Inspection & Diagnostics" \
        --width=400 \
        --height=350 \
        --column="Action" \
        "System Summary" \
        "CPU Information" \
        "Memory Information" \
        "Storage Devices" \
        "Sensors & Thermals" \
        "Run Benchmarks" \
        "Export Report" \
        "Open Terminal" \
        "Reboot" \
        "Power Off")

    case "$CHOICE" in
        "System Summary") system_summary ;;
        "CPU Information") cpu_info ;;
        "Memory Information") mem_info ;;
        "Storage Devices") storage_info ;;
        "Sensors & Thermals") sensor_info ;;
        "Run Benchmarks") benchmark_menu ;;
        "Export Report") export_report ;;
        "Open Terminal") open_terminal ;;
        "Reboot") reboot ;;
        "Power Off") poweroff ;;
        *) exit 0 ;;
    esac
}

system_summary() {
    zenity --text-info \
        --title="System Summary" \
        --width=700 --height=500 \
        --filename=<(inxi -Fxz)
}

cpu_info() {
    zenity --text-info \
        --title="CPU Information" \
        --width=700 --height=500 \
        --filename=<(lscpu)
}

mem_info() {
    zenity --text-info \
        --title="Memory Information" \
        --width=700 --height=500 \
        --filename=<(free -h; echo; cat /proc/meminfo)
}

storage_info() {
    zenity --text-info \
        --title="Storage Devices" \
        --width=700 --height=500 \
        --filename=<(lsblk; echo; blkid)
}

sensor_info() {
    zenity --text-info \
        --title="Sensors & Thermals" \
        --width=700 --height=500 \
        --filename=<(sensors 2>/dev/null || echo "No sensors detected.")
}

benchmark_menu() {
    CHOICE=$(zenity \
        --list \
        --title="Benchmarks" \
        --width=350 --height=250 \
        --column="Benchmark" \
        "CPU Stress Test" \
        "Memory Bandwidth Test" \
        "Disk Benchmark" \
        "Back")

    case "$CHOICE" in
        "CPU Stress Test") stress-ng --cpu 0 --timeout 30s ;;
        "Memory Bandwidth Test") mbw 128 ;;
        "Disk Benchmark") fio --name=readtest --rw=read --size=256M --filename=/tmp/fio.test --direct=1 ;;
        *) return ;;
    esac
}

export_report() {
    OUT="/tmp/probeos-report.txt"
    {
        echo "ProbeOS Report"
        echo "https://probeos.eu"
        echo "© 2026 Ploos AS"
        echo
        date
        echo
        inxi -Fxz
        lscpu
        free -h
        lsblk
    } > "$OUT"

    zenity --info --text="Report written to:\n$OUT"
}

open_terminal() {
    rxvt &
}

while true; do
    main_menu
done
