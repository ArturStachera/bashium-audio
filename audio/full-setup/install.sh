#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|         COMPLETE AUDIO PRODUCTION SETUP                |
+----------------------------------------------------------+
EOF
echo ""
echo "This will run ALL audio setup steps in sequence."
echo ""
read -rsn1 -p "Press Enter to start (or Ctrl+C to cancel)..."

echo ""
echo "==========================================="
echo "Step 1/7: Realtime Audio"
echo "==========================================="
"$(dirname "$0")/../realtime/install.sh"

echo ""
echo "==========================================="
echo "Step 2/7: Kernel Parameters"
echo "==========================================="
"$(dirname "$0")/../kernel/install.sh"

echo ""
echo "==========================================="
echo "Step 3/7: Sysctl Configuration"
echo "==========================================="
"$(dirname "$0")/../sysctl/install.sh"

echo ""
echo "==========================================="
echo "Step 4/7: CPU Governor"
echo "==========================================="
"$(dirname "$0")/../governor/install.sh"

echo ""
echo "==========================================="
echo "Step 5/7: SMT Control"
echo "==========================================="
"$(dirname "$0")/../smt/install.sh"

echo ""
echo "==========================================="
echo "Step 6/7: PipeWire"
echo "==========================================="
"$(dirname "$0")/../pipewire/install.sh"

echo ""
echo "==========================================="
echo "Step 7/7: Audio Packages"
echo "==========================================="
"$(dirname "$0")/../packages/install.sh"

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|        COMPLETE AUDIO SETUP FINISHED!                    |
+----------------------------------------------------------+
EOF
echo ""
echo "Remaining steps (optional):"
echo "  1. Restart your computer for kernel changes"
echo "  2. Run Wine+yabridge if you need Windows VST"
echo "  3. Run rtcqs to audit your system"
echo ""
echo "Your system is now configured for:"
echo "  - Bitwig Studio"
echo "  - Reaper"
echo "  - Ardour"
echo "  - VST plugins via Wine"
echo "  - Live recording"
echo "  - Mix/Master production"
echo ""
read -rsn1 -p "Press Enter to continue..."
