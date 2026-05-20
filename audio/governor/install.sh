#!/bin/bash
set -e

clear

cat <<'EOF'
+----------------------------------------------------------+
|               CPU GOVERNOR SETUP                       |
|                Performance Mode                        |
+----------------------------------------------------------+
EOF
echo ""

echo "[1/4] Installing CPU power management tools..."
sudo apt update

# cpufrequtils is deprecated in Debian; use cpupower from linux-tools
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
sudo apt install -y linux-cpupower || sudo apt install -y cpupower || true

echo ""
echo "[2/4] Configuring CPU governor..."

# Check if performance governor is available and set it directly via sysfs
PERF_AVAILABLE=false
for gov in /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors; do
    if [ -f "$gov" ] && grep -q "performance" "$gov" 2>/dev/null; then
        PERF_AVAILABLE=true
        break
    fi
done

if [ "$PERF_AVAILABLE" = true ]; then
    echo "Setting performance governor on all CPUs..."
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ] && [ -w "$cpu" ]; then
            echo "performance" | sudo tee "$cpu" > /dev/null 2>/dev/null || true
        fi
    done
    echo "Performance governor set."
else
    echo "Warning: 'performance' governor not available on this system."
fi

echo ""
echo "[3/4] Creating persistent configuration..."

# Create systemd service to set governor at boot
if [ ! -f /etc/systemd/system/cpu-performance.service ]; then
    sudo tee /etc/systemd/system/cpu-performance.service > /dev/null << 'EOF'
[Unit]
Description=Set CPU Governor to Performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do if [ -f \"$cpu\" ]; then echo performance > \"$cpu\"; fi; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable cpu-performance.service 2>/dev/null || true
    sudo systemctl start cpu-performance.service 2>/dev/null || true
    echo "Persistent configuration created."
else
    echo "Performance service already exists."
fi

echo ""
echo "[4/4] Verification..."
echo "Current CPU governor settings:"
echo "----------------------------------------"
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -f "$cpu" ]; then
        echo "$(basename $(dirname $cpu)): $(cat $cpu)"
    fi
done
echo "----------------------------------------"

echo ""
cat <<'EOF'
+----------------------------------------------------------+
|              CPU GOVERNOR CONFIGURED!                    |
+----------------------------------------------------------+
EOF
echo ""
echo "All CPU cores set to 'performance' mode."
echo "This ensures consistent CPU frequency for minimal"
echo "latency."
echo ""
read -rsn1 -p "Press Enter to continue..."
