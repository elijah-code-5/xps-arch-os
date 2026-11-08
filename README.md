# XPS Arch OS

An Arch-based, XFCE live/install USB tuned for a Dell XPS 15 9560 (16 GB RAM) used for
coding (VS Code, Arduino), online lessons, lots of browser tabs and music.

## What is tuned

- **Memory:** compressed swap (zram, zstd), VM settings made for zram, `earlyoom` so one runaway
  process can't freeze the laptop, Firefox with uBlock Origin and Auto Tab Discard preinstalled.
- **Laptop:** TLP + thermald, Intel graphics only (the GTX 1050 is left unused so it can power down).
- **Dev:** VS Code (Code - OSS), arduino-cli (the Arduino IDE comes later via Flatpak), gcc/cmake/ninja/ccache/mold, git, Python.
  Serial access for Arduino boards is on for the installed user (`uucp` group).
- **Student/media:** Firefox, VLC, Shotcut (light video editor), Nextcloud desktop client.

## Get the ISO (no terminal needed)

1. On GitHub open the **Actions** tab, then **Build ISO**, then **Run workflow**.
2. When it turns green, open the run and download **xps-arch-os-iso** (a zip containing the `.iso`).
3. Test it in a VM (VirtualBox or virt-manager, enable EFI, 4 GB RAM, 30 GB disk).
4. To put it on a USB stick use Balena Etcher.

The live system boots to a small desktop and opens the installer by itself (or double-click
**Install XPS Arch OS**). It needs internet: connect Wi-Fi with the network icon first. The installer
is the official Arch `archinstall` menu with everything preloaded: you pick the disk, your username
and a password, and it installs the full software list below.

## Status

Version 0.1, **not yet booted anywhere**. Expect the first build or first install to need fixes.
Next planned: native Nextcloud connection to the Pi server.

## Modes (automatic by time of day)

Default schedule, weekdays: **Learning 08:00-13:00**, **Coding 13:00-18:00**, free otherwise.
Weekends are coding-only 08:00-18:00. Change any time in the menu: **Mode times**.

- **Learning:** Firefox opens and gets CPU priority; notifications paused.
- **Coding:** VS Code opens and compiles get CPU priority and protected memory; notifications paused.
- **Free:** everything normal.

Browser memory is capped (soft 6 GB, hard 10 GB) so 24 tabs can never starve your compiler.
Firefox and VS Code launched from the menu are placed in those groups automatically.
Switch by hand any time from the menu: Mode: Learning / Coding / Free time.

## Robot / T-HMI / Pi

First login (once, in the background, needs internet): installs Arduino ESP32 board support
and `mpremote`. Installed: esptool, thonny, picocom, ssh, and `.local` name lookup so your Pi
is reachable as `raspberrypi.local`. Serial boards need no extra permissions.
