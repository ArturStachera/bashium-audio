#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|              ADDITIONAL AUDIO TOOLS                    |
+----------------------------------------------------------+
EOF
echo ""

echo "Checking additional utility tools..."
# Debian package names (some differ from Arch)
TOOL_PKGS="meterbridge vkeybd aconnectgui qpwgraph"
MISSING_TOOLS=""

for pkg in $TOOL_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING_TOOLS="$MISSING_TOOLS $pkg"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo "Installing missing tools:$MISSING_TOOLS..."
    sudo apt update
    sudo apt install -y $MISSING_TOOLS
else
    echo "All additional tools already installed."
fi

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|           ADDITIONAL TOOLS INSTALLED!                    |
+----------------------------------------------------------+
EOF
echo ""
echo "Meters / Monitoring:"
echo "  - meterbridge     (audio level meters)"
echo ""
echo "Routing / Connection:"
echo "  - patchage        (JACK patchbay)"
echo "  - aconnectgui     (MIDI connection GUI)"
echo ""
echo "Virtual Instruments:"
echo "  - vkeybd          (virtual MIDI keyboard)"
echo ""
echo "Note: jack-rack and freqtweak are not available in Debian repos."
echo "      Consider Carla or LSP plugins as alternatives."
echo ""
read -rsn1 -p "Press Enter to continue..."
