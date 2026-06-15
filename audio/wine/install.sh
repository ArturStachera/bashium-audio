#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------
# BASHIUM AUDIO - WINEHQ + YABRIDGE INSTALLER
# Debian testing / stable compatible
# ----------------------------------------------------------

trap 'rm -rf "${TEMP_DIR:-}"' EXIT

info()    { echo -e "\e[1;34m[INFO]\e[0m $*"; }
success() { echo -e "\e[1;32m[SUCCESS]\e[0m $*"; }
warn()    { echo -e "\e[1;33m[WARNING]\e[0m $*"; }
error()   { echo -e "\e[1;31m[ERROR]\e[0m $*"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

banner() {
    clear || true
    cat <<'BANNER'
+----------------------------------------------------------+
|              WINE + YABRIDGE SETUP                       |
|         Windows VST Plugins on Linux                     |
+----------------------------------------------------------+
BANNER
    echo
}

require_cmd() {
    local cmd="$1"
    if ! have_cmd "$cmd"; then
        error "Required tool not found: $cmd"
        exit 1
    fi
}

append_if_missing() {
    local file="$1"
    local line="$2"
    sudo touch "$file"
    if ! grep -Fqx "$line" "$file"; then
        echo "$line" | sudo tee -a "$file" >/dev/null
    fi
}

check_internet() {
    info "Checking internet connection..."
    if ! curl -fsI --max-time 10 https://dl.winehq.org >/dev/null; then
        error "No internet connection, or WineHQ is unreachable."
        exit 1
    fi
    success "Internet connection OK"
}

install_base_packages() {
    info "Installing required tools..."
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        apt-transport-https \
        cabextract \
        unzip \
        p7zip-full \
        zenity \
        jq \
        xdg-utils
}

enable_i386() {
    info "Enabling i386 architecture..."
    sudo dpkg --add-architecture i386
}

detect_debian_codename() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${VERSION_CODENAME:-}"
    else
        echo ""
    fi
}

setup_winehq_repo() {
    local keyring="/etc/apt/keyrings/winehq-archive.key"
    local repo_file="/etc/apt/sources.list.d/winehq.list"
    local codename="${1:-}"
    local repo_url="https://dl.winehq.org/wine-builds/debian"

    info "Configuring WineHQ repository for Debian ${codename}..."

    sudo mkdir -p /etc/apt/keyrings

    if [[ ! -s "$keyring" ]]; then
        curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
            | gpg --dearmor \
            | sudo tee "$keyring" >/dev/null
        sudo chmod 0644 "$keyring"
    fi

    cat <<EOF_REPO | sudo tee "$repo_file" >/dev/null
deb [signed-by=$keyring] $repo_url $codename main
EOF_REPO

    if sudo apt-get update; then
        return 0
    fi

    return 1
}

install_winehq() {
    local candidates=()
    local env_codename="${WINEHQ_DISTRO:-}"
    local system_codename
    system_codename="$(detect_debian_codename)"

    if [[ -n "$env_codename" ]]; then
        candidates+=("$env_codename")
    fi

    if [[ -n "$system_codename" ]]; then
        candidates+=("$system_codename")
    fi

    candidates+=(trixie bookworm)

    local unique_candidates=()
    local seen=""

    for c in "${candidates[@]}"; do
        [[ -z "$c" ]] && continue
        if [[ " $seen " != *" $c "* ]]; then
            unique_candidates+=("$c")
            seen+=" $c"
        fi
    done

    local chosen=""
    local codename
    for codename in "${unique_candidates[@]}"; do
        if setup_winehq_repo "$codename"; then
            chosen="$codename"
            break
        fi
        warn "WineHQ repository for '$codename' did not update cleanly."
    done

    if [[ -z "$chosen" ]]; then
        error "Could not enable a working WineHQ repository."
        error "You can try setting WINEHQ_DISTRO=trixie or WINEHQ_DISTRO=bookworm and rerun."
        exit 1
    fi

    success "WineHQ repository enabled: $chosen"

    local channel="${WINEHQ_CHANNEL:-staging}"
    local pkg="winehq-${channel}"

    info "Installing Wine from WineHQ: $pkg"
    if ! sudo apt-get install -y --install-recommends "$pkg"; then
        warn "Could not install $pkg, trying fallback channels..."
        for channel in devel stable; do
            pkg="winehq-${channel}"
            info "Trying $pkg..."
            if sudo apt-get install -y --install-recommends "$pkg"; then
                success "Wine installed with fallback package: $pkg"
                return 0
            fi
        done
        return 1
    fi

    success "Wine installed: $pkg"
}

install_winetricks() {
    info "Installing winetricks (standalone)..."
    sudo curl -fsSL \
        -o /usr/local/bin/winetricks \
        https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    sudo chmod +x /usr/local/bin/winetricks
    success "winetricks installed"
}

create_prefix() {
    info "Creating Wine audio prefix..."
    export WINEPREFIX="${WINEPREFIX:-$HOME/wine-audio}"
    export WINEARCH="${WINEARCH:-win64}"
    export WINEDEBUG="${WINEDEBUG:--all}"

    mkdir -p "$WINEPREFIX"

    # Initialize the prefix and let Wine create its internal structure.
    wineboot -u >/dev/null 2>&1 || true
    winecfg >/dev/null 2>&1 || true

    success "Wine prefix initialized: $WINEPREFIX"
}

install_runtime_packages() {
    echo
    read -rp "Install common VST runtime libraries? [Y/n]: " INSTALL_RUNTIME
    if [[ "${INSTALL_RUNTIME:-}" =~ ^[Nn]$ ]]; then
        warn "Skipping runtime libraries."
        return 0
    fi

    info "Installing runtime libraries via winetricks..."
    if WINEPREFIX="$WINEPREFIX" winetricks -q corefonts vcrun2019; then
        success "Runtime libraries installed"
    else
        warn "Runtime installation failed, but the main setup can still work."
    fi
}

create_directories() {
    info "Creating VST directories..."
    export YABRIDGE_DIR="${YABRIDGE_DIR:-$HOME/.local/share/yabridge}"
    export BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

    export VST2_DIR="${VST2_DIR:-$WINEPREFIX/drive_c/VSTPlugins}"
    export VST3_DIR="${VST3_DIR:-$WINEPREFIX/drive_c/Program Files/Common Files/VST3}"
    export CLAP_DIR="${CLAP_DIR:-$WINEPREFIX/drive_c/Program Files/Common Files/CLAP}"

    mkdir -p "$VST2_DIR" "$VST3_DIR" "$CLAP_DIR"
    mkdir -p "$HOME/.vst" "$HOME/.vst3" "$HOME/.clap"
    mkdir -p "$YABRIDGE_DIR" "$BIN_DIR"

    success "VST directories created"
}

install_yabridge() {
    info "Installing yabridge..."

    TEMP_DIR="$(mktemp -d)"
    cd "$TEMP_DIR"

    local download_url
    download_url="$({
        curl -fsSL https://api.github.com/repos/robbert-vdh/yabridge/releases/latest \
        | jq -r '.assets[] | select(.name | test("^yabridge-.*\\.tar\\.gz$")) | .browser_download_url' \
        | grep -v 'ubuntu-18\\.04' \
        | head -n 1
    } || true)"

    if [[ -z "${download_url:-}" || "$download_url" == "null" ]]; then
        error "Could not find a yabridge release archive."
        exit 1
    fi

    info "Downloading yabridge..."
    curl -fL "$download_url" -o yabridge.tar.gz

    info "Extracting yabridge..."
    tar -xzf yabridge.tar.gz

    local extracted_dir
    extracted_dir="$(find . -maxdepth 1 -type d -name 'yabridge*' | head -n 1)"

    if [[ -z "$extracted_dir" ]]; then
        error "Could not extract yabridge."
        exit 1
    fi

    rm -rf "$YABRIDGE_DIR"/*
    cp -a "$extracted_dir"/. "$YABRIDGE_DIR"/
    ln -sf "$YABRIDGE_DIR/yabridgectl" "$BIN_DIR/yabridgectl"

    success "yabridge installed"
}

configure_shell_path() {
    info "Configuring PATH in shell startup files..."

    append_if_missing "$HOME/.bashrc" 'export PATH="$HOME/.local/bin:$HOME/.local/share/yabridge:$PATH"'
    append_if_missing "$HOME/.bashrc" 'export WINEPREFIX="$HOME/wine-audio"'
    append_if_missing "$HOME/.bashrc" 'export WINEARCH="win64"'

    export PATH="$HOME/.local/bin:$HOME/.local/share/yabridge:$PATH"
    export WINEPREFIX="$HOME/wine-audio"
    export WINEARCH="win64"
}

configure_yabridge() {
    info "Adding plugin paths to yabridge..."

    "$BIN_DIR/yabridgectl" add "$VST2_DIR" 2>/dev/null || true
    "$BIN_DIR/yabridgectl" add "$VST3_DIR" 2>/dev/null || true
    "$BIN_DIR/yabridgectl" add "$CLAP_DIR" 2>/dev/null || true

    info "Syncing yabridge..."
    "$BIN_DIR/yabridgectl" sync || warn "yabridge sync failed"

    success "yabridge configured"
}

create_pw_jack_wrappers() {
    if ! have_cmd pw-jack; then
        warn "pw-jack not found, skipping JACK wrapper scripts."
        return 0
    fi

    info "Creating pw-jack wrapper scripts..."

    local jack_apps="carla meterbridge jack_mixer non-mixer japa jnoise ardour reaper"
    local app wrapper real_bin

    for app in $jack_apps; do
        wrapper="$BIN_DIR/$app"
        real_bin="$(command -v "$app" 2>/dev/null || true)"

        cat > "$wrapper" <<EOF_WRAPPER
#!/usr/bin/env bash
exec pw-jack "${real_bin:-$app}" "\$@"
EOF_WRAPPER
        chmod +x "$wrapper"
    done

    success "pw-jack wrapper scripts created"
}

finish_message() {
    clear || true
    cat <<EOF

+----------------------------------------------------------+
|                    INSTALL COMPLETE                      |
+----------------------------------------------------------+

Wine prefix:
  $WINEPREFIX

WineHQ channel:
  ${WINEHQ_CHANNEL:-staging}

yabridge directory:
  $YABRIDGE_DIR

VST2 directory:
  $VST2_DIR

VST3 directory:
  $VST3_DIR

CLAP directory:
  $CLAP_DIR

============================================================
FIRST STEPS
============================================================

1. Reload shell environment:

   source ~/.bashrc

2. Install a Windows plugin into the Wine prefix:

   wine setup.exe

   Suggested locations:
     VST2:  C:\\VSTPlugins
     VST3:  C:\\Program Files\\Common Files\\VST3
     CLAP:  C:\\Program Files\\Common Files\\CLAP

3. Sync yabridge after each new plugin install:

   yabridgectl sync

4. Scan these paths in your DAW:

   ~/.vst
   ~/.vst3
   ~/.clap

============================================================
USEFUL COMMANDS
============================================================

List plugins:       yabridgectl list
Force resync:       yabridgectl sync --force
Remove broken:      yabridgectl prune
Wine config:        winecfg
Prefix boot:        wineboot -u

============================================================
NOTES
============================================================

- This setup uses WineHQ because Debian testing may temporarily not ship Wine packages.
- yabridge should live in ~/.local/share/yabridge and yabridgectl can be run from PATH.
- If plugin GUIs look blank or odd, corefonts and vcrun2019 are the first things to try.

EOF
}

main() {
    banner

    require_cmd sudo
    require_cmd curl
    require_cmd wget
    require_cmd tar
    require_cmd grep
    require_cmd awk
    require_cmd gpg

    check_internet
    enable_i386
    install_base_packages
    install_winehq
    install_winetricks
    create_prefix
    install_runtime_packages
    create_directories
    install_yabridge
    configure_shell_path
    configure_yabridge
    create_pw_jack_wrappers
    finish_message

    echo
    read -n 1 -s -r -p "Press any key to exit..."
    echo
}

main "$@"
