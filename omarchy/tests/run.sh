#!/usr/bin/env bash
# Checks run before the app is built. Fails loudly if anything is off.
set -u
cd "$(dirname "$0")/.."
fail=0
check() { if "$@"; then echo "PASS: $*" | cut -c1-110; else echo "FAIL: $*"; fail=1; fi; }

for f in AppRun install.sh payload/bin/xps-dictate payload/bin/xps-mode payload/bin/xps-mode-settings \
         payload/bin/xps-panel payload/bin/xps-shortcuts payload/bin/xps-server-setup; do
    check bash -n "$f"
done
check python3 -m py_compile payload/bin/xps-assistant

check python3 -I -c "import json;json.load(open('payload/taskbar/xps-taskbar.jsonc'))"

# Mode schedule: weekday, weekend, and edges
T=$(mktemp -d); export HOME="$T/home"; mkdir -p "$HOME/.config/xps-modes"
cp payload/schedule.conf "$HOME/.config/xps-modes/schedule.conf"
pick() { XPS_NOW="$1" bash payload/bin/xps-mode pick; }
expect() { got=$(pick "$1"); if [ "$got" = "$2" ]; then echo "PASS: $1 -> $got"; else echo "FAIL: $1 -> $got (wanted $2)"; fail=1; fi; }
expect "2026-11-09 07:59" free
expect "2026-11-09 10:00" free
expect "2026-11-09 13:00" coding
expect "2026-11-09 17:59" coding
expect "2026-11-09 18:00" free
expect "2026-11-14 08:00" coding
expect "2026-11-14 18:00" free

# Installer dry runs for both Omarchy config styles; second run must not duplicate; undo must clean up
for style in lua conf; do
    H="$T/h-$style"; mkdir -p "$H/.config/hypr"; echo "keep me" > "$H/.config/hypr/bindings.$style"
    for i in 1 2; do HOME="$H" XPS_DRY=1 XPS_PAYLOAD="$PWD/payload" bash install.sh </dev/null >/dev/null 2>&1; done
    [ -f "$H/.config/waybar/xps-taskbar.jsonc" ] && echo "PASS: $style taskbar files installed" || { echo "FAIL: $style taskbar missing"; fail=1; }
    n=$(grep -c "XPS-SETUP BEGIN" "$H/.config/hypr/bindings.$style")
    [ "$n" = 1 ] && echo "PASS: $style shortcuts added once" || { echo "FAIL: $style block count $n"; fail=1; }
    HOME="$H" XPS_DRY=1 XPS_PAYLOAD="$PWD/payload" bash install.sh --undo </dev/null >/dev/null 2>&1
    grep -q "XPS-SETUP" "$H/.config/hypr/bindings.$style" && { echo "FAIL: $style undo left block"; fail=1; } || echo "PASS: $style undo removed block"
    [ ! -f "$H/.config/waybar/xps-taskbar.jsonc" ] && echo "PASS: $style undo removed taskbar" || { echo "FAIL: $style undo left taskbar"; fail=1; }
    grep -q "keep me" "$H/.config/hypr/bindings.$style" && echo "PASS: $style user lines kept" || { echo "FAIL: $style user line lost"; fail=1; }
done
rm -rf "$T"
exit $fail
