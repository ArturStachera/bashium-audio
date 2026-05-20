#!/bin/bash

set -e

# ----------------------------------------------------------
# BASHIUM AUDIO - WINE + YABRIDGE INSTALLER
# Debian / Ubuntu compatible
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

info() {
    echo -e "\e[1;34m[INFO]\e[0m $1"
}

success() {
    echo -e "\e[1;32m[SUCCESS]\e[0m $1"
}

warn() {
    echo -e "\e[1;33m[WARNING]\e[0m $1"
}

error() {
    echo -e "\e[1;31m[ERROR]\e[0m $1"
}

# ----------------------------------------------------------
# PACKAGE INSTALLER
# ----------------------------------------------------------

install_if_exists() {

    PACKAGE="$1"

    if apt-cache show "$PACKAGE" &>/dev/null; then

        info "Installing package: $PACKAGE"

        sudo apt install -y "$PACKAGE"

    else

        warn "Skipping missing package: $PACKAGE"

    fi
}

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
# INSTALL REQUIRED PACKAGES
# ----------------------------------------------------------

info "Installing dependencies..."

install_if_exists wine
install_if_exists winetricks
install_if_exists curl
install_if_exists wget
install_if_exists cabextract
install_if_exists unzip
install_if_exists p7zip-full
install_if_exists zenity

# ----------------------------------------------------------
# CHECK WINE
# ----------------------------------------------------------

if ! command -v wine &>/dev/null; then

    error "Wine was not installed correctly."
    exit 1

fi

success "Wine installed"

# ----------------------------------------------------------
# CREATE WINE PREFIX
# ----------------------------------------------------------

info "Creating Wine audio prefix..."

mkdir -p "$WINEPREFIX"

winecfg > /dev/null 2>&1 || true

success "Wine prefix initialized"

# ----------------------------------------------------------
# OPTIONAL RUNTIMES
# ----------------------------------------------------------

echo ""
read -rp "Install common VST runtime libraries? [Y/n]: " INSTALL_RUNTIME

if [[ "$INSTALL_RUNTIME" =~ ^[Yy]$|^$ ]]; then

    if command -v winetricks &>/dev/null; then

        info "Installing Visual C++ runtime..."

        winetricks -q corefonts vcrun2019 || {
            warn "Winetricks runtime installation failed."
        }

        success "Runtime libraries installed"

    else

        warn "Winetricks not available."

    fi

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

ln -sf "$YABRIDGE_DIR/yabridge" "$BIN_DIR/yabridge"
ln -sf "$YABRIDGE_DIR/yabridgectl" "$BIN_DIR/yabridgectl"

success "yabridge installed"

# ----------------------------------------------------------
# PATH
# ----------------------------------------------------------

if ! grep -q '.local/bin' "$HOME/.bashrc"; then

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

fi

export PATH="$HOME/.local/bin:$PATH"

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

Wine Prefix:
  $WINEPREFIX

VST2 Directory:
  $VST2_DIR

VST3 Directory:
  $VST3_DIR

============================================================
HOW TO INSTALL WINDOWS VST PLUGINS
============================================================

1. Run plugin installer:

   wine setup.exe

2. Install plugins to:

   VST2:
   C:\\VSTPlugins

   VST3:
   C:\\Program Files\\Common Files\\VST3

3. Sync yabridge:

   yabridgectl sync

4. Open your DAW and scan:

   ~/.vst
   ~/.vst3

============================================================
USEFUL COMMANDS
============================================================

List plugins:
   yabridgectl list

Force resync:
   yabridgectl sync --force

Remove broken plugins:
   yabridgectl prune

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