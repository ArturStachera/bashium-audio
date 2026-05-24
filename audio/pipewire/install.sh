#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                 PIPEWIRE STACK SETUP                     |
|            Complete Audio Server Stack                   |
+----------------------------------------------------------+
EOF
echo ""

echo "[1/3] Checking PipeWire packages..."

# Check which packages are already installed
PACKAGES="pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber qpwgraph"
MISSING=""

for pkg in $PACKAGES; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [ -z "$MISSING" ]; then
    echo "All PipeWire packages already installed."
else
    echo "Installing missing packages:$MISSING..."
    sudo apt update
    sudo apt install -y $MISSING
fi

echo ""
echo "[2/3] Enabling user services..."
systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo ""
echo "[3/3] Verification..."
echo "Checking PipeWire status..."
if command -v pactl &> /dev/null; then
    SERVER_INFO=$(pactl info 2>/dev/null | grep "Server Name" || echo "Not available")
    echo "  $SERVER_INFO"
else
    echo "  pactl not available (will be after restart)"
fi

echo ""
echo "PipeWire services status:"
systemctl --user status pipewire --no-pager 2>/dev/null | head -4 || echo "  Service status check failed (normal if not logged in yet)"

# ----------------------------------------------------------
# REMOVE QJACKCTL (incompatible with PipeWire)
# ----------------------------------------------------------

if dpkg -l qjackctl 2>/dev/null | grep -q "^ii"; then
    echo ""
    echo "Removing qjackctl (incompatible with PipeWire, use qpwgraph instead)..."
    sudo apt remove -y qjackctl 2>/dev/null || true
fi

# ----------------------------------------------------------
# PW-JACK WRAPPER SCRIPTS
# Wrapper scripts work in terminal AND desktop menu launchers.
# Aliases (.bashrc) only work in terminal — ignored by menus.
# ----------------------------------------------------------

echo ""
echo "Creating pw-jack wrapper scripts in ~/.local/bin/..."

mkdir -p "$HOME/.local/bin"

JACK_APPS="meterbridge carla jack_mixer non-mixer japa jnoise ardour"

WRAPPERS_CREATED=0

for app in $JACK_APPS; do

    WRAPPER="$HOME/.local/bin/$app"

    # Only create if the real binary exists on the system
    REAL_BIN=$(command -v "$app" 2>/dev/null || true)

    if [ -n "$REAL_BIN" ] && [ "$REAL_BIN" != "$WRAPPER" ]; then

        cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
exec pw-jack $REAL_BIN "\$@"
WRAPPER_EOF

        chmod +x "$WRAPPER"
        WRAPPERS_CREATED=$((WRAPPERS_CREATED + 1))

    fi

done

# Create stubs for apps not yet installed (will activate once installed)
for app in $JACK_APPS; do

    WRAPPER="$HOME/.local/bin/$app"

    if [ ! -f "$WRAPPER" ]; then

        cat > "$WRAPPER" <<WRAPPER_EOF
#!/bin/bash
REAL_BIN=\$(command -v "$app" 2>/dev/null || true)
if [ -z "\$REAL_BIN" ] || [ "\$REAL_BIN" = "$HOME/.local/bin/$app" ]; then
    echo "Error: $app is not installed." >&2
    exit 1
fi
exec pw-jack "\$REAL_BIN" "\$@"
WRAPPER_EOF

        chmod +x "$WRAPPER"

    fi

done

echo "Wrapper scripts created for: $JACK_APPS"

# ----------------------------------------------------------
# PATH
# ----------------------------------------------------------

if ! grep -q '.local/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

export PATH="$HOME/.local/bin:$PATH"

# ----------------------------------------------------------
# FINISH
# ----------------------------------------------------------

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|              PIPEWIRE STACK INSTALLED!                   |
+----------------------------------------------------------+

Installed packages:
  - pipewire          (main audio server)
  - pipewire-alsa     (ALSA compatibility)
  - pipewire-pulse    (PulseAudio compatibility)
  - pipewire-jack     (JACK for DAW)
  - wireplumber       (device management)
  - qpwgraph          (patchbay / routing GUI)

============================================================
JACK APPLICATIONS — HOW IT WORKS
============================================================

PipeWire includes a built-in JACK server.
JACK apps must connect via pw-jack wrapper — without it
they crash instantly because they look for a separate
jackd process that does not exist on PipeWire.

Wrapper scripts have been created in ~/.local/bin/ for:
  meterbridge, carla, jack_mixer, non-mixer,
  japa, jnoise, ardour

These work in BOTH terminal and desktop menu launchers.
No extra steps needed — just launch normally.

If you install new JACK apps later, run this script again
to generate their wrappers automatically.

============================================================
QJACKCTL — REMOVED
============================================================

QjackCtl was removed. It is designed to manage a standalone
jackd server process which does not exist on PipeWire.
Running it causes "Could not start JACK" errors.

Use qpwgraph instead — it is the native PipeWire patchbay
with the same functionality (routing, connections, meters).

  qpwgraph

============================================================
QPWGRAPH — AUDIO PATCHBAY
============================================================

Use qpwgraph to visually connect audio ports between apps.
Example: route synthesizer output → DAW input track.

You do NOT need to configure anything to use PipeWire.
Open qpwgraph only when you need manual audio routing.

============================================================
EOF

echo ""
read -rsn1 -p "Press Enter to continue..."