#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                 PIPEWIRE STACK SETUP                     |
|            Complete Audio Server Stack                   |
+----------------------------------------------------------+
EOF
echo ""

echo "[1/3] Checking PipeWire packages..."

# Check which packages are already installed
PACKAGES="pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber qpwgraph"
MISSING=""

for pkg in $PACKAGES; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -z "$MISSING" ]; then
    echo "All PipeWire packages already installed."
else
    echo "Installing missing packages:$MISSING..."
    sudo apt update
    sudo apt install -y $MISSING
fi

echo ""
echo "[2/3] Enabling user services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo ""
echo "[3/3] Verification..."
echo "Checking PipeWire status..."
if command -v pactl &> /dev/null; then
    SERVER_INFO=$(pactl info 2>/dev/null | grep "Server Name" || echo "Not available")
    echo "  $SERVER_INFO"
else
    echo "  pactl not available (will be after restart)"
fi

echo ""
echo "PipeWire services status:"
systemctl --user status pipewire --no-pager 2>/dev/null | head -4 || echo "  Service status check failed (normal if not logged in yet)"

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|              PIPEWIRE STACK INSTALLED!                   |
+----------------------------------------------------------+
EOF
echo ""
echo "Installed packages:"
echo "  - pipewire          (main audio server)"
echo "  - pipewire-alsa     (ALSA compatibility)"
echo "  - pipewire-pulse    (PulseAudio compatibility)"
echo "  - pipewire-jack     (JACK for DAW)"
echo "  - wireplumber       (device management)"
echo "  - qpwgraph          (patchbay / routing GUI)"
echo ""
echo "TIP: Use 'qpwgraph' to visually route audio."
echo ""
read -rsn1 -p "Press Enter to continue..."
