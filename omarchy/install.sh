#!/usr/bin/env bash
# XPS Setup: installs and wires up everything on Omarchy, automatically.
#   (no arguments)  install everything
#   --undo          remove the shortcuts, menu entries and mode timer this app added
# Set XPS_DRY=1 to print the system-level steps instead of running them (used by the tests).
SRC="${XPS_PAYLOAD:?XPS_PAYLOAD is not set}"
DRY="${XPS_DRY:-0}"
R="${XPS_ROOT:-}"     # empty on a real system; the tests point it at a scratch folder
LOG="$HOME/.local/state/xps-setup.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

# The app's own files sit in a mount that even the administrator account cannot read.
# Copy them somewhere ordinary first, otherwise every "sudo install" from them fails.
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/xps-stage.XXXXXX")
cp -a "$SRC/." "$STAGE/"
find "$STAGE" -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null
chmod -R a+rX "$STAGE"
PAYLOAD="$STAGE"
trap 'rm -rf "$STAGE"' EXIT

DONE=(); FAILED=(); NOTES=()
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m %s\n' "$*"; DONE+=("$*"); }
bad()  { printf '  \033[31m[problem]\033[0m %s\n' "$*"; FAILED+=("$*"); }
note() { printf '  %s\n' "$*"; }
run()  {
    if [ "$DRY" = 1 ] && ! { [ "${XPS_TEST_REAL_INSTALL:-0}" = 1 ] && [ "${2:-}" = install ]; }; then echo "  [dry-run] $*"; return 0; fi
    "$@"
}
pause_end() { [ "$DRY" = 1 ] && return; echo; read -r -p "Press Enter to close this window. "; }

BEGIN_MARK='XPS-SETUP BEGIN'
END_MARK='XPS-SETUP END'
HYPR="$HOME/.config/hypr"
APPS="$HOME/.local/share/applications"

# Remove our block (between the marks) from a config file, keeping everything else.
strip_block() {
    local f=$1
    [ -f "$f" ] || return 0
    sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$f"
}

# ------------------------------------------------------------------------------------------------
undo() {
    say "Removing what XPS Setup added (your programs stay installed)"
    for f in "$HYPR/bindings.lua" "$HYPR/bindings.conf"; do strip_block "$f" && [ -f "$f" ] && ok "Shortcuts removed from $(basename "$f")"; done
    rm -f "$APPS"/xps-*.desktop
    systemctl --user disable --now xps-mode-auto.timer >/dev/null 2>&1
    systemctl --user disable --now xps-taskbar.service xps-power.timer xps-usb-watch.service >/dev/null 2>&1
    if [ -f /etc/pam.d/hyprlock.before-xps ] && command -v xps-security >/dev/null 2>&1; then
        echo "  Turning the USB-key lock off first, so you can still log in..."
        xps-security disable
    fi
    rm -f "$HOME/.config/systemd/user"/xps-* "$HOME/.config/waybar"/xps-taskbar.*
    ok "Menu entries, taskbar and the mode timer removed"
    pause_end
    exit 0
}
[ "${1:-}" = "--undo" ] && undo

# ------------------------------------------------------------------------------------------------
clear 2>/dev/null
cat <<'EOF'
  ==========================================
     ELIJAH LAPTOP - one-click setup
  ==========================================
  This will, by itself:
    - update the system and install: Office, video editor, task manager, Nextcloud, Arduino/ESP32 tools
    - add voice typing, the offline AI assistant, coding/free time modes, the control panel
    - add a taskbar at the bottom of the screen and shortcuts: Super+F7 task manager, F8 panel, F9 voice typing, F10 assistant
  It asks for your password once. It can take 10-30 minutes depending on your internet.
EOF
if [ "$DRY" != 1 ]; then read -r -t 15 -p "  Starting in 15 seconds. Press Enter to start now, or close this window to cancel. " _ ; echo; fi

# --- 1. internet ----------------------------------------------------------------------------------
say "Checking the internet"
online() { curl -fsI --max-time 8 https://archlinux.org >/dev/null 2>&1; }
if [ "$DRY" != 1 ]; then
    until online; do
        echo "  No internet yet. Click the Wi-Fi icon at the top right of the screen and connect,"
        echo "  or plug in a cable. Then come back here and press Enter."
        read -r -p "  Press Enter to check again. " _
    done
fi
ok "Internet works"

# --- 2. password once, keep it alive ---------------------------------------------------------------
say "Administrator password (needed once)"
if [ "$DRY" != 1 ]; then
    sudo -v || { echo "  Could not get permission. Closing."; pause_end; exit 1; }
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    KEEPALIVE=$!
fi
ok "Permission granted"

command -v omarchy-menu >/dev/null 2>&1 || note "(This does not look like Omarchy. Continuing; shortcut setup may be skipped.)"

# --- 3. safety snapshot ----------------------------------------------------------------------------
say "Making a restore point"
if command -v snapper >/dev/null 2>&1 && [ "$DRY" != 1 ]; then
    sudo snapper -c root create -d "Before XPS Setup" >/dev/null 2>&1 && ok "Snapshot created (Omarchy can roll back to it)" || note "No snapshot made (snapper is not set up). Continuing."
else
    note "No snapshot tool found. Continuing."
fi

# --- 4. system update + packages --------------------------------------------------------------------
say "Updating the system (this is the long part)"
UPDATED=1
if [ "$DRY" = 1 ]; then echo "  [dry-run] sudo pacman -Syu --noconfirm"
elif ! sudo pacman -Syu --noconfirm; then
    UPDATED=0
    bad "System update failed, so no programs were installed. Check the internet and run this app again."
fi

PKGS=(
    # task manager, voice typing, dialogs
    gnome-system-monitor btop wtype yad tk libnotify wl-clipboard pipewire waybar
    # office, video editor, server sync
    libreoffice-fresh hunspell-en_us kdenlive nextcloud-client xournalpp
    # offline assistant
    ollama curl
    # Arduino / ESP32 / robot work
    arduino-cli esptool python-pyserial picocom python-pipx
    # fast builds
    ccache mold cmake ninja base-devel git
    # memory safety
    zram-generator earlyoom
    # battery and heat on this laptop, lock-screen module build
    thermald power-profiles-daemon pam
)
if [ "$UPDATED" = 1 ]; then
    say "Installing programs"
    AVAIL=(); MISSING=()
    for p in "${PKGS[@]}"; do
        if [ "$DRY" = 1 ] || pacman -Si "$p" >/dev/null 2>&1; then AVAIL+=("$p"); else MISSING+=("$p"); fi
    done
    [ ${#MISSING[@]} -gt 0 ] && note "Not available right now, skipped: ${MISSING[*]}"
    if [ "$DRY" = 1 ]; then echo "  [dry-run] sudo pacman -S --needed --noconfirm ${AVAIL[*]}"
    elif sudo pacman -S --needed --noconfirm "${AVAIL[@]}"; then ok "Programs installed"
    else
        note "One program failed. Trying them one by one..."
        for p in "${AVAIL[@]}"; do sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || bad "Could not install $p"; done
    fi
    if ! command -v code >/dev/null 2>&1 && [ "$DRY" != 1 ]; then
        sudo pacman -S --needed --noconfirm code >/dev/null 2>&1 && ok "VS Code installed" || note "VS Code not installed (Omarchy can add it from its menu: Install > Editor)."
    fi
fi

# --- 5. memory tuning --------------------------------------------------------------------------------
say "Tuning memory so many things can run at once"
if [ "$DRY" = 1 ] || [ "$UPDATED" = 1 ]; then
    if [ -d /sys/block/zram0 ] || { command -v swapon >/dev/null && swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; }; then
        note "Compressed swap (zram) is already on. Leaving it as it is."
    else
        if run sudo install -Dm644 "$PAYLOAD/system/zram-generator.conf" "$R/etc/systemd/zram-generator.conf" \
           && run sudo install -Dm644 "$PAYLOAD/system/99-xps-memory.conf" "$R/etc/sysctl.d/99-xps-memory.conf" \
           && run sudo systemctl daemon-reload && run sudo systemctl start systemd-zram-setup@zram0.service && run sudo sysctl --system >/dev/null; then
            ok "Compressed swap enabled"
        else bad "Compressed swap did not turn on"; fi
    fi
    if run sudo install -Dm644 "$PAYLOAD/system/earlyoom" "$R/etc/default/earlyoom" && run sudo systemctl enable --now earlyoom.service; then
        ok "Out-of-memory guard on (one runaway program can no longer freeze the laptop)"
    else bad "The out-of-memory guard did not install"; fi
    if run sudo install -Dm644 "$PAYLOAD/system/50-serial-uaccess.rules" "$R/etc/udev/rules.d/50-serial-uaccess.rules" \
       && run sudo udevadm control --reload-rules && run sudo usermod -aG uucp "$USER"; then
        ok "Arduino and ESP32 boards can be used without extra permissions (after a restart)"
    else bad "Arduino board permissions did not install"; fi
fi

# --- 6. my tools ----------------------------------------------------------------------------------------
say "Installing my tools"
TOOLFAIL=0
for f in "$PAYLOAD"/bin/*; do
    [ -f "$f" ] || continue
    run sudo install -Dm755 "$f" "$R/usr/local/bin/$(basename "$f")" || { bad "Could not install $(basename "$f")"; TOOLFAIL=1; }
done
if [ -f "$PAYLOAD/whisper-cli" ]; then
    run sudo install -Dm755 "$PAYLOAD/whisper-cli" "$R/usr/local/bin/whisper-cli" || { bad "Could not install the speech engine"; TOOLFAIL=1; }
fi
# security sources (built on this laptop when you run "Security setup") and the device brief for the assistant
run sudo mkdir -p "$R/usr/local/share/xps-security/src" "$R/usr/local/share/xps"
for f in "$PAYLOAD"/security/*; do
    run sudo install -Dm644 "$f" "$R/usr/local/share/xps-security/src/$(basename "$f")" || { bad "Could not install security files"; TOOLFAIL=1; }
done
run sudo install -Dm644 "$PAYLOAD/share/device-brief.md" "$R/usr/local/share/xps/device-brief.md" || { bad "Could not install the device brief"; TOOLFAIL=1; }
# keep a copy of this app so "repair" works later from the menu
if [ -n "${APPIMAGE:-}" ] && [ -f "$APPIMAGE" ] && [ "$DRY" != 1 ]; then
    mkdir -p "$HOME/.local/share/xps"; cp -f "$APPIMAGE" "$HOME/.local/share/xps/XPS-Setup.AppImage" && chmod +x "$HOME/.local/share/xps/XPS-Setup.AppImage"
    cat > "$HOME/.local/share/applications/xps-repair.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=XPS Setup (repair)
Comment=Run the setup again; it skips what already works
Exec=$HOME/.local/share/xps/XPS-Setup.AppImage
Icon=system-software-update
Categories=Utility;
DESK
fi
[ "$TOOLFAIL" = 0 ] && ok "Voice typing, assistant, modes, control panel and shortcuts list installed"

mkdir -p "$APPS" "$HOME/.config/systemd/user" "$HOME/.config/xps-modes" "$HOME/.local/share/xps-models/whisper"
cp -f "$PAYLOAD"/applications/*.desktop "$APPS/"
cp -f "$PAYLOAD"/systemd-user/* "$HOME/.config/systemd/user/"
[ -f "$HOME/.config/xps-modes/schedule.conf" ] || cp "$PAYLOAD/schedule.conf" "$HOME/.config/xps-modes/schedule.conf"
mkdir -p "$HOME/Pictures"; cp -n "$PAYLOAD/logo.png" "$HOME/Pictures/elijah-logo.png" 2>/dev/null
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null
if [ "$DRY" != 1 ]; then
    systemctl --user daemon-reload
    systemctl --user enable --now xps-mode-auto.timer >/dev/null 2>&1 && ok "Coding/free time modes switch by the clock (13:00-18:00 weekdays, 08:00-18:00 weekends)" || bad "Mode timer did not start"
    command -v xps-mode >/dev/null 2>&1 && xps-mode auto >/dev/null 2>&1
    systemctl --user enable --now xps-power.timer >/dev/null 2>&1 && ok "Battery saver: power-saver on battery, balanced when plugged in" || bad "Battery saver timer did not start"
    systemctl --user enable --now xps-usb-watch.service >/dev/null 2>&1 || bad "USB key watcher did not start"
    sudo systemctl enable --now thermald.service power-profiles-daemon.service >/dev/null 2>&1 || note "Heat/power services could not be enabled (Omarchy may manage them)."
fi
ok "Menu entries added (press Super+Space and type: XPS, Task, Assistant, Voice...)"

# --- 6b. taskbar -----------------------------------------------------------------------------------------
say "Adding the taskbar (bottom of the screen, lists open windows)"
mkdir -p "$HOME/.config/waybar"
cp -f "$PAYLOAD/taskbar/xps-taskbar.jsonc" "$PAYLOAD/taskbar/xps-taskbar.css" "$HOME/.config/waybar/"
cp -f "$PAYLOAD/taskbar/xps-taskbar.service" "$HOME/.config/systemd/user/"
if [ "$DRY" != 1 ]; then
    systemctl --user daemon-reload
    systemctl --user enable xps-taskbar.service >/dev/null 2>&1
    systemctl --user restart xps-taskbar.service >/dev/null 2>&1
    sleep 2
    if systemctl --user is-active --quiet xps-taskbar.service; then ok "Taskbar added at the bottom of the screen";
    else
        # fall back to starting it directly for this session
        ( setsid waybar -c "$HOME/.config/waybar/xps-taskbar.jsonc" -s "$HOME/.config/waybar/xps-taskbar.css" >/dev/null 2>&1 & )
        sleep 2
        pgrep -f xps-taskbar.jsonc >/dev/null && ok "Taskbar started (it will also start at next login)" || bad "Taskbar did not start. It is in the Waybar settings if you want it later."
    fi
else
    ok "Taskbar files installed"
fi

# --- 7. shortcuts (works for both Omarchy config styles) ------------------------------------------------
say "Adding keyboard shortcuts"
bind_lua() { printf -- '-- %s\n' "$BEGIN_MARK"
    printf 'o.bind("SUPER + F7", "Task manager", "gnome-system-monitor")\n'
    printf 'o.bind("SUPER + F8", "XPS control panel", "xps-panel")\n'
    printf 'o.bind("SUPER + F9", "Voice typing", "xps-dictate")\n'
    printf 'o.bind("SUPER + F10", "AI assistant", "xps-assistant")\n'
    printf -- '-- %s\n' "$END_MARK"; }
bind_conf() { printf '# %s\n' "$BEGIN_MARK"
    printf 'bindd = SUPER, F7, Task manager, exec, gnome-system-monitor\n'
    printf 'bindd = SUPER, F8, XPS control panel, exec, xps-panel\n'
    printf 'bindd = SUPER, F9, Voice typing, exec, xps-dictate\n'
    printf 'bindd = SUPER, F10, AI assistant, exec, xps-assistant\n'
    printf '# %s\n' "$END_MARK"; }
if [ -f "$HYPR/bindings.lua" ]; then
    cp -n "$HYPR/bindings.lua" "$HYPR/bindings.lua.before-xps"
    strip_block "$HYPR/bindings.lua"; { echo; bind_lua; } >> "$HYPR/bindings.lua"
    ok "Shortcuts added (bindings.lua; original saved as bindings.lua.before-xps)"
elif [ -f "$HYPR/bindings.conf" ]; then
    cp -n "$HYPR/bindings.conf" "$HYPR/bindings.conf.before-xps"
    strip_block "$HYPR/bindings.conf"; { echo; bind_conf; } >> "$HYPR/bindings.conf"
    command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1
    ok "Shortcuts added (bindings.conf; original saved as bindings.conf.before-xps)"
else
    note "Could not find Omarchy's shortcut file, so I skipped shortcuts."
    note "Everything is still in the menu: Super+Space, then type XPS."
fi

# --- 8. voice and assistant files (downloads) ---------------------------------------------------------------
say "Downloading the voice typing model (about 140 MB)"
MODEL="$HOME/.local/share/xps-models/whisper/ggml-base.en.bin"
if [ "$DRY" = 1 ]; then echo "  [dry-run] download speech model"
elif [ -f "$MODEL" ]; then ok "Speech model already there"
elif curl -fL --retry 3 -o "$MODEL.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin && [ "$(stat -c %s "$MODEL.part")" -gt 100000000 ]; then
    mv "$MODEL.part" "$MODEL"; ok "Speech model downloaded"
else rm -f "$MODEL.part"; bad "Speech model did not download. Run this app again later."; fi

say "Downloading the AI assistant model (about 1 GB)"
if [ "$DRY" = 1 ]; then echo "  [dry-run] ollama pull qwen2.5:1.5b"
elif command -v ollama >/dev/null 2>&1; then
    STARTED=0
    if ! curl -sf http://127.0.0.1:11434/ >/dev/null 2>&1; then
        OLLAMA_HOST=127.0.0.1:11434 ollama serve >/dev/null 2>&1 & OPID=$!; STARTED=1
        for _ in $(seq 1 30); do curl -sf http://127.0.0.1:11434/ >/dev/null 2>&1 && break; sleep 1; done
    fi
    if ollama pull qwen2.5:1.5b; then ok "Assistant model downloaded"; else bad "Assistant model did not download. Run this app again later."; fi
    [ "$STARTED" = 1 ] && kill "$OPID" 2>/dev/null
else bad "The assistant engine (ollama) is not installed."; fi

# --- 9. Arduino / ESP32 boards -------------------------------------------------------------------------------
say "Adding ESP32 board support for Arduino (robot, T-HMI). This can take a while"
if [ "$DRY" = 1 ]; then echo "  [dry-run] arduino-cli core install esp32:esp32"
elif command -v arduino-cli >/dev/null 2>&1; then
    arduino-cli config init >/dev/null 2>&1
    arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json >/dev/null 2>&1
    arduino-cli core update-index >/dev/null 2>&1
    if arduino-cli core install esp32:esp32; then ok "ESP32 boards ready in Arduino"; else bad "ESP32 board support did not install. Run this app again later."; fi
    command -v pipx >/dev/null && pipx install mpremote >/dev/null 2>&1 && ok "mpremote (MicroPython tool) installed"
fi

# --- self-check: prove it works, do not just trust the steps above -----------------------------------------------
say "Checking that everything really works"
if [ "$DRY" != 1 ]; then
    for c in gnome-system-monitor kdenlive libreoffice nextcloud ollama wtype yad arduino-cli xps-mode xps-dictate xps-assistant xps-panel xps-shortcuts xps-server-setup xps-doctor xps-security xps-usb-watch xps-power xps-terminal whisper-cli; do
        command -v "$c" >/dev/null 2>&1 || bad "'$c' is not installed or not found"
    done
    /usr/bin/python3 -c "import tkinter" >/dev/null 2>&1 || bad "The assistant window needs Python's tk, which is missing"
    [ -f "$HOME/.local/share/xps-models/whisper/ggml-base.en.bin" ] || bad "The speech model is missing"
    ollama list 2>/dev/null | grep -q qwen2.5 || { [ -d "$HOME/.ollama/models" ] && ls "$HOME/.ollama/models/manifests" >/dev/null 2>&1; } || bad "The assistant model is missing"
    [ ${#FAILED[@]} -eq 0 ] && ok "All checks passed"
fi

# --- done ------------------------------------------------------------------------------------------------------
[ -n "${KEEPALIVE:-}" ] && kill "$KEEPALIVE" 2>/dev/null
echo
echo "=============================================================="
echo "  FINISHED"
echo "=============================================================="
for d in "${DONE[@]}"; do printf '  [ok] %s\n' "$d"; done
if [ ${#FAILED[@]} -gt 0 ]; then
    echo; echo "  Needs another try (run this app again, it skips what already worked):"
    for d in "${FAILED[@]}"; do printf '  [problem] %s\n' "$d"; done
fi
cat <<'EOF'

  Next:
    1. Restart the laptop once (so Arduino board access applies).
    2. Press Super+F8 for the control panel, or Super+Space and type what you want.
    3. Super+F7 = task manager. Super+F9 = voice typing. Super+F10 = AI assistant.
       If those F-keys do nothing on your Dell: press Fn+Esc once (switches the function row), or hold Fn.
       Always works: Super+Space, then type "Task Manager" / "Assistant" / "XPS".
  USB-key lock: open "Security setup (USB key)" from Super+Space. It asks for your password, a USB stick and
  a recovery code you choose. Do that once, then press "Lock screen" in the control panel (Super+F8) to try it.
  If anything seems off, open "Check everything" (Super+Space). It saves a report to ~/xps-doctor.txt.
  A full log is in: ~/.local/state/xps-setup.log
EOF
pause_end
