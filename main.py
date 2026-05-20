import customtkinter as ctk
import tkinter as tk
from pathlib import Path
import subprocess
import shutil
import shlex
import json
import os
import re
import traceback
import random
import math
from datetime import datetime
from typing import Optional

# Konfiguracja CustomTkinter
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

CONFIG_DESCRIPTION = (
    "System tweaks: Wi-Fi firmware, Bluetooth, export /sbin to PATH, disable PC speaker beep.\n"
    "Auto-detects hardware and prompts for installation when relevant devices are found."
)

XFCE_LOOK_DESCRIPTION = (
    "Install XFCE themes, wallpapers, and icons.\n"
    "The script asks for username and installs resources in user folders."
)

SOFTWARE_DESCRIPTION = "Codecs, multimedia, compilation and extra software scripts."

AUDIO_DESCRIPTION = "Complete audio production environment setup. Realtime audio, PipeWire, DAW, plugins."

AUDIO_CATEGORY_DESCRIPTIONS = {
    "full-setup": "Complete setup: runs all audio configuration steps in sequence. Recommended for new setups.",
    "realtime": "Realtime audio priorities: adds user to audio/realtime groups and configures RT privileges.",
    "kernel": "Kernel parameters: threadirqs and USB autosuspend for low-latency audio.",
    "sysctl": "Sysctl tuning: memory, swap, and file watcher limits for audio production.",
    "governor": "CPU Performance: sets CPU governor to performance mode for consistent processing.",
    "pipewire": "PipeWire stack: modern audio server with JACK/PulseAudio compatibility.",
    "packages": "Audio packages: DAW (Ardour), plugins, synthesizers - Ubuntu Studio style.",
    "wine": "Wine + yabridge: run Windows VST plugins on Linux.",
    "rtcqs": "rtcqs audit: verify system is optimized for audio production.",
    "tools": "Additional tools: meters, extra JACK utilities, virtual MIDI keyboard.",
}

# ── Ikony modułów głównych ──────────────────────────────────────────────────
MODULE_ICONS = {
    "Configuration": "⚙",
    "NVIDIA": "◈",
    "Xfce Look": "◉",
    "Software": "◆",
}

# ── Ikony kategorii audio ──────────────────────────────────────────────────
AUDIO_CATEGORY_ICONS = {
    "full-setup": "♬",
    "realtime": "⚡",
    "kernel": "◈",
    "sysctl": "⊞",
    "governor": "▲",
    "pipewire": "♪",
    "packages": "♫",
    "wine": "◊",
    "rtcqs": "⊙",
    "tools": "✦",
}

# ── Dekoracyjny pasek fali ─────────────────────────────────────────────────
WAVE_CHARS = "▁▂▃▄▅▆▇█▇▆▅▄▃▂▁"


def _safe_check_output(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""


def _log_exception(context: str, exc: BaseException) -> None:
    try:
        cfg_dir = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "bashium"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        log_path = cfg_dir / "bashium.log"
        with log_path.open("a", encoding="utf-8") as f:
            f.write(f"\n[{datetime.now().isoformat(timespec='seconds')}] {context}\n")
            f.write("".join(traceback.format_exception(type(exc), exc, exc.__traceback__)))
    except Exception:
        return


def detect_nvidia_gpu() -> bool:
    out = _safe_check_output(["lspci", "-nn"])
    return "nvidia" in out.lower()


def detect_nvidia_arch() -> str:
    """Detect NVIDIA GPU architecture from PCI device IDs (mirrors nvidia.sh logic)."""
    out = _safe_check_output(["lspci", "-nn"])
    if not out:
        return "unknown"

    ids = re.findall(r'10[Dd][Ee]:([0-9a-f]{4})', out)

    if not ids:
        return "unknown"

    dev_id = int(ids[0], 16)

    if dev_id >= 0x2680:
        return "Ada Lovelace"
    if 0x2200 <= dev_id < 0x2680:
        return "Ampere"
    if 0x1E00 <= dev_id < 0x2200:
        return "Turing"
    if 0x1D81 <= dev_id <= 0x1DFF:
        return "Volta"
    if 0x1B00 <= dev_id <= 0x1D80 or 0x15F0 <= dev_id <= 0x15FF:
        return "Pascal"
    if 0x1340 <= dev_id <= 0x17FF:
        return "Maxwell"
    if 0x0FC0 <= dev_id <= 0x133F:
        return "Kepler"
    if dev_id < 0x0FC0:
        return "Fermi or older"

    return "unknown"


def detect_bluetooth_controller() -> bool:
    out_rfkill = _safe_check_output(["rfkill", "list"])
    if "bluetooth" in out_rfkill.lower():
        return True

    out_lspci = _safe_check_output(["lspci"])
    if "bluetooth" in out_lspci.lower():
        return True

    out_lsusb = _safe_check_output(["lsusb"])
    if "bluetooth" in out_lsusb.lower():
        return True

    try:
        entries = os.listdir("/sys/class/bluetooth")
        return any(e.startswith("hci") for e in entries)
    except Exception:
        return False


def detect_wifi_vendors() -> set[str]:
    hw = "\n".join(
        [
            _safe_check_output(["lspci", "-nn"]),
            _safe_check_output(["lsusb"]),
        ]
    ).lower()

    vendors: set[str] = set()
    if not hw.strip():
        return vendors

    lines = hw.splitlines()
    filtered_lines = [
        line for line in lines
        if not any(x in line for x in ["ethernet", "gigabit", "10-gigabit", "1000base", "wired"])
    ]

    for line in filtered_lines:
        if any(x in line for x in ["wireless", "wi-fi", "802.11"]):
            if any(x in line for x in ["intel", "8086:"]):
                vendors.add("Intel")
            if any(x in line for x in ["broadcom", "bcm", "14e4:"]):
                vendors.add("Broadcom")
            if any(x in line for x in ["realtek", "rtl", "10ec:", "0bda:"]):
                vendors.add("Realtek")
            if any(x in line for x in ["atheros", "qualcomm", "168c:", "0cf3:"]):
                vendors.add("Atheros/Qualcomm")
            if any(x in line for x in ["mediatek", "mediatk", "mtk", "14c3:", "0e8d:"]):
                vendors.add("MediaTek")
            if any(x in line for x in ["ralink", "148f:"]):
                vendors.add("Ralink")

    return vendors


def detect_usb_devices_summary() -> str:
    out = _safe_check_output(["lsusb"]).strip()
    if not out:
        return "USB: unknown"
    lines = [ln for ln in out.splitlines() if ln.strip()]
    return f"USB: {len(lines)} device(s)"


def has_nonfree_enabled() -> bool:
    cmd = ["bash", "-lc", "grep -Rqs -- 'non-free' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null"]
    try:
        return subprocess.run(cmd, check=False).returncode == 0
    except Exception:
        return False


# ══════════════════════════════════════════════════════════════════════════════
#  Animowany equalizer (Canvas)
# ══════════════════════════════════════════════════════════════════════════════

class WaveformWidget(ctk.CTkFrame):
    """Animowany equalizer audio — pulsujące słupki EQ."""

    def __init__(self, master, colors: dict, width: int = 210, height: int = 38,
                 n_bars: int = 20, **kwargs):
        super().__init__(master, fg_color="transparent",
                         width=width, height=height, **kwargs)
        self.colors = colors
        self.w = width
        self.h = height
        self.n_bars = n_bars
        self._running = True

        # Losowe fazy i prędkości dla naturalnego wyglądu
        self._phase  = [random.uniform(0, 2 * math.pi) for _ in range(n_bars)]
        self._speed  = [random.uniform(0.04, 0.14)     for _ in range(n_bars)]
        self._base_h = [random.uniform(0.12, 0.58)     for _ in range(n_bars)]
        self._amp    = [random.uniform(0.10, 0.38)      for _ in range(n_bars)]

        self.canvas = tk.Canvas(
            self,
            width=width,
            height=height,
            bg=colors.get("card_bg", "#0b2a33"),
            highlightthickness=0,
            bd=0,
        )
        self.canvas.pack()
        self._animate()

    # ── animacja ──────────────────────────────────────────────────────────
    def _animate(self):
        if not self._running:
            return
        self.canvas.delete("all")

        accent  = self.colors.get("accent",  "#00f5ff")
        success = self.colors.get("success", "#00ff9f")
        muted   = self.colors.get("muted",   "#5b7a83")

        bar_w = max(2, (self.w - (self.n_bars + 1)) // self.n_bars)
        gap   = max(1, (self.w - self.n_bars * bar_w) // (self.n_bars + 1))

        for i in range(self.n_bars):
            self._phase[i] += self._speed[i]
            raw  = self._base_h[i] + self._amp[i] * math.sin(self._phase[i])
            norm = max(0.04, min(0.96, raw))
            bh   = int(norm * self.h)

            x1 = gap + i * (bar_w + gap)
            x2 = x1 + bar_w
            y1 = self.h - bh
            y2 = self.h

            # Kolor słupka zależy od wysokości
            if norm > 0.70:
                color = accent
            elif norm > 0.35:
                color = success
            else:
                color = muted

            # Słupek główny
            self.canvas.create_rectangle(x1, y1, x2, y2, fill=color, outline="")
            # Biały piksel na szczycie
            if bh > 3:
                self.canvas.create_rectangle(x1, y1, x2, y1 + 2,
                                             fill="#ffffff", outline="")

        self.after(55, self._animate)

    def stop(self):
        self._running = False

    def update_colors(self, colors: dict):
        self.colors = colors
        self.canvas.configure(bg=colors.get("card_bg", "#0b2a33"))


# ══════════════════════════════════════════════════════════════════════════════
#  ScriptModule
# ══════════════════════════════════════════════════════════════════════════════

class ScriptModule:
    def __init__(self, name: str, script_path: Path, description: str, enabled: bool = True):
        self.name = name
        self.script_path = script_path
        self.description = description
        self.enabled = enabled

    def _build_shell_command(self) -> str:
        if self.script_path.is_dir():
            script_dir = shlex.quote(str(self.script_path))
            return f"cd {script_dir} && ./install.sh; exec bash"

        script_dir  = shlex.quote(str(self.script_path.parent))
        script_name = shlex.quote(str(self.script_path.name))
        return f"cd {script_dir} && bash ./{script_name}; exec bash"

    def _find_terminal(self) -> tuple[list[str] | None, str]:
        shell_cmd = self._build_shell_command()
        human_cmd = f"bash -lc {shlex.quote(shell_cmd)}"

        candidates = [
            "x-terminal-emulator",
            "gnome-terminal",
            "kgx",
            "konsole",
            "xfce4-terminal",
            "mate-terminal",
            "tilix",
            "alacritty",
            "kitty",
            "lxterminal",
            "xterm",
        ]

        term = None
        for c in candidates:
            if shutil.which(c):
                term = c
                break

        if term is None:
            return None, human_cmd

        if term in {"gnome-terminal", "mate-terminal"}:
            return [term, "--", "bash", "-lc", shell_cmd], human_cmd
        if term == "kgx":
            return [term, "--", "bash", "-lc", shell_cmd], human_cmd
        if term == "konsole":
            return [term, "-e", "bash", "-lc", shell_cmd], human_cmd
        if term == "xfce4-terminal":
            return [term, "--command", f"bash -lc {shlex.quote(shell_cmd)}"], human_cmd
        if term == "tilix":
            return [term, "-e", f"bash -lc {shlex.quote(shell_cmd)}"], human_cmd
        if term in {"alacritty", "kitty", "lxterminal", "xterm", "x-terminal-emulator"}:
            return [term, "-e", "bash", "-lc", shell_cmd], human_cmd

        return [term, "-e", "bash", "-lc", shell_cmd], human_cmd

    def run(self) -> None:
        argv, human_cmd = self._find_terminal()
        if argv is None:
            raise RuntimeError(
                "No supported terminal emulator found. "
                "Install one of: gnome-terminal, konsole, xfce4-terminal, xterm. "
                f"You can run this manually: {human_cmd}"
            )

        try:
            subprocess.Popen(argv)
        except Exception as e:
            raise RuntimeError(f"Failed to launch terminal: {e}. Command: {' '.join(argv)}")


# ══════════════════════════════════════════════════════════════════════════════
#  ModuleCard  —  karta modułu z ikoną muzyczną
# ══════════════════════════════════════════════════════════════════════════════

class ModuleCard(ctk.CTkFrame):
    """Nowoczesna karta modułu z ikoną i animacją hover."""

    def __init__(self, master, module: ScriptModule, colors: dict, **kwargs):
        super().__init__(master, **kwargs)
        self.module = module
        self.colors = colors

        self.configure(
            fg_color=colors["card_bg"],
            corner_radius=12,
            border_width=2,
            border_color=colors["border"]
        )

        self.grid_columnconfigure(0, weight=1)
        self.grid_rowconfigure(1, weight=1)

        # ── Header z ikoną i nazwą ────────────────────────────────────────
        header_frame = ctk.CTkFrame(self, fg_color="transparent")
        header_frame.grid(row=0, column=0, sticky="ew", padx=20, pady=(15, 5))

        # Ikona modułu
        icon_text = MODULE_ICONS.get(module.name, "▶")
        icon_label = ctk.CTkLabel(
            header_frame,
            text=icon_text,
            font=ctk.CTkFont(size=24),
            text_color=colors["accent"],
        )
        icon_label.pack(side="left")

        name_label = ctk.CTkLabel(
            header_frame,
            text=module.name,
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color=colors["accent"],
        )
        name_label.pack(side="left", padx=(10, 0))

        # Status indicator
        status_color = colors["success"] if module.enabled else colors["muted"]
        status_dot = ctk.CTkLabel(
            header_frame,
            text="●",
            font=ctk.CTkFont(size=14),
            text_color=status_color,
        )
        status_dot.pack(side="left", padx=(10, 0))

        # ── Opis ─────────────────────────────────────────────────────────
        desc_label = ctk.CTkLabel(
            self,
            text=module.description,
            font=ctk.CTkFont(size=12),
            text_color=colors["fg"],
            anchor="w",
            justify="left",
            wraplength=500,
        )
        desc_label.grid(row=1, column=0, sticky="nsew", padx=20, pady=(0, 15))

        # ── Przycisk RUN ─────────────────────────────────────────────────
        self.run_button = ctk.CTkButton(
            self,
            text="▶  RUN SCRIPT",
            command=self._run_with_dialog,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color=colors["accent"],
            hover_color=colors["accent_hover"],
            text_color="#000000" if module.enabled else "#404040",
            corner_radius=8,
            height=40,
            state="normal" if module.enabled else "disabled",
        )
        self.run_button.grid(row=2, column=0, sticky="ew", padx=20, pady=(0, 15))

        # Bind hover to card AND all children — prevents flicker when mouse
        # crosses into a child widget (tkinter fires Leave on parent otherwise)
        self._bind_hover_recursive(self)

    def _bind_hover_recursive(self, widget):
        widget.bind("<Enter>", self._on_hover, add="+")
        widget.bind("<Leave>", self._on_leave, add="+")
        for child in widget.winfo_children():
            self._bind_hover_recursive(child)

    def _is_descendant(self, widget) -> bool:
        """Return True if widget is self or any child of self."""
        try:
            w = widget
            while w is not None:
                if w == self:
                    return True
                w = w.master
        except Exception:
            pass
        return False

    def _on_hover(self, event):
        if self.module.enabled:
            self.configure(border_color=self.colors["accent"])

    def _on_leave(self, event):
        # Only remove highlight when the cursor has truly left the card area.
        # winfo_containing gives us the widget currently under the pointer;
        # if it's still inside this card we do nothing.
        widget_under = self.winfo_containing(event.x_root, event.y_root)
        if self._is_descendant(widget_under):
            return
        self.configure(border_color=self.colors["border"])

    def _run_with_dialog(self):
        try:
            dialog = ctk.CTkToplevel(self)
            dialog.title("Confirm Execution")
            dialog.geometry("400x200")
            dialog.transient(self.master)
            dialog.bind("<Escape>", lambda _e: dialog.destroy())

            dialog.update_idletasks()
            x = (dialog.winfo_screenwidth() // 2) - (400 // 2)
            y = (dialog.winfo_screenheight() // 2) - (200 // 2)
            dialog.geometry(f"400x200+{x}+{y}")

            try:
                ctk.CTkLabel(
                    dialog,
                    text=f"Run {self.module.name}?",
                    font=ctk.CTkFont(size=16, weight="bold"),
                ).pack(pady=(20, 10))

                ctk.CTkLabel(
                    dialog,
                    text="This will execute the script in a terminal window.",
                    font=ctk.CTkFont(size=12),
                    text_color="gray",
                ).pack(pady=(0, 20))

                button_frame = ctk.CTkFrame(dialog, fg_color="transparent")
                button_frame.pack(pady=10)
            except Exception as e:
                _log_exception("Failed to build confirm dialog UI", e)
                ctk.CTkLabel(
                    dialog,
                    text="Dialog error. Please close this window and check ~/.config/bashium/bashium.log",
                    font=ctk.CTkFont(size=13),
                    wraplength=360,
                    justify="left",
                ).pack(pady=20, padx=20)
                ctk.CTkButton(dialog, text="Close", command=dialog.destroy, width=120).pack(pady=10)
                return

            def confirm():
                dialog.destroy()
                try:
                    self.module.run()
                except Exception as e:
                    _log_exception("Failed to launch script terminal", e)
                    try:
                        err = ctk.CTkToplevel(self)
                        err.title("Execution error")
                        err.geometry("620x260")
                        err.transient(self.master)
                        err.bind("<Escape>", lambda _e: err.destroy())

                        err.update_idletasks()
                        x = (err.winfo_screenwidth() // 2) - (620 // 2)
                        y = (err.winfo_screenheight() // 2) - (260 // 2)
                        err.geometry(f"620x260+{x}+{y}")

                        ctk.CTkLabel(
                            err,
                            text="Could not launch the terminal to run the script.",
                            font=ctk.CTkFont(size=16, weight="bold"),
                        ).pack(pady=(20, 10), padx=20, anchor="w")

                        textbox = ctk.CTkTextbox(err, height=120)
                        textbox.pack(fill="both", expand=True, padx=20, pady=(0, 10))
                        textbox.insert("1.0", str(e))
                        textbox.configure(state="disabled")

                        ctk.CTkButton(err, text="Close", command=err.destroy, width=120).pack(pady=(0, 20))
                    except Exception as dialog_err:
                        _log_exception("Failed to show execution error dialog", dialog_err)

            ctk.CTkButton(
                button_frame,
                text="Execute",
                command=confirm,
                fg_color=self.colors["success"],
                hover_color=self.colors["success_hover"],
                width=120,
            ).pack(side="left", padx=5)

            ctk.CTkButton(
                button_frame,
                text="Cancel",
                command=dialog.destroy,
                fg_color="gray40",
                hover_color="gray30",
                width=120,
            ).pack(side="left", padx=5)
        except Exception as e:
            _log_exception("Unhandled error in _run_with_dialog", e)


# ══════════════════════════════════════════════════════════════════════════════
#  AudioProductionWindow  —  okno z kategorystami audio
# ══════════════════════════════════════════════════════════════════════════════

class AudioProductionWindow(ctk.CTkToplevel):
    """Window with compact expandable audio setup categories."""

    def __init__(self, master, colors: dict, base_dir: Path):
        super().__init__(master)
        self.colors = colors
        self.base_dir = base_dir
        self._waveform: Optional[WaveformWidget] = None

        self.title("Audio Production Studio")
        self.geometry("700x530")
        self.transient(master)
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.bind("<Escape>", lambda _e: self._on_close())

        self.update_idletasks()
        self.deiconify()
        self.lift()
        self.focus_force()
        x = (self.winfo_screenwidth() // 2) - (700 // 2)
        y = (self.winfo_screenheight() // 2) - (530 // 2)
        self.geometry(f"700x530+{x}+{y}")

        self.row_widgets = []
        self.expanded_row = None

        self.setup_ui()

    def _on_close(self):
        if self._waveform:
            self._waveform.stop()
        self.destroy()

    def setup_ui(self):
        # ── Header ────────────────────────────────────────────────────────
        header_bg = ctk.CTkFrame(
            self,
            fg_color=self.colors["card_bg"],
            corner_radius=0,
        )
        header_bg.pack(fill="x")

        header_frame = ctk.CTkFrame(header_bg, fg_color="transparent")
        header_frame.pack(fill="x", padx=20, pady=12)

        # Ikona + tytuł
        title_icon = ctk.CTkLabel(
            header_frame,
            text="♬",
            font=ctk.CTkFont(size=28),
            text_color=self.colors["accent"],
        )
        title_icon.pack(side="left")

        title_label = ctk.CTkLabel(
            header_frame,
            text="  Audio Production Studio",
            font=ctk.CTkFont(size=22, weight="bold"),
            text_color=self.colors["accent"],
        )
        title_label.pack(side="left")

        subtitle = ctk.CTkLabel(
            header_frame,
            text="hover for details",
            font=ctk.CTkFont(size=10),
            text_color=self.colors["fg_secondary"],
        )
        subtitle.pack(side="left", padx=(12, 0))

        # Waveform po prawej stronie headera
        waveform_container = ctk.CTkFrame(
            header_frame,
            fg_color=self.colors["bg"],
            corner_radius=6,
            border_width=1,
            border_color=self.colors["border"],
        )
        waveform_container.pack(side="right")

        self._waveform = WaveformWidget(
            waveform_container,
            self.colors,
            width=180,
            height=32,
            n_bars=16,
        )
        self._waveform.pack(padx=4, pady=4)

        # ── Info box ───────────────────────────────────────────────────────
        info_frame = ctk.CTkFrame(self, fg_color=self.colors["card_bg"], corner_radius=0)
        info_frame.pack(fill="x")

        info_text = (
            "♩  Install in order:  1) Realtime  →  2) Kernel / Sysctl / Governor  "
            "→  3) PipeWire  →  4) Packages  →  5) Wine (optional)  →  6) rtcqs (audit)"
        )
        ctk.CTkLabel(
            info_frame,
            text=info_text,
            font=ctk.CTkFont(size=10),
            text_color=self.colors["fg_secondary"],
            wraplength=660,
            justify="left",
        ).pack(padx=16, pady=8)

        # Separator
        sep = ctk.CTkFrame(self, fg_color=self.colors["border"], height=1, corner_radius=0)
        sep.pack(fill="x")

        # ── Scrollable lista kategorii ─────────────────────────────────────
        scroll_frame = ctk.CTkScrollableFrame(
            self,
            fg_color="transparent",
            corner_radius=0,
        )
        scroll_frame.pack(fill="both", expand=True, padx=15, pady=(10, 0))

        self.categories = [
            ("full-setup", "Complete Setup",    True),
            ("realtime",   "Realtime Audio",    True),
            ("kernel",     "Kernel Parameters", True),
            ("sysctl",     "Sysctl Tuning",     True),
            ("governor",   "CPU Performance",   True),
            ("pipewire",   "PipeWire Stack",    True),
            ("packages",   "Audio Packages",    True),
            ("wine",       "Wine + yabridge",   True),
            ("tools",      "Additional Tools",  True),
            ("rtcqs",      "System Audit",      True),
        ]

        self.button_items = []
        for i in range(0, len(self.categories), 2):
            self._create_row(scroll_frame, i)

        # ── Panel opisu (na dole) ──────────────────────────────────────────
        self.desc_panel = ctk.CTkFrame(
            self,
            fg_color=self.colors["card_bg"],
            corner_radius=8,
        )
        self.desc_panel.pack(fill="x", padx=15, pady=(6, 6))
        self.desc_panel.pack_propagate(False)
        self.desc_panel.configure(height=62)

        self.desc_label = ctk.CTkLabel(
            self.desc_panel,
            text="♪  Hover over a button to see description",
            font=ctk.CTkFont(size=11),
            text_color=self.colors["fg_secondary"],
            wraplength=650,
            justify="left",
        )
        self.desc_label.pack(padx=15, pady=10)

        # ── Przycisk zamknięcia ────────────────────────────────────────────
        btn_frame = ctk.CTkFrame(self, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=(0, 12))

        ctk.CTkButton(
            btn_frame,
            text="✕  Close",
            command=self._on_close,
            font=ctk.CTkFont(size=12),
            fg_color=self.colors["muted"],
            hover_color=self.colors["border"],
            width=110,
            height=32,
        ).pack(side="right")

    def _create_row(self, master, start_idx):
        row_frame = ctk.CTkFrame(master, fg_color="transparent")
        row_frame.pack(fill="x", pady=3)

        for i in range(2):
            idx = start_idx + i
            if idx < len(self.categories):
                cat_id, cat_name, enabled = self.categories[idx]
                item = self._create_compact_item(row_frame, cat_id, cat_name, enabled, idx)
                self.button_items.append(item)
            else:
                placeholder = ctk.CTkFrame(row_frame, fg_color="transparent", width=315, height=48)
                placeholder.pack(side="left", padx=5)

    def _create_compact_item(self, master, cat_id: str, cat_name: str, enabled: bool, idx: int):
        script_path = self.base_dir / "audio" / cat_id / "install.sh"
        module = ScriptModule(cat_name, script_path, "", enabled=enabled and script_path.exists())

        container = ctk.CTkFrame(
            master,
            fg_color=self.colors["card_bg"],
            corner_radius=8,
            width=315,
            height=48,
        )
        container.pack(side="left", padx=5)
        container.pack_propagate(False)
        container.configure(border_width=1, border_color=self.colors["border"])

        btn_frame = ctk.CTkFrame(container, fg_color="transparent")
        btn_frame.place(relx=0.5, rely=0.5, anchor="center", relwidth=0.92, relheight=0.80)

        # Status dot
        status_color = self.colors["success"] if (enabled and script_path.exists()) else self.colors["muted"]
        status_dot = ctk.CTkLabel(
            btn_frame,
            text="●",
            font=ctk.CTkFont(size=10),
            text_color=status_color,
        )
        status_dot.place(relx=0.0, rely=0.5, anchor="w")

        # Ikona kategorii + nazwa
        icon = AUDIO_CATEGORY_ICONS.get(cat_id, "♪")
        name_label = ctk.CTkLabel(
            btn_frame,
            text=f"  {icon}  {cat_name}",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color=self.colors["accent"],
        )
        name_label.place(relx=0.06, rely=0.5, anchor="w")

        # Przycisk Run
        run_btn = ctk.CTkButton(
            btn_frame,
            text="Run",
            command=lambda: self._run_category_script(module),
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color=self.colors["accent"],
            hover_color=self.colors["accent"],
            text_color="#000000",
            corner_radius=5,
            width=58,
            height=26,
            state="normal" if (enabled and script_path.exists()) else "disabled",
        )
        run_btn.place(relx=0.98, rely=0.5, anchor="e")

        cat_id_real = self.categories[idx][0]
        desc = AUDIO_CATEGORY_DESCRIPTIONS.get(cat_id_real, "")

        item_data = {
            "container": container,
            "run_btn":   run_btn,
            "name_label": name_label,
            "cat_id":    cat_id_real,
            "cat_name":  cat_name,
            "description": desc,
        }

        def on_enter(e, it=item_data):
            if getattr(self, "_current_hover", None) != it:
                self._current_hover = it
                self._on_button_enter(it)

        def on_leave(e, it=item_data):
            if getattr(self, "_current_hover", None) == it:
                self._current_hover = None
                self._on_button_leave(it)

        for widget in [container, btn_frame, status_dot, name_label, run_btn]:
            widget.bind("<Enter>", on_enter)
            widget.bind("<Leave>", on_leave)

        return item_data

    def _on_button_enter(self, item_data):
        item_data["container"].configure(border_color=self.colors["accent"], border_width=2)
        icon = AUDIO_CATEGORY_ICONS.get(item_data["cat_id"], "♪")
        self.desc_label.configure(
            text=f"{icon}  {item_data['cat_name']}: {item_data['description']}",
            text_color=self.colors["fg"],
        )

    def _on_button_leave(self, item_data):
        item_data["container"].configure(border_color=self.colors["border"], border_width=1)
        self.desc_label.configure(
            text="♪  Hover over a button to see description",
            text_color=self.colors["fg_secondary"],
        )

    def _run_category_script(self, module: ScriptModule):
        try:
            dialog = ctk.CTkToplevel(self)
            dialog.title("Confirm Execution")
            dialog.geometry("400x180")
            dialog.transient(self)
            dialog.bind("<Escape>", lambda _e: dialog.destroy())

            dialog.update_idletasks()
            dialog.deiconify()
            dialog.lift()
            x = (dialog.winfo_screenwidth() // 2) - (400 // 2)
            y = (dialog.winfo_screenheight() // 2) - (180 // 2)
            dialog.geometry(f"400x180+{x}+{y}")

            ctk.CTkLabel(
                dialog,
                text=f"Run {module.name}?",
                font=ctk.CTkFont(size=16, weight="bold"),
            ).pack(pady=(20, 10))

            ctk.CTkLabel(
                dialog,
                text="Execute setup script in terminal?",
                font=ctk.CTkFont(size=11),
                text_color="gray",
            ).pack(pady=(0, 20))

            button_frame = ctk.CTkFrame(dialog, fg_color="transparent")
            button_frame.pack(pady=10)

            def confirm():
                dialog.destroy()
                try:
                    module.run()
                except Exception as e:
                    _log_exception("Failed to launch script terminal", e)

            ctk.CTkButton(
                button_frame,
                text="Execute",
                command=confirm,
                fg_color=self.colors["success"],
                hover_color=self.colors["success_hover"],
                width=100,
                height=30,
            ).pack(side="left", padx=5)

            ctk.CTkButton(
                button_frame,
                text="Cancel",
                command=dialog.destroy,
                fg_color="gray40",
                hover_color="gray30",
                width=100,
                height=30,
            ).pack(side="left", padx=5)

        except Exception as e:
            _log_exception("Failed to show category confirm dialog", e)


# ══════════════════════════════════════════════════════════════════════════════
#  BashiumApp  —  główne okno aplikacji
# ══════════════════════════════════════════════════════════════════════════════

class BashiumApp:
    PALETTES = {
        # ── Oryginalne ──────────────────────────────────────────────────────
        "Gruvbox Dark": {
            "bg": "#282828",
            "fg": "#ebdbb2",
            "fg_secondary": "#bdae93",
            "accent": "#fabd2f",
            "accent_hover": "#d79921",
            "card_bg": "#3c3836",
            "border": "#504945",
            "muted": "#7c6f64",
            "success": "#b8bb26",
            "success_hover": "#98971a",
        },
        "Gruvbox Light": {
            "bg": "#fbf1c7",
            "fg": "#3c3836",
            "fg_secondary": "#665c54",
            "accent": "#d79921",
            "accent_hover": "#b57614",
            "card_bg": "#f2e5bc",
            "border": "#d5c4a1",
            "muted": "#7c6f64",
            "success": "#98971a",
            "success_hover": "#79740e",
        },
        "Tokyo Night": {
            "bg": "#1a1b26",
            "fg": "#c0caf5",
            "fg_secondary": "#9aa5ce",
            "accent": "#7aa2f7",
            "accent_hover": "#5a82d7",
            "card_bg": "#24283b",
            "border": "#414868",
            "muted": "#565f89",
            "success": "#9ece6a",
            "success_hover": "#7ea84a",
        },
        "Cyberpunk": {
            "bg": "#0b0f1a",
            "fg": "#e6e6e6",
            "fg_secondary": "#b0b0b0",
            "accent": "#ff2a6d",
            "accent_hover": "#df0a4d",
            "card_bg": "#1b1f36",
            "border": "#2b2f46",
            "muted": "#6b6f86",
            "success": "#05ffa1",
            "success_hover": "#00df81",
        },
        "Neon Cyan": {
            "bg": "#07161b",
            "fg": "#d7f9ff",
            "fg_secondary": "#a0c9d1",
            "accent": "#00f5ff",
            "accent_hover": "#00d5df",
            "card_bg": "#0b2a33",
            "border": "#1b3a43",
            "muted": "#5b7a83",
            "success": "#00ff9f",
            "success_hover": "#00df7f",
        },
        # ── Nowe motywy audio ────────────────────────────────────────────────
        "Studio Dark": {
            # Głęboka fioletowo-purpurowa — jak wnętrze studia nagrań
            "bg": "#0d0a1e",
            "fg": "#e8e0ff",
            "fg_secondary": "#a89bc2",
            "accent": "#b084ff",
            "accent_hover": "#9060df",
            "card_bg": "#1a1530",
            "border": "#2d2545",
            "muted": "#5a4f7a",
            "success": "#7bed9f",
            "success_hover": "#5bcd7f",
        },
        "Midnight Jazz": {
            # Ciemny, ciepły — klimat jazzowego klubu o północy
            "bg": "#0a0c12",
            "fg": "#f5e6c8",
            "fg_secondary": "#c9a87a",
            "accent": "#f0a030",
            "accent_hover": "#d08010",
            "card_bg": "#14161e",
            "border": "#2a2535",
            "muted": "#6a5a3a",
            "success": "#50e080",
            "success_hover": "#30c060",
        },
        "Synthwave": {
            # Retro-futurystyczny róż i fiolet — lata 80., analogi
            "bg": "#0f0520",
            "fg": "#ffccee",
            "fg_secondary": "#cc88bb",
            "accent": "#ff44aa",
            "accent_hover": "#df2490",
            "card_bg": "#1a0a35",
            "border": "#3a1555",
            "muted": "#6a3a7a",
            "success": "#44ffcc",
            "success_hover": "#24dfaa",
        },
    }

    def __init__(self, root: ctk.CTk, modules: list[ScriptModule], hw_info: dict):
        self.root = root
        self.modules = modules
        self.hw_info = hw_info
        self.config_path = (
            Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
            / "bashium" / "config.json"
        )
        self.module_cards: list[ModuleCard] = []
        self.waveform: Optional[WaveformWidget] = None

        self.setup_window()
        self.setup_ui()

        saved_palette = self._load_palette_preset()
        self.palette_var.set(saved_palette)
        self._apply_palette()

        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

    def _on_close(self):
        if self.waveform:
            self.waveform.stop()
        self.root.destroy()

    def setup_window(self):
        self.root.title("BASHIUM-AUDIO — System Tweaker & Audio Setup")
        self.root.geometry("1000x720")
        self.root.minsize(900, 620)

        self.root.update_idletasks()
        x = (self.root.winfo_screenwidth()  // 2) - (1000 // 2)
        y = (self.root.winfo_screenheight() // 2) - (720 // 2)
        self.root.geometry(f"1000x720+{x}+{y}")

    def setup_ui(self):
        colors = self._get_current_colors()

        # ── Main container ────────────────────────────────────────────────
        main_frame = ctk.CTkFrame(self.root, fg_color="transparent")
        main_frame.pack(fill="both", expand=True, padx=20, pady=20)

        # ── Header ────────────────────────────────────────────────────────
        header_frame = ctk.CTkFrame(main_frame, fg_color="transparent")
        header_frame.pack(fill="x", pady=(0, 16))

        # Title block: BASHIUM-AUDIO on top, subtitle below
        title_block = ctk.CTkFrame(header_frame, fg_color="transparent")
        title_block.pack(side="left")

        self.title_label = ctk.CTkLabel(
            title_block,
            text="⚡ BASHIUM-AUDIO",
            font=ctk.CTkFont(size=32, weight="bold"),
        )
        self.title_label.pack(anchor="w")

        self.subtitle_label = ctk.CTkLabel(
            title_block,
            text="System Tweaker  ❖  Audio Setup",
            font=ctk.CTkFont(size=12),
        )
        self.subtitle_label.pack(anchor="w")

        # Animowany equalizer w headerze
        eq_container = ctk.CTkFrame(
            header_frame,
            fg_color=colors["card_bg"],
            corner_radius=8,
            border_width=1,
            border_color=colors["border"],
        )
        eq_container.pack(side="left", padx=(22, 0))

        self.waveform = WaveformWidget(
            eq_container,
            colors,
            width=210,
            height=38,
            n_bars=20,
        )
        self.waveform.pack(padx=5, pady=5)

        # Theme selector
        self.palette_var = ctk.StringVar()
        theme_menu = ctk.CTkOptionMenu(
            header_frame,
            values=list(self.PALETTES.keys()),
            variable=self.palette_var,
            command=lambda _: self._apply_palette(),
            font=ctk.CTkFont(size=12),
            width=155,
        )
        theme_menu.pack(side="right")

        # ── Hardware info panel ───────────────────────────────────────────
        self.hw_panel = ctk.CTkFrame(main_frame, corner_radius=12)
        self.hw_panel.pack(fill="x", pady=(0, 16))

        self.hw_title = ctk.CTkLabel(
            self.hw_panel,
            text="🖥  Hardware Detection",
            font=ctk.CTkFont(size=16, weight="bold"),
        )
        self.hw_title.pack(anchor="w", padx=20, pady=(15, 10))

        info_grid = ctk.CTkFrame(self.hw_panel, fg_color="transparent")
        info_grid.pack(fill="x", padx=20, pady=(0, 15))

        hw_items = [
            ("Wi-Fi",      self.hw_info.get("wifi_text",    "Unknown")),
            ("Bluetooth",  self.hw_info.get("bt_text",      "Unknown")),
            ("NVIDIA",     self.hw_info.get("nvidia_text",  "Unknown")),
            ("Repository", self.hw_info.get("nonfree_text", "Unknown")),
            ("USB Devices",self.hw_info.get("usb_text",     "Unknown")),
        ]

        self.hw_labels = []
        for i, (label, value) in enumerate(hw_items):
            row = i // 2
            col = i % 2
            item_frame = ctk.CTkFrame(info_grid, fg_color="transparent")
            item_frame.grid(row=row, column=col, sticky="w", padx=15, pady=5)

            label_widget = ctk.CTkLabel(
                item_frame,
                text=f"{label}:",
                font=ctk.CTkFont(size=12, weight="bold"),
            )
            label_widget.pack(side="left")

            value_widget = ctk.CTkLabel(
                item_frame,
                text=value,
                font=ctk.CTkFont(size=12),
            )
            value_widget.pack(side="left", padx=(5, 0))
            self.hw_labels.append((label_widget, value_widget))

        # ── Audio Production banner ───────────────────────────────────────
        audio_frame = ctk.CTkFrame(
            main_frame,
            fg_color=self._get_current_colors()["card_bg"],
            corner_radius=12,
        )
        audio_frame.pack(fill="x", pady=(0, 16))

        audio_content = ctk.CTkFrame(audio_frame, fg_color="transparent")
        audio_content.pack(fill="x", padx=20, pady=14)

        # Duże ikony muzyczne po lewej
        icons_label = ctk.CTkLabel(
            audio_content,
            text="♬",
            font=ctk.CTkFont(size=40),
        )
        icons_label.pack(side="left")

        audio_text_frame = ctk.CTkFrame(audio_content, fg_color="transparent")
        audio_text_frame.pack(side="left", padx=(16, 0), fill="x", expand=True)

        audio_title = ctk.CTkLabel(
            audio_text_frame,
            text="Audio Production",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color=self._get_current_colors()["accent"],
        )
        audio_title.pack(anchor="w")

        audio_desc = ctk.CTkLabel(
            audio_text_frame,
            text="Transform Debian into a professional audio workstation (Ubuntu Studio style)",
            font=ctk.CTkFont(size=12),
            text_color=self._get_current_colors()["fg_secondary"],
        )
        audio_desc.pack(anchor="w")

        # Dekoracyjny pasek fali (statyczny)
        wave_label = ctk.CTkLabel(
            audio_text_frame,
            text="▁▂▃▅▆▇▆▅▄▃▂▁▂▃▅▆",
            font=ctk.CTkFont(size=11),
            text_color=self._get_current_colors()["muted"],
        )
        wave_label.pack(anchor="w", pady=(2, 0))
        self.audio_wave_label = wave_label

        # Przycisk Open Setup
        self.audio_btn = ctk.CTkButton(
            audio_content,
            text="Open Setup",
            command=self._open_audio_window,
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color=self._get_current_colors()["accent"],
            hover_color=self._get_current_colors()["accent_hover"],
            text_color="#000000",
            corner_radius=8,
            width=140,
            height=42,
        )
        self.audio_btn.pack(side="right")

        # Hover effect — bind recursively to avoid flicker on child widgets
        def audio_on_hover(event):
            audio_frame.configure(border_width=2, border_color=self._get_current_colors()["accent"])

        def audio_on_leave(event):
            widget_under = audio_frame.winfo_containing(event.x_root, event.y_root)
            w = widget_under
            while w is not None:
                if w == audio_frame:
                    return
                try:
                    w = w.master
                except Exception:
                    break
            audio_frame.configure(border_width=0)

        def _bind_audio_hover(widget):
            widget.bind("<Enter>", audio_on_hover, add="+")
            widget.bind("<Leave>", audio_on_leave, add="+")
            for child in widget.winfo_children():
                _bind_audio_hover(child)

        _bind_audio_hover(audio_frame)
        audio_frame.configure(border_width=0)

        self.audio_frame = audio_frame
        self.audio_title = audio_title
        self.audio_desc  = audio_desc

        # ── Scrollable frame z kartami modułów ───────────────────────────
        scroll_frame = ctk.CTkScrollableFrame(
            main_frame,
            fg_color="transparent",
            corner_radius=0,
        )
        scroll_frame.pack(fill="both", expand=True)

        for idx, module in enumerate(self.modules):
            row = idx // 2
            col = idx % 2
            card = ModuleCard(scroll_frame, module, self._get_current_colors())
            card.grid(row=row, column=col, padx=10, pady=10, sticky="nsew")
            self.module_cards.append(card)

        scroll_frame.grid_columnconfigure(0, weight=1)
        scroll_frame.grid_columnconfigure(1, weight=1)

    # ── Helpers ───────────────────────────────────────────────────────────

    def _get_current_colors(self) -> dict:
        palette_name = self.palette_var.get() if hasattr(self, "palette_var") else "Neon Cyan"
        return self.PALETTES.get(palette_name, self.PALETTES["Neon Cyan"])

    def _apply_palette(self):
        colors = self._get_current_colors()

        # Tryb jasny / ciemny
        if "Light" in self.palette_var.get():
            ctk.set_appearance_mode("light")
        else:
            ctk.set_appearance_mode("dark")

        self._save_palette_preset(self.palette_var.get())

        # Header
        self.title_label.configure(text_color=colors["fg"])
        self.subtitle_label.configure(text_color=colors["fg_secondary"])

        # Hardware panel
        self.hw_title.configure(text_color=colors["fg"])
        for label_widget, value_widget in self.hw_labels:
            label_widget.configure(text_color=colors["fg"])
            value_widget.configure(text_color=colors["fg_secondary"])

        # Waveform
        if self.waveform:
            self.waveform.update_colors(colors)

        # Audio banner
        if hasattr(self, "audio_frame"):
            self.audio_frame.configure(fg_color=colors["card_bg"])
        if hasattr(self, "audio_title"):
            self.audio_title.configure(text_color=colors["accent"])
        if hasattr(self, "audio_desc"):
            self.audio_desc.configure(text_color=colors["fg_secondary"])
        if hasattr(self, "audio_wave_label"):
            self.audio_wave_label.configure(text_color=colors["muted"])
        if hasattr(self, "audio_btn"):
            self.audio_btn.configure(
                fg_color=colors["accent"],
                hover_color=colors["accent_hover"],
            )

        # Karty modułów
        for card in self.module_cards:
            card.colors = colors
            card.configure(fg_color=colors["card_bg"], border_color=colors["border"])
            if hasattr(card, "run_button"):
                card.run_button.configure(
                    fg_color=colors["accent"],
                    hover_color=colors["accent_hover"],
                )
            for widget in card.winfo_children():
                if isinstance(widget, ctk.CTkLabel):
                    if widget.cget("text") == "●":
                        continue
                    widget.configure(text_color=colors["fg"])
                elif isinstance(widget, ctk.CTkFrame):
                    for subwidget in widget.winfo_children():
                        if isinstance(subwidget, ctk.CTkLabel):
                            if subwidget.cget("text") == "●":
                                continue
                            if subwidget.cget("font").cget("weight") == "bold":
                                subwidget.configure(text_color=colors["accent"])
                            else:
                                subwidget.configure(text_color=colors["fg"])
                elif isinstance(widget, ctk.CTkButton):
                    is_enabled = str(widget.cget("state")) == "normal"
                    widget.configure(text_color="#000000" if is_enabled else "#404040")

    def _load_palette_preset(self) -> str:
        try:
            if self.config_path.exists():
                data = json.loads(self.config_path.read_text(encoding="utf-8"))
                preset = data.get("palette_preset")
                if preset in self.PALETTES:
                    return preset
        except Exception:
            pass
        return "Neon Cyan"

    def _save_palette_preset(self, preset: str):
        try:
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            data = {"palette_preset": preset}
            self.config_path.write_text(json.dumps(data), encoding="utf-8")
        except Exception:
            pass

    def _open_audio_window(self):
        try:
            base_dir = Path(__file__).parent.resolve()
            AudioProductionWindow(
                self.root,
                self._get_current_colors(),
                base_dir,
            )
        except Exception as e:
            _log_exception("Failed to open audio production window", e)


# ══════════════════════════════════════════════════════════════════════════════
#  Entry point
# ══════════════════════════════════════════════════════════════════════════════

def main():
    base_dir = Path(__file__).parent.resolve()

    nvidia_detected  = detect_nvidia_gpu()
    nvidia_arch      = detect_nvidia_arch() if nvidia_detected else ""
    bt_detected      = detect_bluetooth_controller()
    wifi_vendors     = detect_wifi_vendors()
    nonfree_enabled  = has_nonfree_enabled()
    usb_summary      = detect_usb_devices_summary()

    wifi_desc    = "None detected" if not wifi_vendors else "Detected: " + ", ".join(sorted(wifi_vendors))
    bt_desc      = "Detected"     if bt_detected       else "Not detected"
    nonfree_desc = "Enabled"      if nonfree_enabled   else "Not enabled"

    if nvidia_detected:
        legacy_archs = {"Kepler", "Maxwell", "Pascal", "Volta", "Fermi or older"}
        if nvidia_arch in legacy_archs:
            nvidia_desc = f"Detected ({nvidia_arch} — legacy, max driver 580.xx)"
        elif nvidia_arch != "unknown":
            nvidia_desc = f"Detected ({nvidia_arch})"
        else:
            nvidia_desc = "Detected"
    else:
        nvidia_desc = "Not detected"

    hw_info = {
        "wifi_text":    wifi_desc,
        "bt_text":      bt_desc,
        "nvidia_text":  nvidia_desc,
        "nonfree_text": nonfree_desc,
        "usb_text":     usb_summary,
    }

    if nvidia_detected and nvidia_arch in {"Kepler", "Maxwell", "Pascal", "Volta", "Fermi or older"}:
        nvidia_module_desc = (
            f"Detected NVIDIA GPU ({nvidia_arch} — legacy). "
            f"Smart driver selection will find a compatible version."
        )
    elif nvidia_detected:
        nvidia_module_desc = (
            "Detected NVIDIA GPU. Quick driver setup (also available via Configuration)."
        )
    else:
        nvidia_module_desc = "No NVIDIA GPU detected."

    modules = [
        ScriptModule("Configuration", base_dir / "configuration",               CONFIG_DESCRIPTION),
        ScriptModule("NVIDIA",        base_dir / "configuration" / "nvidia.sh", nvidia_module_desc, enabled=nvidia_detected),
        ScriptModule("Xfce Look",     base_dir / "xfce_look",                   XFCE_LOOK_DESCRIPTION),
        ScriptModule("Software",      base_dir / "software",                    SOFTWARE_DESCRIPTION),
    ]

    root = ctk.CTk()
    app = BashiumApp(root, modules, hw_info=hw_info)
    root.mainloop()


if __name__ == "__main__":
    main()
