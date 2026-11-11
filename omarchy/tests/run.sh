#!/usr/bin/env bash
# Checks run before the app is built. Fails loudly if anything is off.
set -u
cd "$(dirname "$0")/.."
fail=0
check() { if "$@"; then echo "PASS: $*" | cut -c1-110; else echo "FAIL: $*"; fail=1; fi; }

for f in AppRun install.sh payload/bin/xps-dictate payload/bin/xps-mode payload/bin/xps-mode-settings \
         payload/bin/xps-panel payload/bin/xps-shortcuts payload/bin/xps-server-setup \
         payload/bin/xps-doctor payload/bin/xps-terminal payload/bin/xps-usb-watch payload/bin/xps-power \
         payload/bin/xps-apps payload/bin/xps-update; do
    check bash -n "$f"
done
check python3 -m py_compile payload/bin/xps-assistant
check bash -n payload/bin/xps-security
check grep -q 'qwen2.5-coder:1.5b' payload/bin/xps-assistant
check grep -q 'MODEL = os.environ.get("XPS_MODEL", "xps-coder")' payload/bin/xps-assistant
check grep -q '127.0.0.1:11434' payload/bin/xps-assistant
for mode in 'Arduino / ESP32' 'Linux sysadmin' 'Raspberry Pi' 'Code review' 'Build / debug'; do
    grep -Fq "$mode" payload/bin/xps-assistant || { echo "FAIL: missing assistant mode: $mode"; fail=1; }
done
check test -s payload/share/device-brief.md
check grep -q 'device_context' payload/bin/xps-assistant
if command -v gcc >/dev/null; then
    B=$(mktemp -d)
    check gcc -Wall -Werror -Ipayload/security -o "$B/t" tests/security/test_check.c payload/security/xps_check.c -lcrypt
    check "$B/t"
    check gcc -Wall -Itests/stubs -Ipayload/security -fsyntax-only payload/security/pam_xps.c
    check gcc -Wall -Itests/stubs -Ipayload/security -fsyntax-only payload/security/xps_pamtest.c
fi
check python3 -I -c "import json;json.load(open('payload/taskbar/xps-taskbar.jsonc'))"
grep -q '"on-click": "minimize-raise"' payload/taskbar/xps-taskbar.jsonc && echo "PASS: taskbar toggles minimize/restore" || { echo "FAIL: taskbar minimize/restore action missing"; fail=1; }
grep -q 'xps-apps' payload/taskbar/xps-taskbar.jsonc && echo "PASS: taskbar Apps button uses launcher fallback" || { echo "FAIL: taskbar Apps launcher missing"; fail=1; }
grep -q 'omarchy update' payload/bin/xps-update && echo "PASS: update button calls Omarchy updater" || { echo "FAIL: safe Omarchy update action missing"; fail=1; }

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

# Regression test: the AppImage payload is staged so privileged installation can read it.
if [ "$(id -u)" = 0 ] && command -v setpriv >/dev/null; then
    chmod 755 "$T"
    mkdir -p "$T/bin" "$T/root" "$T/locked" "$T/hreg/.config/hypr"
    chmod 777 "$T/root"
    cp -a payload "$T/locked/payload"; chmod -R go-rwx "$T/locked"
    printf '#!/bin/bash\nexec setpriv --reuid=65534 --regid=65534 --clear-groups "$@"\n' > "$T/bin/sudo"; chmod +x "$T/bin/sudo"
    echo "x" > "$T/hreg/.config/hypr/bindings.lua"
    PATH="$T/bin:$PATH" HOME="$T/hreg" XPS_DRY=1 XPS_TEST_REAL_INSTALL=1 XPS_ROOT="$T/root" \
        XPS_PAYLOAD="$T/locked/payload" bash install.sh </dev/null >"$T/reg.log" 2>&1
    for f in xps-dictate xps-assistant xps-mode xps-panel xps-shortcuts xps-server-setup xps-mode-settings xps-security xps-apps xps-update whisper-cli; do
        if [ "$f" = whisper-cli ]; then [ -e payload/whisper-cli ] || continue; fi
        [ -x "$T/root/usr/local/bin/$f" ] && echo "PASS: locked payload -> $f installed" || { echo "FAIL: $f not installed from a locked payload"; fail=1; }
    done
    [ -f "$T/root/etc/default/earlyoom" ] && echo "PASS: locked payload -> earlyoom config installed" || { echo "FAIL: earlyoom config missing"; fail=1; }
    grep -q "Permission denied" "$T/reg.log" && { echo "FAIL: permission errors in installer output"; fail=1; } || echo "PASS: no permission errors"
else
    echo "SKIP: locked-payload regression test (needs root)"
fi

rm -rf "$T"
exit $fail
