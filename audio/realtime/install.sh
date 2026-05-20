#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                REALTIME AUDIO SETUP                      |
|                   RT Priorities                          |
+----------------------------------------------------------+
EOF
echo ""

echo "[1/4] Installing realtime support packages..."
sudo apt update

# Install rtkit for realtime scheduling via D-Bus
sudo apt install -y rtkit

# Configure PAM limits for audio group
if [ ! -f /etc/security/limits.d/audio.conf ]; then
    echo "@audio   -  rtprio     95" | sudo tee /etc/security/limits.d/audio.conf > /dev/null
    echo "@audio   -  memlock    unlimited" | sudo tee -a /etc/security/limits.d/audio.conf > /dev/null
    echo "Realtime limits configured for audio group"
else
    echo "Audio limits already configured"
fi

echo ""
echo "[2/4] Configuring device access..."
# Add udev rule for /dev/cpu_dma_latency
if [ ! -f /etc/udev/rules.d/99-cpu-dma-latency.rules ]; then
    echo 'KERNEL=="cpu_dma_latency", GROUP="audio", MODE="0660"' | sudo tee /etc/udev/rules.d/99-cpu-dma-latency.rules > /dev/null
    echo "udev rule for /dev/cpu_dma_latency created"
    sudo udevadm control --reload-rules && sudo udevadm trigger || true
else
    echo "/dev/cpu_dma_latency rule already exists"
fi

echo ""
echo "[3/4] Checking user groups..."
CURRENT_GROUPS=$(groups "$USER" 2>/dev/null || echo "")

# Add to audio group
if echo "$CURRENT_GROUPS" | grep -q "audio"; then
    echo "User is already in the 'audio' group."
else
    echo "Adding user to audio group..."
    sudo usermod -aG audio "$USER"
    echo "Group added."
fi

# Add to realtime group (common in some setups, even if manual)
if getent group realtime > /dev/null; then
    if echo "$CURRENT_GROUPS" | grep -q "realtime"; then
        echo "User is already in the 'realtime' group."
    else
        echo "Adding user to realtime group..."
        sudo usermod -aG realtime "$USER"
    fi
else
    echo "Creating 'realtime' group and adding user..."
    sudo groupadd -r realtime || true
    sudo usermod -aG realtime "$USER"
fi

echo ""
echo "[4/4] Verifying groups..."
echo "Current groups for user $USER:"
groups "$USER"

echo ""
echo "[4/4] Checking memlock..."
MEMLOCK=$(ulimit -l)
echo "Memlock limit: $MEMLOCK"

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|              REALTIME AUDIO CONFIGURED!                  |
+----------------------------------------------------------+
EOF
echo ""
echo "IMPORTANT: Log out and log back in for group changes"
echo "           to take effect."
echo ""
echo "After re-login, verify with:"
echo "  groups        - should include 'audio realtime'"
echo "  ulimit -l     - should return 'unlimited'"
echo ""
read -rsn1 -p "Press Enter to continue..."
