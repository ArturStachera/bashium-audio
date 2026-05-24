#!/bin/bash

set -e

# ----------------------------------------------------------
# BASHIUM AUDIO - WINE + YABRIDGE INSTALLER
# Debian testing / Forky compatible
# ----------------------------------------------------------

clear

cat <<'EOF'
+----------------------------------------------------------+
|              WINE + YABRIDGE SETUP                       |
|         Windows VST Plugins on Linux                     |
+----------------------------------------------------------+
EOF

echo ""

# ----------------------------------------------------------
# CONFIG
# ----------------------------------------------------------

export WINEPREFIX="$HOME/wine-audio"
export WINEARCH="win64"
export WINEDEBUG="-all"

YABRIDGE_DIR="$HOME/.local/share/yabridge"
BIN_DIR="$HOME/.local/bin"

VST2_DIR="$WINEPREFIX/drive_c/VSTPlugins"
VST3_DIR="$WINEPREFIX/drive_c/Program Files/Common Files/VST3"

# ----------------------------------------------------------
# HELPERS
# ----------------------------------------------------------

info() { echo -e "\e[1;34m[INFO]\e[0m $1"; }
success() { echo -e "\e[1;32m[SUCCESS]\e[0m $1"; }
warn() { echo -e "\e[1;33m[WARNING]\e[0m $1"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $1"; }

# ----------------------------------------------------------
# INTERNET CHECK
# ----------------------------------------------------------

info "Checking internet connection..."

if ! ping -c 1 github.com &>/dev/null; then
    error "No internet connection."
    exit 1
fi

success "Internet connection OK"

# ----------------------------------------------------------
# ENABLE i386
# ----------------------------------------------------------

info "Enabling i386 architecture..."
sudo dpkg --add-architecture i386 2>/dev/null || true

# ----------------------------------------------------------
# UPDATE APT
# ----------------------------------------------------------

info "Updating package lists..."
sudo apt update

# ----------------------------------------------------------
# INSTALL WINE FROM DEBIAN REPOS
# Debian testing/Forky carries a recent wine build.
# winehq repos do not support testing — do not add them.
# ----------------------------------------------------------

info "Installing wine..."

for pkg in wine wine64 "wine32:i386"; do
    if ! dpkg -l "${pkg%%:*}" 2>/dev/null | grep -q "^ii"; then
        sudo apt install -y "$pkg" 2>/dev/null || \
            warn "Could not install $pkg (may be pulled as dependency)"
    fi
done

if ! command -v wine &>/dev/null; then
    error "Wine was not installed correctly."
    exit 1
fi

WINE_VERSION=$(wine --version)
success "Wine installed: $WINE_VERSION"

# ----------------------------------------------------------
# INSTALL DEPENDENCIES
# ----------------------------------------------------------

info "Installing dependencies..."

for pkg in curl wget cabextract unzip p7zip-full zenity; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        sudo apt install -y "$pkg" || warn "Could not install: $pkg"
    fi
done

# ----------------------------------------------------------
# INSTALL WINETRICKS STANDALONE
# The Debian winetricks package depends on the Debian wine
# package by name, causing conflicts. The standalone script
# has no such dependency and is always up to date.
# ----------------------------------------------------------

info "Installing winetricks (standalone from GitHub)..."

sudo wget -q -O /usr/local/bin/winetricks \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks

sudo chmod +x /usr/local/bin/winetricks

success "winetricks installed"

# ----------------------------------------------------------
# CREATE WINE PREFIX
# ----------------------------------------------------------

info "Creating Wine audio prefix..."

mkdir -p "$WINEPREFIX"
WINEDEBUG="-all" winecfg > /dev/null 2>&1 || true

success "Wine prefix initialized"

# ----------------------------------------------------------
# OPTIONAL RUNTIMES
# ----------------------------------------------------------

echo ""
read -rp "Install common VST runtime libraries? [Y/n]: " INSTALL_RUNTIME

if [[ "$INSTALL_RUNTIME" =~ ^[Yy]$|^$ ]]; then

    info "Installing Visual C++ runtime..."

    WINEPREFIX="$WINEPREFIX" winetricks -q corefonts vcrun2019 || {
        warn "Winetricks runtime installation failed."
    }

    success "Runtime libraries installed"

fi

# ----------------------------------------------------------
# CREATE VST DIRECTORIES
# ----------------------------------------------------------

info "Creating VST directories..."

mkdir -p "$VST2_DIR"
mkdir -p "$VST3_DIR"
mkdir -p "$HOME/.vst"
mkdir -p "$HOME/.vst3"

success "VST directories created"

# ----------------------------------------------------------
# INSTALL YABRIDGE
# ----------------------------------------------------------

info "Installing yabridge..."

mkdir -p "$YABRIDGE_DIR"
mkdir -p "$BIN_DIR"

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

DOWNLOAD_URL=$(curl -s \
    https://api.github.com/repos/robbert-vdh/yabridge/releases/latest \
    | grep browser_download_url \
    | grep 'yabridge-.*\.tar\.gz' \
    | cut -d '"' -f 4 \
    | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    error "Could not find yabridge release."
    exit 1
fi

info "Downloading yabridge..."
curl -L "$DOWNLOAD_URL" -o yabridge.tar.gz

info "Extracting yabridge..."
tar -xzf yabridge.tar.gz

EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "yabridge*" | head -n 1)

if [ -z "$EXTRACTED_DIR" ]; then
    error "Could not extract yabridge."
    exit 1
fi

cp -r "$EXTRACTED_DIR"/* "$YABRIDGE_DIR/"
ln -sf "$YABRIDGE_DIR/yabridgectl" "$BIN_DIR/yabridgectl"

success "yabridge installed"

# ----------------------------------------------------------
# PATH + ENVIRONMENT
# ----------------------------------------------------------

if ! grep -q '.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

if ! grep -q 'WINEPREFIX' "$HOME/.bashrc"; then
    echo 'export WINEPREFIX="$HOME/wine-audio"' >> "$HOME/.bashrc"
fi

if ! grep -q 'WINEARCH' "$HOME/.bashrc"; then
    echo 'export WINEARCH="win64"' >> "$HOME/.bashrc"
fi

export PATH="$HOME/.local/bin:$PATH"

# ----------------------------------------------------------
# PW-JACK WRAPPER SCRIPTS
# Wrapper scripts work in terminal AND desktop menu launchers.
# Aliases (.bashrc) only work in terminal — ignored by menus.
# ----------------------------------------------------------

info "Creating pw-jack wrapper scripts..."

JACK_APPS="meterbridge carla jack_mixer non-mixer japa jnoise ardour"

for app in $JACK_APPS; do

    WRAPPER="$BIN_DIR/$app"

    # Skip if wrapper already exists with pw-jack
    if [ -f "$WRAPPER" ] && grep -q "pw-jack" "$WRAPPER" 2>/dev/null; then
        continue
    fi

    REAL_BIN=$(command -v "$app" 2>/dev/null || true)

    if [ -n "$REAL_BIN" ] && [ "$REAL_BIN" != "$WRAPPER" ]; then
        cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
exec pw-jack $REAL_BIN "\$@"
WRAPPER_EOF
    else
        cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
REAL_BIN=\$(command -v "$app" 2>/dev/null || true)
if [ -z "\$REAL_BIN" ] || [ "\$REAL_BIN" = "$BIN_DIR/$app" ]; then
    echo "Error: $app is not installed." >&2
    exit 1
fi
exec pw-jack "\$REAL_BIN" "\$@"
WRAPPER_EOF
    fi

    chmod +x "$WRAPPER"

done

success "pw-jack wrapper scripts created"

# ----------------------------------------------------------
# CONFIGURE YABRIDGE
# ----------------------------------------------------------

info "Adding plugin paths to yabridge..."

"$BIN_DIR/yabridgectl" add "$VST2_DIR" 2>/dev/null || true
"$BIN_DIR/yabridgectl" add "$VST3_DIR" 2>/dev/null || true

info "Syncing yabridge..."

"$BIN_DIR/yabridgectl" sync || {
    warn "yabridge sync failed"
}

success "yabridge configured"

# ----------------------------------------------------------
# FINISH
# ----------------------------------------------------------

clear

cat <<EOF

+----------------------------------------------------------+
|                    INSTALL COMPLETE                      |
+----------------------------------------------------------+

Wine:          $(wine --version 2>/dev/null || echo "installed")
Wine Prefix:   $WINEPREFIX
Architecture:  $WINEARCH

VST2 Directory:
  $VST2_DIR

VST3 Directory:
  $VST3_DIR

============================================================
FIRST STEPS
============================================================

1. Reload shell environment:

   source ~/.bashrc

2. Install a Windows VST plugin:

   wine setup.exe

   Install to:
     VST2:  C:\\VSTPlugins
     VST3:  C:\\Program Files\\Common Files\\VST3

3. Sync yabridge after each new plugin install:

   yabridgectl sync

4. Scan in your DAW:

   ~/.vst
   ~/.vst3

============================================================
JACK APPLICATIONS
============================================================

pw-jack wrapper scripts created for:
  $JACK_APPS

These wrap JACK apps to use PipeWire's JACK layer.
Works in terminal and desktop menu launchers.

To add wrappers for new JACK apps, run this script again.

============================================================
USEFUL COMMANDS
============================================================

List plugins:       yabridgectl list
Force resync:       yabridgectl sync --force
Remove broken:      yabridgectl prune
Wine config:        winecfg
Install runtime:    winetricks vcrun2019

============================================================
SUPPORTED DAWs
============================================================

- REAPER
- Bitwig Studio
- Ardour
- Carla
- Waveform
- Mixbus

============================================================

EOF

read -n 1 -s -r -p "Press any key to exit..."
echo ""