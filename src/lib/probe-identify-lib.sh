#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Parser/collector library for probe-identify. Functions are fixture-testable.

have() { command -v "$1" >/dev/null 2>&1; }
fixture_path() { [[ -n "${PROBE_FIXTURE_DIR:-}" && -e "$PROBE_FIXTURE_DIR/$1" ]] && printf '%s\n' "$PROBE_FIXTURE_DIR/$1"; }
run() {
    local name=$1 fixture
    shift
    fixture=$(fixture_path "$name")
    if [[ -n "$fixture" ]]; then cat "$fixture"; return 0; fi
    [[ -n "${PROBE_FIXTURE_DIR:-}" ]] && return 127
    have "$name" || return 127
    if have timeout; then timeout "${PROBE_COMMAND_TIMEOUT:-20}" "$name" "$@" 2>/dev/null; else "$name" "$@" 2>/dev/null; fi
}
capture() {
    local label=$1; shift
    if run "$@" > "$TMP/$label"; then printf 'ok\n' > "$TMP/$label.status"; else : > "$TMP/$label"; printf 'unavailable\n' > "$TMP/$label.status"; fi
}
status_for() { [[ -s "$TMP/$1.status" ]] && cat "$TMP/$1.status" || printf 'unavailable\n'; }
nullify() { [[ -n "$1" ]] && printf '%s' "$1" || printf 'null'; }

parse_cpu() {
    local file=$1
    [[ -s "$file" ]] || { printf '[]'; return; }
    awk -F: '
      function trim(s){gsub(/^[ \t]+|[ \t]+$/, "", s); return s}
      {k=trim($1); $1=""; sub(/^:/,""); v=trim($0); a[k]=v}
      END {
        print "{";
        keys[1]="Vendor ID"; names[1]="vendor"; keys[2]="Model name"; names[2]="model";
        keys[3]="Architecture"; names[3]="architecture"; keys[4]="CPU family"; names[4]="family";
        keys[5]="Model"; names[5]="model_number"; keys[6]="Stepping"; names[6]="stepping";
        keys[7]="Socket(s)"; names[7]="sockets"; keys[8]="Core(s) per socket"; names[8]="cores_per_socket";
        keys[9]="CPU(s)"; names[9]="threads"; keys[10]="Thread(s) per core"; names[10]="threads_per_core";
        keys[11]="CPU max MHz"; names[11]="max_mhz"; keys[12]="CPU min MHz"; names[12]="min_mhz";
        keys[13]="CPU MHz"; names[13]="current_mhz"; keys[14]="L1d cache"; names[14]="l1d_cache";
        keys[15]="L1i cache"; names[15]="l1i_cache"; keys[16]="L2 cache"; names[16]="l2_cache";
        keys[17]="L3 cache"; names[17]="l3_cache"; keys[18]="Flags"; names[18]="flags";
        keys[19]="Virtualization"; names[19]="virtualization"; keys[20]="Hypervisor vendor"; names[20]="hypervisor";
        for(i=1;i<=20;i++){gsub(/\\/,"\\\\",a[keys[i]]);gsub(/\"/,"\\\"",a[keys[i]]); printf "\"%s\":\"%s\"%s",names[i],a[keys[i]],i<20?",":""}
        print "}";
      }' "$file" | jq '[. | with_entries(.value |= if .=="" then null else . end) | .cores=((.sockets|tonumber? // 0) * (.cores_per_socket|tonumber? // 0) | if .==0 then null else . end) | .microcode=null]'
}

dmi_value() {
    local file=$1 section=$2 key=$3
    [[ -s "$file" ]] || return 0
    awk -v section="$section" -v key="$key" '
      $0 ~ "^[[:space:]]*" section "$" {inside=1; next}
      inside && /^[^[:space:]]/ {exit}
      inside {line=$0; sub(/^[[:space:]]*/,"",line); if(index(line,key ":")==1){sub(/^[^:]*:[[:space:]]*/,"",line); print line; exit}}
    ' "$file"
}

parse_dmi() {
    local file=$1
    jq -n --arg system "$(dmi_value "$file" 'System Information' 'Product Name')" \
      --arg board "$(dmi_value "$file" 'Base Board Information' 'Product Name')" \
      --arg bios "$(dmi_value "$file" 'BIOS Information' 'Version')" \
      'def n($x):if $x=="" then null else $x end; {system:n($system),motherboard:n($board),bios:n($bios)}'
}

parse_pci() {
    local file=$1
    [[ -s "$file" ]] || { printf '[]'; return; }
    awk '
      /^[0-9a-fA-F]+:/ {if(seen) print rec; rec=$0; seen=1; next}
      seen && /^[ \t]+Kernel driver in use:/ {sub(/^[ \t]+Kernel driver in use:[ \t]*/,""); driver=$0; rec=rec "\t" driver; next}
      seen && /^[ \t]+Kernel modules:/ {sub(/^[ \t]+Kernel modules:[ \t]*/,""); rec=rec "\t" $0}
      END{if(seen) print rec}' "$file" | while IFS=$'\t' read -r line driver modules; do
        address=${line%% *}; desc=${line#* }; class=${desc%%:*}; ids=$(printf '%s' "$desc" | sed -n 's/.*\[\([0-9A-Fa-f]\{4\}\):\([0-9A-Fa-f]\{4\}\)\].*/\1 \2/p')
        vendor_id=${ids%% *}; device_id=${ids#* }; [[ "$device_id" == "$ids" ]] && device_id=
        jq -nc --arg address "$address" --arg class "$class" --arg description "$desc" --arg vendor "$vendor_id" --arg device "$device_id" --arg driver "$driver" --arg modules "$modules" 'def n($x):if $x=="" then null else $x end; {address:$address,class:$class,description:$description,vendor_id:n($vendor),device_id:n($device),driver:n($driver),modules:($modules|split(", ")|map(select(length>0)))}'
    done | jq -s .
}

parse_storage() {
    local file=$1
    [[ -s "$file" ]] || { printf '[]'; return; }
    if ! jq empty "$file" >/dev/null 2>&1; then printf '[]'; return; fi
    jq '[.blockdevices[]? | select(.type=="disk") | {device:("/dev/"+.name),type,capacity_bytes:(.size // null),manufacturer:(.vendor // null),model:(.model // null),serial:(.serial // null),firmware:(.rev // null),transport:(.tran // null),interface:(.subsystems // null),rotational:(if has("rota") then .rota else null end),smart:{capable:null,status:null},nvme:(if .tran=="nvme" then {} else null end),filesystems:[recurse(.children[]?) | select(.fstype != null) | {device:("/dev/"+.name),filesystem:.fstype,label:(.label // null),uuid:(.uuid // null),mountpoint:(.mountpoint // null)}]}]' "$file"
}

parse_usb() {
    local file=$1
    [[ -s "$file" ]] || { printf '[]'; return; }
    sed -n 's/^Bus \([0-9]*\) Device \([0-9]*\): ID \([0-9A-Fa-f]*\):\([0-9A-Fa-f]*\) \(.*\)$/\1\t\2\t\3\t\4\t\5/p' "$file" | while IFS=$'\t' read -r bus device vendor product description; do
      jq -nc --arg bus "$bus" --arg device "$device" --arg vendor "$vendor" --arg product "$product" --arg description "$description" '{bus:$bus,device:$device,vendor_id:$vendor,product_id:$product,description:$description,topology:null}'
    done | jq -s .
}

parse_network() {
    local file=$1
    [[ -s "$file" ]] || { printf '[]'; return; }
    jq 'if type=="array" then [.[] | {interface:.ifname,mac_address:(.address // null),state:(.operstate // null),mtu:(.mtu // null),controller:null,bus_identity:null,driver:null,link_capability:null}] else [] end' "$file" 2>/dev/null || printf '[]'
}

enrich_network() {
    local network=$1 interface base bus driver product speed modes info item result='[]'
    while IFS= read -r interface; do
        base="/sys/class/net/$interface"
        bus=""; driver=""; product=""; speed=""; modes=""
        if [[ -e "$base/device" ]]; then
            bus=$(basename "$(readlink -f "$base/device")")
            [[ -L "$base/device/driver" ]] && driver=$(basename "$(readlink -f "$base/device/driver")")
            [[ -r "$base/device/uevent" ]] && product=$(sed -n 's/^PRODUCT=//p' "$base/device/uevent" | head -n1)
        fi
        if [[ -z "${PROBE_FIXTURE_DIR:-}" ]] && have ethtool; then
            info=$(timeout "${PROBE_COMMAND_TIMEOUT:-20}" ethtool "$interface" 2>/dev/null || true)
            speed=$(sed -n 's/^[[:space:]]*Speed:[[:space:]]*//p' <<<"$info" | head -n1)
            modes=$(sed -n 's/^[[:space:]]*Supported link modes:[[:space:]]*//p' <<<"$info" | head -n1)
        fi
        item=$(jq -n --argjson all "$network" --arg interface "$interface" --arg bus "$bus" --arg driver "$driver" --arg product "$product" --arg speed "$speed" --arg modes "$modes" 'def n($x):if $x=="" then null else $x end; ($all[]|select(.interface==$interface)) | .bus_identity=n($bus) | .driver=n($driver) | .controller=(if $product=="" then null else "USB "+$product end) | .link_capability={speed:n($speed),supported_modes:n($modes)}')
        result=$(jq -n --argjson old "$result" --argjson item "$item" '$old+[$item]')
    done < <(jq -r '.[].interface' <<<"$network")
    printf '%s\n' "$result"
}

enrich_graphics() {
    local graphics=$1 path name status modes driver entry result
    result=$graphics
    [[ -n "${PROBE_FIXTURE_DIR:-}" ]] && { printf '%s\n' "$result"; return; }
    for path in /sys/class/drm/card*; do
        [[ -e "$path" ]] || continue
        name=$(basename "$path"); status=""; modes=""; driver=""
        [[ -r "$path/status" ]] && status=$(cat "$path/status")
        [[ -r "$path/modes" ]] && modes=$(paste -sd, "$path/modes")
        [[ -L "$path/device/driver" ]] && driver=$(basename "$(readlink -f "$path/device/driver")")
        entry=$(jq -n --arg name "$name" --arg status "$status" --arg modes "$modes" --arg driver "$driver" 'def n($x):if $x=="" then null else $x end; {source:"drm",device:$name,status:n($status),modes:($modes|split(",")|map(select(length>0))),driver:n($driver),pci_id:null}')
        result=$(jq -n --argjson old "$result" --argjson entry "$entry" '$old+[$entry]')
    done
    printf '%s\n' "$result"
}

enrich_storage() {
    local storage=$1 nvme_file=$2 device base fixture info result
    result=$storage
    while IFS= read -r device; do
        [[ -n "$device" ]] || continue
        base=${device##*/}
        fixture=$(fixture_path "smartctl.$base.json")
        info=""
        if [[ -n "$fixture" ]]; then info=$(cat "$fixture");
        elif [[ -z "${PROBE_FIXTURE_DIR:-}" ]] && have smartctl; then info=$(timeout "${PROBE_COMMAND_TIMEOUT:-20}" smartctl -j --info --health "$device" 2>/dev/null || true); fi
        if [[ -n "$info" ]] && jq empty >/dev/null 2>&1 <<<"$info"; then
            result=$(jq -n --argjson disks "$result" --arg device "$device" --argjson smart "$info" '$disks | map(if .device==$device then .smart={capable:($smart.smart_support.available // null),enabled:($smart.smart_support.enabled // null),status:($smart.smart_status.passed // null)} | .firmware=(.firmware // $smart.firmware_version // null) | .serial=(.serial // $smart.serial_number // null) | .model=(.model // $smart.model_name // null) else . end)')
        fi
    done < <(jq -r '.[].device' <<<"$storage")
    if [[ -s "$nvme_file" ]] && jq empty "$nvme_file" >/dev/null 2>&1; then
        result=$(jq -n --argjson disks "$result" --slurpfile nvme "$nvme_file" '$nvme[0] as $n | $disks | map(. as $d | ($n.Devices // $n.devices // [] | map(select((.DevicePath // .device // "")==$d.device)) | first) as $x | if $x then .nvme=$x else . end)')
    fi
    printf '%s\n' "$result"
}

parse_memory() {
    local file=$1 total meminfo
    meminfo=$(fixture_path meminfo)
    [[ -n "$meminfo" ]] || meminfo=/proc/meminfo
    total=$(awk '/^MemTotal:/{print $2*1024}' "$meminfo" 2>/dev/null || true)
    [[ -s "$file" ]] || { jq -n --arg total "$total" '{total_usable_bytes:($total|tonumber?),slots:{total:null,populated:null,empty:null},dimms:[]}'; return; }
    awk '
      /^[[:space:]]*Memory Device$/ {if(in_dev) print rec; in_dev=1; rec=""; next}
      in_dev && /^[^[:space:]]/ {print rec; in_dev=0}
      in_dev && /^[[:space:]]*(Size|Locator|Bank Locator|Type|Speed|Configured Memory Speed|Manufacturer|Serial Number|Part Number):/ {x=$0; sub(/^[[:space:]]*/,"",x); rec=rec (rec?"\t":"") x}
      END{if(in_dev) print rec}' "$file" | while IFS= read -r rec; do
        jq -nc --arg rec "$rec" 'reduce ($rec|split("\t")[]) as $x ({}; ($x|index(":")) as $p | . + {($x[0:$p]):($x[$p+1:]|sub("^ +";"")|sub(" +$";""))}) | {locator:(.Locator // null),bank_locator:(.["Bank Locator"] // null),capacity:(.Size // null),type:(.Type // null),configured_speed:(.["Configured Memory Speed"] // null),rated_speed:(.Speed // null),manufacturer:(.Manufacturer // null),serial_number:(.["Serial Number"] // null),part_number:(.["Part Number"] // null),populated:((.Size // "") != "No Module Installed")}'
    done | jq -s --arg total "$total" '{total_usable_bytes:($total|tonumber?),slots:{total:length,populated:(map(select(.populated))|length),empty:(map(select(.populated|not))|length)},dimms:map(select(.populated))}'
}

extract_msdm_key() {
    local file=${1:-}
    [[ -n "$file" && -r "$file" ]] || return 0
    LC_ALL=C strings "$file" 2>/dev/null | grep -Eio '[A-Z0-9]{5}(-[A-Z0-9]{5}){4}' | head -n1 || true
}
mask_key() { [[ "$1" =~ ^.{5}-.{5}-.{5}-.{5}-(.{5})$ ]] && printf '*****-*****-*****-*****-%s' "${BASH_REMATCH[1]}"; }
firmware_license_json() {
    local file=${1:-} key=${2:-} exists=false found=false masked=""
    [[ -n "$file" && -e "$file" ]] && exists=true
    if [[ -n "$key" ]]; then found=true; masked=$(mask_key "$key"); fi
    jq -n --argjson exists "$exists" --argjson found "$found" --arg masked "$masked" '{msdm_present:$exists,oem_key_found:$found,source:(if $exists then "firmware_msdm" else null end),key_type:(if $found then "OEM_DM" else null end),confidence:(if $found then "high" else null end),reusable_hint:(if $found then "May be useful when reinstalling the matching Windows edition; activation is not guaranteed." else null end),key_masked:(if $masked=="" then null else $masked end),key_disclosure:"Use an explicit local reveal or sensitive export; normal reports never contain the complete key."}'
}

sanitize_windows_installations() {
    jq 'map(. as $item | ($item.recoverable_product_key // null) as $key |
      . + {recoverable_key_status:(if $key then "found" else (.recoverable_key_status // "not_established") end),
           recovered_key:{source:(.recovered_key.source // (if $key then "offline_registry" else null end)),
             key_type:(.recovered_key.key_type // .key_type // null),confidence:(.recovered_key.confidence // .confidence // null),
             reusable_hint:(.recovered_key.reusable_hint // .reusable_hint // null),edition_hint:(.recovered_key.edition_hint // .edition // null)}} |
      del(.recoverable_product_key,.key,.key_type,.confidence,.reusable_hint) |
      .activation_status=(.activation_status // "cannot be reliably determined offline"))'
}

discover_windows() {
    local _tmp=$1 allow_mount=$2 fixture fixture_json
    fixture=$(fixture_path windows_installations.json)
    if [[ -n "$fixture" ]]; then
        fixture_json=$(jq -c 'if type=="array" then . else [] end' "$fixture" 2>/dev/null) || { printf '[]'; return; }
        if [[ -n "${SENSITIVE_KEYS_FILE:-}" ]]; then
            jq -c '.[] | select(.recoverable_product_key) | {source:"offline_registry",key:.recoverable_product_key,key_type:(.key_type // .recovered_key.key_type // "unknown"),confidence:(.confidence // .recovered_key.confidence // "low"),reusable_hint:(.reusable_hint // .recovered_key.reusable_hint // "possible_not_guaranteed"),edition_hint:(.edition // .product_name // null),installation:(.device // null)}' <<< "$fixture_json" >> "$SENSITIVE_KEYS_FILE" 2>/dev/null || true
        fi
        sanitize_windows_installations <<< "$fixture_json"; return
    fi
    [[ -n "${PROBE_FIXTURE_DIR:-}" || "$allow_mount" != 1 ]] && { printf '[]'; return; }
    # Candidate discovery is conservative. Only currently mounted filesystems and
    # successful read-only mounts are inspected; every mount is cleaned by trap.
    local dev fstype mountpoint candidate hive name edition version build product_id arch channel metadata recovered helper
    helper=${PROBE_WINDOWS_HELPER:-$SELF_DIR/../lib/windows-license.py}
    while IFS=$'\t' read -r dev fstype mountpoint; do
        [[ "$fstype" =~ ^(ntfs|ntfs3|vfat|exfat)$ ]] || continue
        candidate="$mountpoint"
        if [[ -z "$candidate" || "$candidate" == null ]]; then
            candidate=$(mktemp -d "${TMPDIR:-/tmp}/probe-win.XXXXXX") || continue
            if timeout "${PROBE_COMMAND_TIMEOUT:-20}" mount -o ro,nosuid,nodev,noexec "$dev" "$candidate" 2>/dev/null; then MOUNTS="$candidate $MOUNTS"; else rmdir "$candidate"; continue; fi
        fi
        [[ -d "$candidate/Windows/System32/config" ]] || continue
        hive="$candidate/Windows/System32/config/SOFTWARE"
        name=""; edition=""; version=""; build=""; product_id=""; arch=""; channel=""; recovered=null
        if [[ -d "$candidate/Windows/SysWOW64" ]]; then arch=x86_64; else arch=x86; fi
        if have hivexregedit && [[ -r "$hive" ]]; then
            metadata=$(hivexregedit --export "$hive" 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 2>/dev/null || true)
            name=$(printf '%s\n' "$metadata" | sed -n 's/^"ProductName"="\(.*\)"/\1/p' | head -n1)
            version=$(printf '%s\n' "$metadata" | sed -n 's/^"DisplayVersion"="\(.*\)"/\1/p' | head -n1)
            build=$(printf '%s\n' "$metadata" | sed -n 's/^"CurrentBuild"="\(.*\)"/\1/p' | head -n1)
            product_id=$(printf '%s\n' "$metadata" | sed -n 's/^"ProductId"="\(.*\)"/\1/p' | head -n1)
            edition=$(printf '%s\n' "$metadata" | sed -n 's/^"EditionID"="\(.*\)"/\1/p' | head -n1)
            if [[ -x "$helper" ]]; then recovered=$(printf '%s\n' "$metadata" | "$helper" --registry-export --channel "$channel" 2>/dev/null || printf null); fi
        fi
        if [[ "$recovered" != null && -n "${SENSITIVE_KEYS_FILE:-}" ]]; then
            jq -nc --argjson value "$recovered" --arg edition "$name" --arg device "$dev" '$value + {source:"offline_registry",edition_hint:(if $edition=="" then null else $edition end),installation:$device}' >> "$SENSITIVE_KEYS_FILE"
        fi
        jq -nc --arg device "$dev" --arg fs "$fstype" --arg name "$name" --arg edition "$edition" --arg version "$version" --arg build "$build" --arg pid "$product_id" --arg arch "$arch" --arg channel "$channel" --argjson recovered "$recovered" 'def n($x):if $x=="" then null else $x end; {device:$device,filesystem:$fs,product_name:n($name),edition:n($edition),architecture:n($arch),version:n($version),build:n($build),product_id:n($pid),license_channel:n($channel),registry_metadata_read:($name!="" or $build!=""),recoverable_product_key:($recovered.key // null),recovered_key:(if $recovered then ($recovered|del(.key)|.source="offline_registry") else null end),activation_status:"cannot be reliably determined offline",firmware_key_relationship:"cannot be reliably determined offline"}'
    done < <(lsblk -rno PATH,FSTYPE,MOUNTPOINT 2>/dev/null) | jq -s . | sanitize_windows_installations
}

parse_sensors() {
    local file=$1
    if [[ -s "$file" ]] && jq empty "$file" >/dev/null 2>&1; then jq '{status:"available",readings:.}' "$file"; else jq -n '{status:"unavailable",readings:null}'; fi
}
parse_power() {
    local base entries='[]' fixture
    fixture=$(fixture_path power.json)
    if [[ -n "$fixture" ]]; then jq 'if type=="object" then . else {supplies:[]} end' "$fixture" 2>/dev/null || printf '{"supplies":[]}' ; return; fi
    for base in /sys/class/power_supply/*; do
        [[ -d "$base" ]] || continue
        entries=$(jq -n --argjson old "$entries" --arg name "$(basename "$base")" --arg type "$(cat "$base/type" 2>/dev/null)" --arg status "$(cat "$base/status" 2>/dev/null)" --arg capacity "$(cat "$base/capacity" 2>/dev/null)" --arg manufacturer "$(cat "$base/manufacturer" 2>/dev/null)" --arg model "$(cat "$base/model_name" 2>/dev/null)" --arg serial "$(cat "$base/serial_number" 2>/dev/null)" --arg design "$(cat "$base/energy_full_design" 2>/dev/null)" --arg full "$(cat "$base/energy_full" 2>/dev/null)" --arg cycles "$(cat "$base/cycle_count" 2>/dev/null)" 'def n($x):if $x=="" then null else $x end; $old + [{name:$name,type:n($type),status:n($status),capacity_percent:($capacity|tonumber?),manufacturer:n($manufacturer),model:n($model),serial_number:n($serial),design_capacity:($design|tonumber?),full_charge_capacity:($full|tonumber?),cycle_count:($cycles|tonumber?)}]')
    done
    jq -n --argjson supplies "$entries" '{supplies:$supplies}'
}

render_text() {
    jq -r '
      "ProbeOS Hardware Identification Report\nGenerated: \(.probeos.generated_at)\nSchema: \(.schema_version)\n",
      "SYSTEM\n  Manufacturer: \(.system.manufacturer // "Unknown")\n  Product: \(.system.product // "Unknown")\n  Serial: \(.system.serial_number // "Unknown")\n  UUID: \(.system.uuid // "Unknown")\n",
      "CPU\n" + (if (.cpu|length)>0 then (.cpu[] | "  \(.model // "Unknown")\n  Architecture: \(.architecture // "Unknown"), cores: \(.cores // "Unknown"), threads: \(.threads // "Unknown")\n  Virtualization: \(.virtualization // "Unknown")") else "  Unknown" end) + "\n",
      "MEMORY\n  Usable bytes: \(.memory.total_usable_bytes // "Unknown")\n  Slots: \(.memory.slots.populated // "Unknown") populated / \(.memory.slots.total // "Unknown") total\n",
      "MOTHERBOARD / FIRMWARE\n  Board: \(.motherboard.vendor // "Unknown") \(.motherboard.model // "Unknown")\n  Firmware: \(.firmware.vendor // "Unknown") \(.firmware.version // "Unknown")\n  Boot mode: \(.firmware.boot_mode), Secure Boot: \(.firmware.secure_boot)\n",
      "DEVICES\n  PCI: \(.pci|length), USB: \(.usb|length), graphics: \(.graphics|length), storage: \(.storage|length), network: \(.network|length)\n",
      "WINDOWS\n  Firmware Windows OEM key: \(if .windows.firmware_license.oem_key_found then "Found" else "Not found" end)\n  MSDM present: \(.windows.firmware_license.msdm_present)\n  Source: \(.windows.firmware_license.source // "None")\n  Key: \(.windows.firmware_license.key_masked // "Not available")\n  Installations discovered: \(.windows.installations|length)\n  Activation status is not claimed from offline metadata.\n",
      "PRIVACY\n  This report may contain serial numbers, UUIDs, and MAC addresses. The complete Windows key is excluded."
    ' "$1"
}
