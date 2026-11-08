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
overlay = root / "overlay"

packages = [
    line.strip()
    for line in (overlay / "packages.installed").read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]

# Files from the overlay that also go onto the installed system.
carry = [
    "/etc/systemd/zram-generator.conf",
    "/etc/sysctl.d/99-xps-memory.conf",
    "/etc/default/earlyoom",
    "/etc/modprobe.d/blacklist-nouveau.conf",
    "/etc/udev/rules.d/50-serial-uaccess.rules",
    "/usr/lib/firefox/distribution/policies.json",
]

commands = []
for path in carry:
    data = (overlay / "airootfs" / path.lstrip("/")).read_bytes()
    encoded = base64.b64encode(data).decode()
    folder = str(pathlib.PurePosixPath(path).parent)
    commands.append(f"mkdir -p {folder} && echo {encoded} | base64 -d > {path}")

commands.append(
    "systemctl enable lightdm NetworkManager earlyoom tlp thermald bluetooth"
)
commands.append(
    "flatpak remote-add --if-not-exists flathub "
    "https://dl.flathub.org/repo/flathub.flatpakrepo || true"
)

config = {
    "hostname": "xps-arch",
    "kernels": ["linux"],
    "packages": packages,
    "custom_commands": commands,
}

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(config, indent=2) + "\n")
print(f"Wrote {out} with {len(packages)} packages and {len(commands)} commands")
