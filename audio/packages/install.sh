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

echo "[1/4] Checking DAW and recording tools..."

DAW_PKGS=(
    ardour
    audacity
    hydrogen
    mixxx
)

install_if_available "${DAW_PKGS[@]}"

echo ""
echo "[2/4] Checking plugins (LV2/LADSPA)..."

PLUGIN_PKGS=(
    calf-plugins
    lsp-plugins
    zam-plugins
    x42-plugins
    invada-studio-plugins-lv2
    guitarix
)

install_if_available "${PLUGIN_PKGS[@]}"

echo ""
echo "[3/4] Checking additional tools..."

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
echo "[4/4] Checking synthesizers and instruments..."

SYNTH_PKGS=(
    zynaddsubfx
    fluidsynth
    qsynth
)

install_if_available "${SYNTH_PKGS[@]}"

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
echo "  - ZynAddSubFX     (synthesizer)"
echo "  - FluidSynth      (SoundFont player)"
echo "  - QSynth          (FluidSynth GUI)"

echo ""
echo "Setup completed successfully."

read -rp "Press Enter to continue..."