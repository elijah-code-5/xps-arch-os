#!/usr/bin/env bash
# Run by the build (not by you). Turns the stock Arch "releng" ISO profile into the XPS Arch OS profile:
# the whole desktop and every app live inside the image, so it works with no internet.
set -euo pipefail

PROFILE="${1:?usage: apply-overlay.sh <profile-dir>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Packages -------------------------------------------------------------------------------
# One list for the live image: small live packages + everything for the installed system.
# A package that does not exist is skipped with a warning instead of breaking the whole build.
ESSENTIAL="xfce4-session lightdm xorg-server networkmanager firefox"
wanted=$(cat "$HERE/overlay/packages.live" "$HERE/overlay/packages.installed" | grep -vE '^\s*(#|$)' | sort -u)
available=""
missing=""
for p in $wanted; do
    if pacman -Si "$p" >/dev/null 2>&1; then available+="$p"$'\n'; else missing+="$p "; fi
done
if [ -n "$missing" ]; then echo "::warning::skipped packages not found in the repos: $missing"; fi
for e in $ESSENTIAL; do
    grep -qx "$e" <<<"$available" || { echo "::error::essential package missing: $e"; exit 1; }
done
printf '%s' "$available" >> "$PROFILE/packages.x86_64"

# --- Our files on top of the live system ------------------------------------------------------
cp -a "$HERE/overlay/airootfs/." "$PROFILE/airootfs/"

# Models and speech engine prepared by ci-build.sh (skipped if not present)
if [ -d "${XPS_EXTRAS:-/nonexistent}" ]; then
    mkdir -p "$PROFILE/airootfs/usr/share/xps-models" "$PROFILE/airootfs/usr/local/bin"
    [ -d "$XPS_EXTRAS/whisper" ] && cp -a "$XPS_EXTRAS/whisper" "$PROFILE/airootfs/usr/share/xps-models/"
    [ -d "$XPS_EXTRAS/ollama" ]  && cp -a "$XPS_EXTRAS/ollama"  "$PROFILE/airootfs/usr/share/xps-models/"
    [ -x "$XPS_EXTRAS/whisper-cli" ] && install -m 755 "$XPS_EXTRAS/whisper-cli" "$PROFILE/airootfs/usr/local/bin/whisper-cli"
fi

# Installer settings for archinstall (package list + tuning files)
python3 "$HERE/scripts/make-archinstall-config.py" "$HERE" \
  "$PROFILE/airootfs/usr/share/xps-arch-os/archinstall.json"

# NetworkManager replaces the stock live networking
rm -f "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" \
      "$PROFILE/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service" \
      "$PROFILE/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket" \
      "$PROFILE/airootfs/etc/systemd/system/sysinit.target.wants/systemd-networkd-wait-online.service" \
      "$PROFILE/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"

# --- Boot logo (Plymouth) ---------------------------------------------------------------------
if grep -qx plymouth <<<"$available"; then
    hooks="$PROFILE/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
    if [ -f "$hooks" ] && grep -q '^HOOKS=' "$hooks"; then
        sed -i '/^HOOKS=/ s/\budev\b/udev plymouth/' "$hooks"
    else
        echo "::warning::mkinitcpio hooks file not found; boot logo will not show"
    fi
    # quiet splash = show the logo; cow_spacesize = RAM space for the live session's changes
    for f in "$PROFILE"/syslinux/*.cfg "$PROFILE"/grub/*.cfg "$PROFILE"/efiboot/loader/entries/*.conf; do
        [ -f "$f" ] && sed -i 's|archisobasedir=%INSTALL_DIR%|cow_spacesize=3G quiet splash archisobasedir=%INSTALL_DIR%|g' "$f"
    done
fi

# --- Name, label and file permissions ---------------------------------------------------------
sed -i \
  -e 's|^iso_name=.*|iso_name="xps-arch-os"|' \
  -e 's|^iso_label=.*|iso_label="XPSARCH_$(date +%Y%m)"|' \
  -e 's|^iso_application=.*|iso_application="XPS Arch OS Live/Install"|' \
  "$PROFILE/profiledef.sh"
for f in "$HERE"/overlay/airootfs/usr/local/bin/*; do
    echo "file_permissions+=([\"/usr/local/bin/$(basename "$f")\"]=\"0:0:755\")" >> "$PROFILE/profiledef.sh"
done
[ -x "$PROFILE/airootfs/usr/local/bin/whisper-cli" ] && \
    echo 'file_permissions+=(["/usr/local/bin/whisper-cli"]="0:0:755")' >> "$PROFILE/profiledef.sh"

echo "Overlay applied to $PROFILE"
