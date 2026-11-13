#!/usr/bin/env bash
# Real PAM test. Run as root inside an Arch Linux container (CI does this).
# Builds the actual module and checks every login scenario through the real PAM library.
set -u
SRC="${1:?path to omarchy/payload/security}"
pacman -Sy --noconfirm --needed gcc pam >/dev/null 2>&1 || { echo "FAIL: could not install gcc/pam"; exit 1; }
B=$(mktemp -d); fail=0
gcc -O2 -Wall -shared -fPIC -I"$SRC" -o /usr/lib/security/pam_xps.so "$SRC/pam_xps.c" "$SRC/xps_check.c" -lpam -lcrypt || { echo "FAIL: build module"; exit 1; }
gcc -O2 -Wall -I"$SRC" -o "$B/pamtest" "$SRC/xps_pamtest.c" -lpam || { echo "FAIL: build pamtest"; exit 1; }
gcc -O2 -Wall -I"$SRC" -o "$B/codehash" "$SRC/xps_codehash.c" "$SRC/xps_check.c" -lcrypt || { echo "FAIL: build codehash"; exit 1; }

useradd -m tester && echo 'tester:0405' | chpasswd
mkdir -p /etc/xps-security "$B/usb" "$B/nousb"
HASH=$(printf '2059' | "$B/codehash")
printf 'usb_id=usb-TestStick_123-0:0\ncode_hash=%s\n' "$HASH" > /etc/xps-security/xps.conf
chmod 644 /etc/xps-security/xps.conf   # the lock screen runs as the normal user, so it must be able to read this
chmod -R a+rX "$B"; chmod a+rx "$B"
touch "$B/usb/usb-TestStick_123-0:0"
touch "$B/usb/usb-TestStick_123-0:0-part1"

stack() { cat <<STACK
auth       required     pam_unix.so
auth       required     pam_xps.so usbdir=$1
account    required     pam_unix.so
STACK
}
stack "$B/usb"   > /etc/pam.d/t-usb
stack "$B/nousb" > /etc/pam.d/t-nousb

t() { # name service answers expect(0/1)
    XPS_TEST_ANSWERS="$3" setpriv --reuid=tester --regid=tester --clear-groups "$B/pamtest" "$2" tester >"$B/out" 2>&1; rc=$?
    if [ "$rc" = "$4" ]; then echo "PASS: $1"; else echo "FAIL: $1 (rc=$rc, wanted $4)"; cat "$B/out"; fail=1; fi
}
t "password + stick present"            t-usb   "0405"      0
t "wrong password, stick present"       t-usb   "9999"      1
t "stick missing, right code"           t-nousb "0405;2059" 0
t "stick missing, wrong code"           t-nousb "0405;1111" 1
t "stick missing, empty code"           t-nousb "0405;"     1
t "right code but wrong password"       t-nousb "9999;2059" 1
# the recovery code must never replace the password
t "code alone is not enough"            t-nousb "2059;2059" 1
# unreadable config (root-only) must fail, which is the bug that broke Test A
chmod 600 /etc/xps-security/xps.conf
t "root-only config is refused (regression)" t-usb "0405" 1
chmod 644 /etc/xps-security/xps.conf
# never set up -> module is ignored, password alone works (cannot lock you out)
mv /etc/xps-security/xps.conf "$B/conf.bak"
t "not set up: password alone works"    t-nousb "0405"      0
printf 'garbage\n' > /etc/xps-security/xps.conf
t "broken config: refuses (safe)"       t-nousb "0405;2059" 1
# --- face check (as a second condition while the stick is in) ---
mv "$B/conf.bak" /etc/xps-security/xps.conf 2>/dev/null || printf 'usb_id=usb-TestStick_123-0:0\ncode_hash=%s\n' "$HASH" > /etc/xps-security/xps.conf
echo "face=1" >> /etc/xps-security/xps.conf; chmod 644 /etc/xps-security/xps.conf
printf '#!/bin/sh\nexit 0\n' > "$B/face-ok"; printf '#!/bin/sh\nexit 1\n' > "$B/face-no"; printf '#!/bin/sh\nsleep 60\n' > "$B/face-hang"
chmod 755 "$B"/face-*
for v in ok no hang; do
    printf 'auth required pam_unix.so\nauth required pam_xps.so usbdir=%s facecmd=%s\naccount required pam_unix.so\n' "$B/usb" "$B/face-$v" > /etc/pam.d/t-face-$v
done
t "face ok + stick in: password is enough"      t-face-ok   "0405"      0
t "face NOT ok + stick in: asks recovery code"  t-face-no   "0405;2059" 0
t "face NOT ok + wrong code: refused"           t-face-no   "0405;1111" 1
t "face NOT ok + no code: refused"              t-face-no   "0405;"     1
t "camera hangs: gives up, then code works"     t-face-hang "0405;2059" 0
t "camera hangs + wrong code: refused"          t-face-hang "0405;1111" 1
printf 'auth required pam_unix.so\nauth required pam_xps.so usbdir=%s facecmd=/nonexistent/xps-face\naccount required pam_unix.so\n' "$B/usb" > /etc/pam.d/t-face-missing
t "face program missing: code fallback"         t-face-missing "0405;2059" 0
t "face program missing + wrong code: refused"  t-face-missing "0405;0000" 1
# --- pam_usb layout (the real stack text from xps-security; pam_permit / pam_deny stand in for pam_usb) ---
BACKUP=/etc/pam.d/orig
eval "$(sed -n '/^make_stack_pamusb() {/,/^}/p' "$SRC/../bin/xps-security")"
mk() { make_stack_pamusb "$B/face-$2" | sed "s#pam_usb.so#$1#; s#pam_xps.so usbdir=/var/empty#pam_xps.so usbdir=/var/empty#" > "/etc/pam.d/$3"; }
mk pam_permit.so ok  u-ok-ok     # stick ok, face ok
mk pam_permit.so no  u-ok-no     # stick ok, face not ok
mk pam_deny.so   ok  u-no-ok     # stick not ok
# face on (config already has face=1)
t "pam_usb: stick ok + face ok + password"        u-ok-ok "0405"      0
t "pam_usb: stick ok + face ok + wrong password"  u-ok-ok "9999"      1
t "pam_usb: stick ok, face no -> asks code, right" u-ok-no "0405;2059" 0
t "pam_usb: stick ok, face no -> wrong code"       u-ok-no "0405;1111" 1
t "pam_usb: stick not ok -> right code"            u-no-ok "0405;2059" 0
t "pam_usb: stick not ok -> wrong code"            u-no-ok "0405;1111" 1
t "pam_usb: wrong password, stick+face ok"         u-no-ok "9999;2059" 1
# face off: stick ok alone is enough with the password
sed -i '/^face=/d' /etc/xps-security/xps.conf
t "pam_usb, face off: stick ok + password"         u-ok-no "0405"      0
t "pam_usb, face off: stick not ok, wrong code"    u-no-ok "0405;1111" 1
exit $fail
