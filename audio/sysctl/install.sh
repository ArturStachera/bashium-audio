#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                  SYSCTL TUNING SETUP                     |
|           Memory and Sample Libraries                    |
+----------------------------------------------------------+
EOF
echo ""

CONFIG_FILE="/etc/sysctl.d/99-audio.conf"

echo "[1/3] Checking sysctl configuration..."

# Define desired configuration
NEW_CONFIG="# Audio production optimizations
# Swap only for emergencies
vm.swappiness=10

# Larger file limit for sample libraries
fs.inotify.max_user_watches=600000

# Network audio optimizations
net.core.rmem_max=250000000
net.core.wmem_max=250000000
net.ipv4.tcp_rmem=4096 87380 250000000
net.ipv4.tcp_wmem=4096 65536 250000000"

# Check if file exists with same content
if [ -f "$CONFIG_FILE" ] && echo "$NEW_CONFIG" | diff -q - "$CONFIG_FILE" > /dev/null 2>&1; then
    echo "Configuration file already exists with correct settings."
else
    echo "Creating/updating sysctl configuration..."
    echo "$NEW_CONFIG" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "Created/updated $CONFIG_FILE"
fi
echo ""

echo "[2/3] Configuration content:"
echo "----------------------------------------"
cat "$CONFIG_FILE"
echo "----------------------------------------"
echo ""

echo "[3/3] Applying changes..."
sudo sysctl --system

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|                SYSCTL CONFIGURED!                      |
+----------------------------------------------------------+
EOF
echo ""
echo "Changes applied:"
echo "  - vm.swappiness=10              (minimal swap usage)"
echo "  - fs.inotify.max_user_watches   (more monitored files)"
echo "  - net.core.*mem_max             (network buffering)"
echo ""
echo "Changes are active immediately (no restart needed)."
echo ""
read -rsn1 -p "Press Enter to continue..."
