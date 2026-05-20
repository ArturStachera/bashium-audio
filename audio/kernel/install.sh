#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|               KERNEL PARAMETERS SETUP                    |
|              threadirqs + USB Autosuspend                |
+----------------------------------------------------------+
EOF
echo ""

GRUB_FILE="/etc/default/grub"

echo "[1/3] Checking current GRUB parameters..."
CURRENT=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_FILE" 2>/dev/null || echo "NOT FOUND")
echo "Current value:"
echo "  $CURRENT"
echo ""

# Check for Pascal + Kernel 7.0 conflict
detect_gpu_arch(){
    if command -v lspci >/dev/null 2>&1; then
        local pci_ids=$(lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -ioP '10de:([0-9a-f]{4})' | cut -d: -f2 | head -n1 | tr '[:upper:]' '[:lower:]')
        if [[ -n $pci_ids ]]; then
            local id_int=$((16#$pci_ids))
            if (( id_int >= 0x1B00 && id_int <= 0x1D80 )) || (( id_int >= 0x15F0 && id_int <= 0x15FF )); then
                echo "pascal"
                return
            fi
        fi
    fi
    echo "unknown"
}

get_kernel_major(){
    uname -r | grep -oP '^[0-9]+' | head -n1
}

ARCH=$(detect_gpu_arch)
KMAJ=$(get_kernel_major)

if [[ "$ARCH" == "pascal" ]] && (( KMAJ >= 7 )); then
    echo "!!! PASCAL GPU + KERNEL 7.0 DETECTED !!!"
    echo "This combination is known to have issues with NVIDIA drivers."
    echo ""
    read -p "Would you like to install Kernel 6.12 (LTS) for compatibility? (y/n): " answer
    if [[ $answer =~ ^[yY]$ ]]; then
        echo "Installing Kernel 6.12..."
        # Add stable repo if needed (assuming trixie as stable)
        if ! grep -qs "trixie" /etc/apt/sources.list /etc/apt/sources.list.d/*.list; then
             echo "deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list.d/debian-stable.list > /dev/null
             sudo apt update
        fi
        sudo apt install -y linux-image-6.12-amd64 linux-headers-6.12-amd64
        echo "Kernel 6.12 installed. Please reboot and select it in GRUB."
    fi
fi

echo ""
echo "[2/3] Adding kernel parameters..."
# Check if parameters already exist
if grep -q "threadirqs" "$GRUB_FILE" 2>/dev/null; then
    echo "Parameter 'threadirqs' already exists in GRUB."
else
    # Find current line and add parameters
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE"; then
        # Extract current value
        CURRENT_VALUE=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" | sed 's/GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
        # Add new parameters
        NEW_VALUE="$CURRENT_VALUE threadirqs usbcore.autosuspend=-1"
        
        echo ""
        read -p "Would you like to disable Spectre/Meltdown mitigations? (increases performance, reduces security) (y/n): " mitig_answer
        if [[ $mitig_answer =~ ^[yY]$ ]]; then
            NEW_VALUE="$NEW_VALUE mitigations=off"
        fi

        # Replace in file
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_VALUE\"|" "$GRUB_FILE"
        echo "Updated kernel parameters: $NEW_VALUE"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_FILE"
    fi
fi

echo ""
echo "[3/3] Checking for Realtime Kernel..."
if uname -v | grep -q "PREEMPT_RT"; then
    echo "You are already running a Realtime (RT) kernel."
else
    read -p "Would you like to install the Realtime (RT) kernel for lower latency? (y/n): " rt_answer
    if [[ $rt_answer =~ ^[yY]$ ]]; then
        echo "Installing RT kernel..."
        # If Pascal conflict, try to get 6.12-rt
        if [[ "$ARCH" == "pascal" ]] && (( KMAJ >= 7 )); then
             # Ensure stable repo exists
             if ! grep -qs "trixie" /etc/apt/sources.list /etc/apt/sources.list.d/*.list; then
                  echo "deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list.d/debian-stable.list > /dev/null
                  sudo apt update
             fi
             sudo apt install -y linux-image-6.12-rt-amd64 linux-headers-6.12-rt-amd64 || sudo apt install -y linux-image-rt-amd64
        else
             sudo apt install -y linux-image-rt-amd64 linux-headers-rt-amd64
        fi
        echo "RT kernel installed. Please reboot and select it in GRUB."
    fi
fi

echo ""
echo "Regenerating GRUB..."
sudo update-grub

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|             KERNEL PARAMETERS CONFIGURED!                |
+----------------------------------------------------------+
EOF
echo ""
echo "Added parameters (if missing):"
echo "  - threadirqs              (RT interrupt priorities)"
echo "  - usbcore.autosuspend=-1  (disable USB autosuspend)"
echo ""
echo "IMPORTANT: Restart your computer for changes to take effect."
echo ""
read -rsn1 -p "Press Enter to continue..."
