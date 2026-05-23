#!/bin/bash

clear

cat <<'EOF'
+----------------------------------------------------------+
|                AUDIO PACKAGES SETUP                      |
|              Ubuntu Studio Style                         |
+----------------------------------------------------------+
EOF

echo ""

install_if_available() {
    for pkg in "$@"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            echo "[OK] $pkg already installed."
        else
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                echo "[INSTALL] $pkg"
                sudo apt install -y "$pkg"
            else
                echo "[SKIP] Package not available: $pkg"
            fi
        fi
    done
}

echo "[1/6] Checking DAW and recording tools..."

DAW_PKGS=(
    ardour
    audacity
    hydrogen
    mixxx
)

install_if_available "${DAW_PKGS[@]}"

echo ""
echo "[2/6] Checking plugins (LV2/LADSPA)..."

PLUGIN_PKGS=(
    calf-plugins
    lsp-plugins
    zam-plugins
    x42-plugins
    invada-studio-plugins-lv2
    guitarix
    swh-plugins
    tap-plugins
    mda-lv2
    caps
    dragonfly-reverb
)

install_if_available "${PLUGIN_PKGS[@]}"

echo ""
echo "[3/6] Checking additional tools..."

TOOL_PKGS=(
    qjackctl
    easyeffects
    helvum
    qpwgraph
    pavucontrol
)

# Carla detection for Debian/Ubuntu variants
if apt-cache show carla >/dev/null 2>&1; then
    TOOL_PKGS+=(carla)
elif apt-cache show carla-git >/dev/null 2>&1; then
    TOOL_PKGS+=(carla-git)
else
    echo "[SKIP] Carla package not available in repositories."
fi

install_if_available "${TOOL_PKGS[@]}"

echo ""
echo "[4/6] Checking synthesizers and instruments..."

SYNTH_PKGS=(
    zynaddsubfx
    fluidsynth
    qsynth
    yoshimi
    amsynth
    setbfree
)

install_if_available "${SYNTH_PKGS[@]}"

echo ""
echo "[5/6] Installing Yoshimi banks from GitHub..."

YOSHIMI_BANKS_DIR="$HOME/.local/share/yoshimi/banks"

if [ -d "$YOSHIMI_BANKS_DIR" ] && [ "$(ls -A "$YOSHIMI_BANKS_DIR" 2>/dev/null)" ]; then
    echo "[OK] Yoshimi banks already present, skipping."
else
    if command -v git >/dev/null 2>&1; then
        mkdir -p "$YOSHIMI_BANKS_DIR"
        TMP_YOSHIMI=$(mktemp -d)
        echo "[INSTALL] Cloning Yoshimi repository for banks..."
        git clone --depth=1 https://github.com/Yoshimi/yoshimi.git "$TMP_YOSHIMI" 2>&1 | tail -1
        if [ -d "$TMP_YOSHIMI/banks" ]; then
            cp -r "$TMP_YOSHIMI"/banks/* "$YOSHIMI_BANKS_DIR/"
            echo "[OK] Yoshimi banks installed to $YOSHIMI_BANKS_DIR"
        else
            echo "[SKIP] Could not find banks directory in cloned repo."
        fi
        rm -rf "$TMP_YOSHIMI"
    else
        echo "[SKIP] git not found, skipping Yoshimi banks. Install git and re-run."
    fi
fi

echo ""
echo "[6/6] Checking sampler (SFZ)..."

SAMPLER_PKGS=(
    sfizz
)

install_if_available "${SAMPLER_PKGS[@]}"

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|              AUDIO PACKAGES INSTALLED!                   |
+----------------------------------------------------------+
EOF

echo ""
echo "DAW / Recording:"
echo "  - Ardour          (professional DAW)"
echo "  - Audacity        (audio editor)"
echo "  - Hydrogen        (drum machine)"
echo "  - Mixxx           (DJ software)"

echo ""
echo "Plugins:"
echo "  - calf-plugins                (mixing/mastering)"
echo "  - lsp-plugins                 (professional mastering)"
echo "  - zam-plugins                 (analog emulations)"
echo "  - x42-plugins                 (utility/mastering)"
echo "  - invada-studio-plugins-lv2  (classic LV2 plugins)"
echo "  - guitarix                    (guitar amp simulator)"
echo "  - swh-plugins                 (Steve Harris LADSPA)"
echo "  - tap-plugins                 (LADSPA: reverb, chorus, etc.)"
echo "  - mda-lv2                     (MDA: epiano, synths, effects)"
echo "  - caps                        (C* Audio: analog emulations)"
echo "  - dragonfly-reverb            (high quality reverb)"

echo ""
echo "Tools:"
echo "  - Carla / Carla-Git  (plugin host)"
echo "  - qjackctl           (JACK control GUI)"
echo "  - EasyEffects        (audio processing)"
echo "  - qpwgraph           (PipeWire patchbay)"
echo "  - helvum             (simple patchbay)"
echo "  - pavucontrol        (volume control)"

echo ""
echo "Synthesizers:"
echo "  - ZynAddSubFX     (additive/subtractive synthesizer)"
echo "  - Yoshimi         (ZynAddSubFX fork, LV2 plugin)"
echo "  - amsynth         (analog virtual synthesizer)"
echo "  - setBfree        (Hammond organ emulator)"
echo "  - FluidSynth      (SoundFont player)"
echo "  - QSynth          (FluidSynth GUI)"

echo ""
echo "Banks:"
echo "  - Yoshimi banks   (~/.local/share/yoshimi/banks/)"

echo ""
echo "Sampler:"
echo "  - sfizz           (SFZ sampler, LV2 plugin)"

echo ""
echo "Setup completed successfully."

read -rp "Press Enter to continue..."