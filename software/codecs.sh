#!/bin/bash

clear
cat <<'EOF'
+----------------------------------------------------------+
|              AUDIO/VIDEO CODECS INSTALLATION             |
+----------------------------------------------------------+
EOF
echo ""

CODEC_PKGS="gstreamer1.0-vaapi ffmpeg libavcodec-extra"
MISSING=""

for pkg in $CODEC_PKGS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Installing missing codec packages:$MISSING..."
    sudo apt install -y $MISSING
else
    echo "All codec packages already installed."
fi