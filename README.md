# BASHIUM

**BASHIUM** is a GUI-driven toolkit for turning a stock Debian installation into a fully configured audio production workstation — similar in spirit to Ubuntu Studio, but built on pure Debian.

It uses `customtkinter` to provide a clean, modern interface for running system configuration scripts, installing audio software, tuning the kernel for low-latency work, and setting up the complete PipeWire/JACK stack.

---

## Features

- **Audio production environment** — one-click setup for realtime audio, PipeWire, DAW software, plugins, and Windows VST support via Wine + yabridge
- **Full setup wizard** — runs all audio configuration steps in sequence for new installations
- **Individual module control** — configure each subsystem independently (kernel, sysctl, governor, PipeWire, etc.)
- **System configuration** — APT sources, firmware, Bluetooth, NVIDIA drivers, and more
- **Software installer** — codecs, multimedia tools, compilation toolchains, and extra packages
- **XFCE appearance** — themes, icons, and wallpapers
- **Hardware detection panel** — Wi-Fi, Bluetooth, NVIDIA, APT repo status
- **Theme/palette preset selector** — persisted per-user
- **Modern look & feel** via `customtkinter`
- **Easy to extend** — add or modify scripts under any module directory

---

## Audio Production

The audio section transforms Debian into a professional audio workstation. It can be run as a **complete setup** (recommended for fresh installs) or module-by-module.

### Modules

| Module | Directory | Description |
|--------|-----------|-------------|
| **Full Setup** | `audio/full-setup/` | Runs all audio configuration steps in sequence (realtime → kernel → sysctl → governor → PipeWire → packages) |
| **Realtime Audio** | `audio/realtime/` | Adds the user to `audio`/`realtime` groups, configures PAM limits (`rtprio 95`, `memlock unlimited`), and sets up `/dev/cpu_dma_latency` access |
| **Kernel Parameters** | `audio/kernel/` | Adds `threadirqs` and `usbcore.autosuspend=-1` to GRUB, optionally disables Spectre/Meltdown mitigations, offers RT kernel installation |
| **Sysctl Tuning** | `audio/sysctl/` | Sets `vm.swappiness=10`, raises `inotify` watch limits for sample libraries, and tunes network buffers |
| **CPU Governor** | `audio/governor/` | Locks all CPU cores to `performance` mode via a persistent systemd service |
| **PipeWire** | `audio/pipewire/` | Installs and enables the full PipeWire stack: `pipewire`, `pipewire-alsa`, `pipewire-pulse`, `pipewire-jack`, `wireplumber`, `qpwgraph` |
| **Audio Packages** | `audio/packages/` | Installs DAWs (Ardour, Audacity, Hydrogen, Mixxx), plugins (Calf, LSP, ZAM, x42, Guitarix), tools (Carla, EasyEffects, helvum), and synthesizers (ZynAddSubFX, FluidSynth) |
| **Wine + yabridge** | `audio/wine/` | Installs Wine and yabridge for running Windows VST/VST3 plugins on Linux |
| **Additional Tools** | `audio/tools/` | Extra utilities: meterbridge, aconnectgui, vkeybd, qpwgraph |
| **rtcqs Audit** | `audio/rtcqs/` | Installs the rtcqs system audit tool to verify that the system is properly configured for audio production |

### After setup

Once the full setup is complete, the system is ready for:

- **Bitwig Studio**, **Reaper**, **Ardour** — professional DAWs
- **Live recording** with low-latency PipeWire/JACK
- **Mix & master production** with LV2/LADSPA plugins
- **Windows VST plugins** via Wine + yabridge

Run `rtcqs` at any time to verify that all optimizations are active.

---

## Requirements

Install the system packages required to run the GUI and bootstrap the Python virtualenv:

```bash
sudo apt update
sudo apt install -y \
  python3 \
  python3-tk \
  python3-venv \
  curl \
  git
```

Notes:

- `curl` can be required by `pip`/build steps on minimal installs.
- Some scripts may additionally require tools like `unzip` (for XFCE themes/icons).

---

## Python dependencies

Python packages are listed in `requirements.txt` (currently: `customtkinter`).

---

## Running

### Quick start

```bash
git clone https://github.com/ArturStachera/bashium-audio.git
cd bashium-audio
chmod +x bashium.sh
./bashium.sh
```

The startup script will:

- **Create** a virtual environment under `env/` (if missing)
- **Install** Python dependencies
- **Start** the application

### Manual run (optional)

```bash
python3 -m venv env
source env/bin/activate
pip install -r requirements.txt
python3 main.py
```

---

## Folder structure

```text
bashium/
  bashium.sh
  main.py
  requirements.txt
  audio/
    full-setup/
    realtime/
    kernel/
    sysctl/
    governor/
    pipewire/
    packages/
    wine/
    tools/
    rtcqs/
  configuration/
  software/
  xfce_look/
```

---

## NVIDIA Drivers (Debian)

The NVIDIA flow is implemented in:

- `configuration/nvidia.sh`

It is intended to be run from the main GUI as a dedicated module.

### What it does

When an NVIDIA GPU is detected, the script:

- Asks whether to use the proprietary NVIDIA driver or Nouveau
- If proprietary is selected:
  - Ensures Debian `contrib non-free non-free-firmware` components are enabled
  - Installs `nvidia-detect` and picks the recommended package (including legacy packages such as `nvidia-legacy-470xx-driver` when applicable)
  - Enables `*-backports` automatically if the recommended package is not available in the current APT sources
  - Blacklists Nouveau and updates initramfs
- If Nouveau is selected:
  - Removes the Nouveau blacklist (if present)
  - Optionally purges installed `nvidia-*` packages

After changing the driver, a reboot is recommended.

### Repo and release detection

During the NVIDIA flow, BASHIUM detects:

- Debian track: `stable`, `testing`, `unstable` (based on `apt-cache policy`)
- Whether `*-backports` is already enabled
- Whether `contrib`, `non-free`, and `non-free-firmware` are present in APT sources

This is used to avoid enabling backports on `unstable` and to make the flow more robust across different Debian releases.

### Troubleshooting

- If you see messages like "Conflicting nouveau kernel module loaded" during installation, it usually means Nouveau was already loaded by the running kernel session. BASHIUM will blacklist Nouveau for the next boot, but a reboot is still required for the proprietary driver to take over.
- If you enabled `*-backports` (explicitly or implicitly) and then see dependency errors for `firmware-linux-nonfree` / `firmware-misc-nonfree`, make sure the firmware packages are installed from the same suite as the NVIDIA packages (stable vs backports). BASHIUM attempts to keep them consistent automatically.
- Boot logs showing repeated `ata` / `I/O error` messages indicate storage problems and are unrelated to GPU drivers. Check the disk/cable/port and review SMART data.

---

## GUI appearance

You can switch the UI appearance from the top bar.

The selected preset is stored in:

- `~/.config/bashium/config.json` (or `$XDG_CONFIG_HOME/bashium/config.json`)

### Palette presets (HEX colors)

The GUI uses palette presets based on HTML-like HEX codes (for example `#282828`).

The palette preset is stored in the config file under `palette_preset`.

---

## Contributing

Feel free to fork this repository and contribute via pull requests.
Any improvements, bug fixes, or suggestions are welcome!

---

## License

This project is licensed under the MIT License — see the LICENSE file for details.

---

## Author

**Artur Stachera**
