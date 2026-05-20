#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                RTCQS AUDIT TOOL                        |
|       System Audio Production Verification             |
+----------------------------------------------------------+
EOF
echo ""

echo "[1/2] Checking pipx installation..."
if command -v pipx &> /dev/null; then
    echo "pipx is already installed."
else
    echo "Installing pipx..."
    sudo apt update
    sudo apt install -y pipx
fi

echo ""
echo "[2/2] Checking rtcqs installation..."
if command -v rtcqs &> /dev/null || [ -f "$HOME/.local/bin/rtcqs" ]; then
    echo "rtcqs is already installed."
    rtcqs --version 2>/dev/null || echo "Version check skipped"
else
    echo "Installing rtcqs..."
    pipx install rtcqs
fi

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|                RTCQS INSTALLED!                          |
+----------------------------------------------------------+
EOF
echo ""
echo "rtcqs checks your system for:"
echo "  - Realtime permissions"
echo "  - Kernel configuration"
echo "  - Resource limits"
echo "  - CPU governor"
echo "  - PipeWire status"
echo "  - Swappiness settings"
echo ""
echo "Run audit with:"
echo "  rtcqs"
echo ""
echo "Expected results for audio production:"
echo "  - realtime OK"
echo "  - rtprio OK"
echo "  - memlock unlimited"
echo "  - governor performance"
echo "  - PipeWire active"
echo "  - swappiness = 10"
echo ""
read -rsn1 -p "Press Enter to continue..."
