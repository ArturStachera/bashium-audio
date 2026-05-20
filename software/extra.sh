#!/bin/bash

clear
cat <<'EOF'
+----------------------------------------------------------+
|               EXTRA TOOLS INSTALLATION                   |
+----------------------------------------------------------+
EOF
echo ""

EXTRA_PKGS="
rar
unrar
zip
unzip
p7zip-full

neovim

fastfetch
inxi

curl
wget

mc
btop
nvtop

tree
rsync
fzf
ripgrep

lm-sensors
smartmontools
"

MISSING=""

for pkg in $EXTRA_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Installing missing extra tools:$MISSING..."
    sudo apt install -y $MISSING
else
    echo "All extra tools already installed."
fi