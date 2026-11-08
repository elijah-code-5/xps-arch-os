#!/usr/bin/env python3
"""Build archinstall.json from the overlay so there is one source of truth.

Usage: make-archinstall-config.py <repo-root> <output.json>
"""
import base64
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
airootfs = root / "overlay" / "airootfs"

packages = [
    line.strip()
    for line in (root / "overlay" / "packages.installed").read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]

# Overlay files that also go onto the installed system.
carry_files = [
    "etc/systemd/zram-generator.conf",
    "etc/default/earlyoom",
    "usr/local/bin/xps-mode",
    "usr/local/bin/xps-mode-settings",
    "usr/local/bin/xps-first-login",
]
carry_dirs = [
    "etc/skel",
    "etc/profile.d",
    "etc/sysctl.d",
    "etc/modprobe.d",
    "etc/udev/rules.d",
    "etc/systemd/journald.conf.d",
    "usr/lib/systemd/user",
    "usr/share/applications",
    "usr/lib/firefox",
]

paths = list(carry_files)
for d in carry_dirs:
    for f in sorted((airootfs / d).rglob("*")):
        if f.is_file() and not f.is_symlink():
            paths.append(str(f.relative_to(airootfs)))

commands = []
for rel in paths:
    target = "/" + rel
    folder = str(pathlib.PurePosixPath(target).parent)
    encoded = base64.b64encode((airootfs / rel).read_bytes()).decode()
    commands.append(
        f'mkdir -p "{folder}" && echo {encoded} | base64 -d > "{target}"'
    )

commands += [
    "chmod +x /usr/local/bin/xps-mode /usr/local/bin/xps-mode-settings /usr/local/bin/xps-first-login",
    # Home folders already exist when these commands run, so give them the skel files.
    'for d in /home/*/; do u=$(basename "$d"); cp -rn /etc/skel/. "$d" && chown -R "$u":"$(id -gn "$u")" "$d"; done',
    # Learning/coding/free mode timer for every user
    "systemctl --global enable xps-mode-auto.timer",
    # raspberrypi.local style names for the Pi server
    "sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf",
    "systemctl enable lightdm NetworkManager earlyoom tlp thermald bluetooth avahi-daemon",
    "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true",
]

config = {
    "hostname": "xps-arch",
    "kernels": ["linux"],
    "packages": packages,
    "custom_commands": commands,
}

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(config, indent=2) + "\n")
print(f"Wrote {out} with {len(packages)} packages and {len(commands)} commands")
