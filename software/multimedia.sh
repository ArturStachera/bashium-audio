#!/bin/bash

clear
cat <<'EOF'
+----------------------------------------------------------+
|              MULTIMEDIA APPS INSTALLATION                |
+----------------------------------------------------------+
EOF
echo ""

MULTI_PKGS="
vlc
qmmp
gimp
mpv
obs-studio
pavucontrol
easyeffects
gwenview
"

MISSING=""

for pkg in $MULTI_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Installing missing multimedia apps:$MISSING..."
    sudo apt install -y $MISSING
else
    echo "All multimedia apps already installed."
fi