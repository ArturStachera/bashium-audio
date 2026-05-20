#!/bin/bash

clear
cat <<'EOF'
+----------------------------------------------------------+
|              COMPILATION TOOLS INSTALLATION              |
+----------------------------------------------------------+
EOF
echo ""

COMP_PKGS="
build-essential
pkg-config
cmake
meson
ninja-build
autoconf
automake
libtool
linux-headers-$(uname -r)
"

MISSING=""

for pkg in $COMP_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Installing missing compilation tools:$MISSING..."
    sudo apt install -y $MISSING
else
    echo "All compilation tools already installed."
fi