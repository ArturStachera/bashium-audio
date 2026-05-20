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

has_nonfree_enabled(){
    if grep -Rqs -- 'non-free' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        return 0
    fi
    return 1
}

ensure_non_free_components(){
    local changed=false

    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        if ! sudo grep -q "^[[:space:]]*Components:.*non-free" /etc/apt/sources.list.d/debian.sources; then
            sudo sed -i -E 's/^(Components:[[:space:]]*)(.*)$/\1\2 contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
            changed=true
        fi
    fi

    if [[ -f /etc/apt/sources.list ]]; then
        if sudo grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]]main([[:space:]]|$)' /etc/apt/sources.list; then
            if ! sudo grep -Eq '^[[:space:]]*deb[[:space:]].*[[:space:]](main.*non-free|main.*non-free-firmware|main.*contrib)' /etc/apt/sources.list; then
                sudo sed -i -E 's/^(deb[[:space:]].*[[:space:]]main)([[:space:]]*)$/\1 contrib non-free non-free-firmware\2/' /etc/apt/sources.list
                changed=true
            fi
        fi
    fi

    if [[ $changed == true ]]; then
        sudo apt-get update
    fi
}

detect_wifi_vendors(){
    local hw
    hw=$( (command -v lspci >/dev/null 2>&1 && lspci -nn) 2>/dev/null; (command -v lsusb >/dev/null 2>&1 && lsusb) 2>/dev/null )

    wifi_intel=false
    wifi_broadcom=false
    wifi_realtek=false
    wifi_atheros=false
    wifi_mediatek=false
    wifi_ralink=false

    # Exclude Ethernet controllers - they also appear as "Network controller"
    # Filter out lines containing Ethernet before checking for wireless
    local filtered_hw
    filtered_hw=$(echo "$hw" | grep -Eiv 'Ethernet|Gigabit|10-Gigabit|1000Base')

    if echo "$filtered_hw" | grep -Eqi 'Network controller.*Wireless|Network controller.*802\.11|Wireless|Wi-Fi|802\.11'; then
        if echo "$filtered_hw" | grep -Eqi 'Intel|8086:'; then wifi_intel=true; fi
        if echo "$filtered_hw" | grep -Eqi 'Broadcom|BCM|14e4:'; then wifi_broadcom=true; fi
        if echo "$filtered_hw" | grep -Eqi 'Realtek|RTL|10ec:|0bda:'; then wifi_realtek=true; fi
        if echo "$filtered_hw" | grep -Eqi 'Atheros|Qualcomm|168c:|0cf3:'; then wifi_atheros=true; fi
        if echo "$filtered_hw" | grep -Eqi 'MediaTek|Mediatek|MTK|14c3:|0e8d:'; then wifi_mediatek=true; fi
        if echo "$filtered_hw" | grep -Eqi 'Ralink|148f:'; then wifi_ralink=true; fi
    fi
}

has_nvidia_gpu(){
    if command -v lspci >/dev/null 2>&1; then
        lspci -nn | grep -qi nvidia
        return $?
    fi
    return 1
}

echo "Detecting Wi-Fi hardware..."

detect_wifi_vendors

# Check if any Wi-Fi vendor was detected
no_wifi=false
if [[ $wifi_intel == false && $wifi_broadcom == false && $wifi_realtek == false && $wifi_atheros == false && $wifi_mediatek == false && $wifi_ralink == false ]]; then
    echo "No Wi-Fi hardware detected. Skipping vendor-specific firmware."
    no_wifi=true
fi

if [[ $no_wifi == false ]]; then

echo ""
echo "Detected Wi-Fi hardware. Select which firmware to install:"
echo ""

if [[ $wifi_intel == true ]]; then
    if ask_question "Install Intel Wi-Fi firmware (firmware-iwlwifi)?"; then
        intel=true
    fi
fi

if [[ $wifi_broadcom == true ]]; then
    if ask_question "Install Broadcom Wi-Fi firmware (firmware-brcm80211)?"; then
        broadcom=true
    fi
fi

if [[ $wifi_realtek == true ]]; then
    if ask_question "Install Realtek Wi-Fi firmware (firmware-realtek)?"; then
        realtek=true
    fi
fi

if [[ $wifi_atheros == true ]]; then
    if ask_question "Install Atheros/Qualcomm Wi-Fi firmware (firmware-atheros)?"; then
        atheros=true
    fi
fi

if [[ $wifi_mediatek == true ]]; then
    if ask_question "Install MediaTek Wi-Fi firmware (firmware-mediatek)?"; then
        mediatek=true
    fi
fi

if [[ $wifi_ralink == true ]]; then
    if ask_question "Install Ralink Wi-Fi firmware (firmware-ralink)?"; then
        ralink=true
    fi
fi

fi # end of no_wifi == false

read -rsn1 -p "Press Enter to continue..."
echo ""

# Install the appropriate firmware packages based on the responses
if [[ ${intel:-} == true ]]; then
    echo "Installing INTEL WiFi driver..."
    sudo apt install firmware-iwlwifi -y
fi

if [[ ${broadcom:-} == true ]]; then
    echo "Installing Broadcom WiFi driver..."
    sudo apt install firmware-brcm80211 -y
fi

if [[ ${realtek:-} == true ]]; then
    echo "Installing Realtek driver..."
    sudo apt install firmware-realtek -y
fi

if [[ ${atheros:-} == true ]]; then
    echo "Installing Atheros/Qualcomm WiFi firmware..."
    sudo apt install firmware-atheros -y
fi

if [[ ${mediatek:-} == true ]]; then
    echo "Installing MediaTek WiFi firmware..."
    sudo apt install firmware-mediatek -y
fi

if [[ ${ralink:-} == true ]]; then
    echo "Installing Ralink WiFi firmware..."
    sudo apt install firmware-ralink -y
fi

echo "Wi-Fi firmware installation complete."