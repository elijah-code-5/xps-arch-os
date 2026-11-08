#!/usr/bin/env bash
# Run by GitHub Actions (not by you). Turns the stock Arch "releng" ISO profile
# into the XPS Arch OS profile by layering ./overlay on top of it.
set -euo pipefail

PROFILE="${1:?usage: apply-overlay.sh <profile-dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Extra packages
grep -vE '^\s*(#|$)' "$HERE/overlay/packages.extra" >> "$PROFILE/packages.x86_64"

# Extra package repo (chaotic-aur: Calamares, Arduino IDE)
cat "$HERE/overlay/pacman.append" >> "$PROFILE/pacman.conf"

# Our files on top of the live system
cp -a "$HERE/overlay/airootfs/." "$PROFILE/airootfs/"

# NetworkManager replaces the stock live networking
rm -f "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" \
      "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service" \
      "$PROFILE/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket" \
      "$PROFILE/airootfs/etc/systemd/system/sysinit.target.wants/systemd-networkd-wait-online.service" \
      "$PROFILE/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

# Name, label and file permissions
sed -i \
  -e 's|^iso_name=.*|iso_name="xps-arch-os"|' \
  -e 's|^iso_label=.*|iso_label="XPSARCH_$(date +%Y%m)"|' \
  -e 's|^iso_application=.*|iso_application="XPS Arch OS Live/Install"|' \
  "$PROFILE/profiledef.sh"
echo 'file_permissions+=(["/usr/local/bin/create-live-user"]="0:0:755")' >> "$PROFILE/profiledef.sh"

echo "Overlay applied to $PROFILE"
