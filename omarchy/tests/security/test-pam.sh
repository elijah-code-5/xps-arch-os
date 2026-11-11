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
touch "$B/usb/usb-TestStick_123-0:0"
touch "$B/usb/usb-TestStick_123-0:0-part1"

stack() { cat <<STACK
auth    required    pam_unix.so
auth    required    pam_xps.so usbdir=$1
account required    pam_unix.so
STACK
}
stack "$B/usb"   > /etc/pam.d/t-usb
stack "$B/nousb" > /etc/pam.d/t-nousb

t() { # name service answers expect(0/1)
    XPS_TEST_ANSWERS="$3" "$B/pamtest" "$2" tester >"$B/out" 2>&1; rc=$?
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
# never set up -> module is ignored, password alone works (cannot lock you out)
mv /etc/xps-security/xps.conf "$B/conf.bak"
t "not set up: password alone works"    t-nousb "0405"      0
printf 'garbage\n' > /etc/xps-security/xps.conf
t "broken config: refuses (safe)"       t-nousb "0405;2059" 1
exit $fail
