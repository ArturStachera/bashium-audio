#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|                SMT / HYPER-THREADING                     |
|            DSP Load Spike Optimization                   |
+----------------------------------------------------------+
EOF
echo ""

CONTROL_FILE="/sys/devices/system/cpu/smt/control"
SERVICE_FILE="/etc/systemd/system/cpu-smt.service"

echo "[1/3] Checking SMT status..."
if [ ! -f "$CONTROL_FILE" ]; then
    echo "Error: SMT control is not supported by your kernel or CPU."
    echo "This is common on older hardware or virtual machines."
    echo ""
    read -rsn1 -p "Press Enter to continue..."
    exit 0
fi

CURRENT_STATUS=$(cat "$CONTROL_FILE")
echo "Current SMT status: $CURRENT_STATUS"

ACTION="none"

if [ "$CURRENT_STATUS" = "on" ]; then
    echo ""
    echo "SMT (Hyper-threading) is currently ENABLED."
    echo "This can cause unpredictable DSP spikes in audio applications."
    echo ""
    read -p "Do you want to DISABLE SMT? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ACTION="disable"
    fi
else
    echo ""
    echo "SMT is currently DISABLED (or not 'on')."
    echo ""
    read -p "Do you want to ENABLE SMT? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ACTION="enable"
    fi
fi

echo ""
echo "[2/3] Applying changes..."

if [ "$ACTION" = "disable" ]; then
    echo "Disabling SMT..."
    echo off | sudo tee "$CONTROL_FILE" > /dev/null
    echo "Creating persistent configuration..."
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Disable CPU SMT
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo off > $CONTROL_FILE'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable cpu-smt.service 2>/dev/null || true
    echo "SMT disabled and persistent service created."
elif [ "$ACTION" = "enable" ]; then
    echo "Enabling SMT..."
    echo on | sudo tee "$CONTROL_FILE" > /dev/null
    if [ -f "$SERVICE_FILE" ]; then
        echo "Removing persistent disable service..."
        sudo systemctl disable cpu-smt.service 2>/dev/null || true
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
    fi
    echo "SMT enabled."
else
    echo "No changes made to runtime status."
    if [ "$CURRENT_STATUS" = "off" ] && [ ! -f "$SERVICE_FILE" ]; then
        read -p "SMT is off, but no persistent service found. Create one to KEEP it off? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Creating persistent configuration..."
            sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Disable CPU SMT
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo off > $CONTROL_FILE'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable cpu-smt.service 2>/dev/null || true
            echo "Persistent service created."
        fi
    fi
fi

echo ""
echo "[3/3] Verification..."
echo "Current SMT status: $(cat $CONTROL_FILE)"
if [ -f "$SERVICE_FILE" ]; then
    echo "Persistence: ENABLED (via systemd)"
else
    echo "Persistence: DISABLED"
fi
echo ""

cat <<'EOF'
+----------------------------------------------------------+
|                SMT CONFIGURED!                           |
+----------------------------------------------------------+
EOF
echo ""
echo "Note: Disabling SMT reduces the number of logical cores,"
echo "but provides more stable performance for DSP threads."
echo ""
read -rsn1 -p "Press Enter to continue..."
