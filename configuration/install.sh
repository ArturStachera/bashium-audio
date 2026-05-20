#!/bin/bash

# Function to display a question and wait for the user's response
ask_question(){
    local answer
    printf "\e[33m%s\e[0m (y/n): " "$1"
    while true; do
        read -rsn1 answer
        if [[ $answer =~ ^[yYnN]$ ]]; then
            printf "%s " "$answer" # print the answer without a newline
            break
        fi
    done
    echo "" # move to a newline
    if [[ $answer == [yY] ]]; then
        return 0
    else
        return 1
    fi
}

print_header(){
    echo ""
    echo "+----------------------------------------------------------+"
    echo "|                       BASHIUM CONFIG                     |"
    echo "+----------------------------------------------------------+"
}

print_status_table(){
    local wifi_status="$1"
    local bt_status="$2"
    local nvidia_status="$3"
    local nonfree_status="$4"
    local beep_status="$5"
    local sbin_status="$6"

    cat <<EOF
+----------------------+-------------------------------+
| Component            | Status                        |
+----------------------+-------------------------------+
| Wi-Fi                | ${wifi_status}
| Bluetooth            | ${bt_status}
| NVIDIA GPU           | ${nvidia_status}
| APT non-free         | ${nonfree_status}
| PC speaker beep      | ${beep_status}
| /sbin in user PATH   | ${sbin_status}
+----------------------+-------------------------------+
EOF
}

has_nonfree_enabled(){
    if grep -Rqs -- 'non-free' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        return 0
    fi
    return 1
}

is_beep_disabled(){
    if grep -Rqs -- '^[[:space:]]*blacklist[[:space:]]\+pcspkr[[:space:]]*$' /etc/modprobe.d 2>/dev/null; then
        return 0
    fi
    if grep -q '^[[:space:]]*blacklist[[:space:]]\+pcspkr[[:space:]]*$' /etc/modprobe.d/blacklist.conf 2>/dev/null; then
        return 0
    fi
    return 1
}

user_has_sbin_in_bashrc(){
    local username="$1"
    if [[ -z $username ]]; then
        return 2
    fi
    if ! id "$username" &>/dev/null; then
        return 2
    fi
    local user_home
    user_home=$(eval echo ~"$username" 2>/dev/null)
    if [[ -z $user_home ]]; then
        return 2
    fi
    local bashrc_file="$user_home/.bashrc"
    if [[ -f $bashrc_file ]] && grep -Fxq 'export PATH=$PATH:/sbin' "$bashrc_file"; then
        return 0
    fi
    return 1
}

has_bluetooth(){
    if command -v rfkill >/dev/null 2>&1; then
        if rfkill list 2>/dev/null | grep -qi bluetooth; then
            return 0
        fi
    fi

    if command -v lspci >/dev/null 2>&1; then
        if lspci 2>/dev/null | grep -qi bluetooth; then
            return 0
        fi
    fi

    if command -v lsusb >/dev/null 2>&1; then
        if lsusb 2>/dev/null | grep -qi bluetooth; then
            return 0
        fi
    fi

    if [[ -d /sys/class/bluetooth ]]; then
        if ls /sys/class/bluetooth 2>/dev/null | grep -q '^hci'; then
            return 0
        fi
    fi

    return 1
}

has_nvidia_gpu(){
    if command -v lspci >/dev/null 2>&1; then
        lspci -nn 2>/dev/null | grep -qi nvidia
        return $?
    fi
    return 1
}

has_wifi(){
    local hw
    hw=$( (command -v lspci >/dev/null 2>&1 && lspci -nn) 2>/dev/null; (command -v lsusb >/dev/null 2>&1 && lsusb) 2>/dev/null )
    # Look for wireless devices but exclude Ethernet/wired controllers
    echo "$hw" | grep -Eqi 'Network controller.*Wireless|Network controller.*802\.11|Wireless|Wi-Fi|802\.11' && \
        ! echo "$hw" | grep -Eqi 'Ethernet|Gigabit|10-Gigabit|1000Base'
}

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 1: Detection & Status
# ══════════════════════════════════════════════════════════════════════════════

print_header

wifi_status="not detected"
bt_status="not detected"
nvidia_status="not detected"
nonfree_status="not enabled"
beep_status="enabled"
sbin_status="unknown (no user selected)"

if has_wifi; then wifi_status="detected"; fi
if has_bluetooth; then bt_status="detected"; fi
if has_nvidia_gpu; then nvidia_status="detected"; fi
if has_nonfree_enabled; then nonfree_status="enabled"; fi
if is_beep_disabled; then beep_status="disabled"; fi

read -r -p "Enter username for user-level checks (optional, press Enter to skip): " username
if [[ -n $username ]]; then
    user_has_sbin_in_bashrc "$username"
    rc=$?
    if [[ $rc -eq 0 ]]; then
        sbin_status="already configured"
    elif [[ $rc -eq 1 ]]; then
        sbin_status="not configured"
    else
        sbin_status="unknown (invalid user)"
    fi
fi

print_status_table "$wifi_status" "$bt_status" "$nvidia_status" "$nonfree_status" "$beep_status" "$sbin_status"
echo ""
echo "Select what you want to configure. All selected tasks will run after you make your choices."
echo ""

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 2: Collect all user choices (no execution yet)
# ══════════════════════════════════════════════════════════════════════════════

do_sbin=false
do_beep=false
do_bluetooth=false
do_nvidia=false
do_firmware=false
do_nonfree_fw=false

# --- /sbin PATH ---
echo "--- /sbin PATH ---"
if [[ -n $username ]]; then
    if [[ $sbin_status == "not configured" ]]; then
        if ask_question "Configure /sbin PATH entry for '$username'?"; then
            do_sbin=true
        fi
    elif [[ $sbin_status == "already configured" ]]; then
        if ask_question "/sbin PATH already configured for '$username'. Run anyway?"; then
            do_sbin=true
        fi
    else
        if ask_question "Configure /sbin PATH entry (will ask for username)?"; then
            do_sbin=true
        fi
    fi
else
    if ask_question "Configure /sbin PATH entry (will ask for username)?"; then
        do_sbin=true
    fi
fi

# --- PC Speaker Beep ---
echo ""
echo "--- PC Speaker Beep ---"
if is_beep_disabled; then
    if ask_question "PC speaker beep is already disabled. Run beep disable step anyway?"; then
        do_beep=true
    fi
else
    if ask_question "Disable the PC speaker beep sound?"; then
        do_beep=true
    fi
fi

# --- Bluetooth ---
echo ""
echo "--- Bluetooth ---"
if has_bluetooth; then
    if ask_question "Bluetooth controller detected. Configure Bluetooth?"; then
        do_bluetooth=true
    fi
else
    echo "No Bluetooth controller detected. Skipping."
fi

# --- NVIDIA GPU ---
echo ""
echo "--- NVIDIA GPU ---"
if has_nvidia_gpu; then
    if ask_question "NVIDIA GPU detected. Configure proprietary NVIDIA driver?"; then
        do_nvidia=true
    fi
else
    echo "No NVIDIA GPU detected. Skipping."
fi

# --- Wi-Fi Firmware ---
echo ""
echo "--- Wi-Fi Firmware ---"
if has_wifi; then
    if ask_question "Wi-Fi hardware detected. Install drivers/firmware?"; then
        do_firmware=true
    fi
else
    echo "No Wi-Fi hardware detected. Skipping."
fi

# --- Non-free Firmware ---
echo ""
echo "--- Non-free Firmware ---"
echo "(firmware-misc-nonfree, firmware-linux-nonfree, amd64-microcode)"
echo "Recommended for most hardware (GPU, network, sensors, etc.)."
if has_nonfree_enabled; then
    if ask_question "Non-free repos already enabled. Install non-free firmware bundle?"; then
        do_nonfree_fw=true
    fi
else
    if ask_question "Enable non-free repos and install non-free firmware bundle?"; then
        do_nonfree_fw=true
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
#  PHASE 3: Summary & Execution
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "+----------------------------------------------------------+"
echo "|                  SELECTED TASKS SUMMARY                  |"
echo "+----------------------------------------------------------+"

selected=0
if [[ $do_sbin == true ]];      then echo "  [✓] /sbin PATH configuration";  ((selected++)); else echo "  [ ] /sbin PATH configuration"; fi
if [[ $do_beep == true ]];      then echo "  [✓] Disable PC speaker beep";   ((selected++)); else echo "  [ ] Disable PC speaker beep"; fi
if [[ $do_bluetooth == true ]]; then echo "  [✓] Bluetooth configuration";   ((selected++)); else echo "  [ ] Bluetooth configuration"; fi
if [[ $do_nvidia == true ]];    then echo "  [✓] NVIDIA driver setup";       ((selected++)); else echo "  [ ] NVIDIA driver setup"; fi
if [[ $do_firmware == true ]];  then echo "  [✓] Wi-Fi firmware";            ((selected++)); else echo "  [ ] Wi-Fi firmware"; fi
if [[ $do_nonfree_fw == true ]];then echo "  [✓] Non-free firmware bundle";  ((selected++)); else echo "  [ ] Non-free firmware bundle"; fi

echo "+----------------------------------------------------------+"
echo ""

if [[ $selected -eq 0 ]]; then
    echo "No tasks selected. Nothing to do."
    exit 0
fi

if ! ask_question "Proceed with $selected selected task(s)?"; then
    echo "Cancelled."
    exit 0
fi

# Clear terminal before execution — clean output from here on
clear

echo "+----------------------------------------------------------+"
echo "|                    EXECUTING TASKS                       |"
echo "+----------------------------------------------------------+"
echo ""

# --- Non-free firmware (run first — other scripts may depend on non-free repos) ---
if [[ $do_nonfree_fw == true ]]; then
    echo "=== Installing Non-free Firmware ==="
    if ! has_nonfree_enabled; then
        if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
            if ! grep -Eq "^[[:space:]]*Components:.*non-free" /etc/apt/sources.list.d/debian.sources; then
                sudo sed -i -E 's/^(Components:[[:space:]]*)(.*)$/\1\2 contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
            fi
        fi
        if [[ -f /etc/apt/sources.list ]]; then
            if grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)' /etc/apt/sources.list; then
                if ! grep -Eq '^[[:space:]]*deb[[:space:]].*main.*non-free' /etc/apt/sources.list; then
                    sudo sed -i -E '/^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)/ s/$/ contrib non-free non-free-firmware/' /etc/apt/sources.list
                fi
            fi
        fi
        sudo apt-get update
    fi
    sudo apt-get install -y firmware-misc-nonfree firmware-linux-nonfree amd64-microcode
    echo ""
fi

# --- /sbin PATH ---
if [[ $do_sbin == true ]]; then
    echo "=== Configuring /sbin PATH ==="
    if [[ -n ${username:-} ]]; then
        ./sbin.sh "$username"
    else
        ./sbin.sh
    fi
    echo ""
fi

# --- Beep ---
if [[ $do_beep == true ]]; then
    echo "=== Disabling PC Speaker Beep ==="
    ./beep.sh
    echo ""
fi

# --- Bluetooth ---
if [[ $do_bluetooth == true ]]; then
    echo "=== Configuring Bluetooth ==="
    ./bluetooth.sh
    echo ""
fi

# --- Wi-Fi Firmware ---
if [[ $do_firmware == true ]]; then
    echo "=== Installing Wi-Fi Firmware ==="
    ./firmware.sh
    echo ""
fi

# --- NVIDIA ---
if [[ $do_nvidia == true ]]; then
    echo "=== Configuring NVIDIA Driver ==="
    ./nvidia.sh --yes
    echo ""
fi

echo "+----------------------------------------------------------+"
echo "|                    ALL TASKS COMPLETE                    |"
echo "+----------------------------------------------------------+"
echo ""
echo "Please restart your computer for changes to take effect."
