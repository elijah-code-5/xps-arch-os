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

1. Open the repo's **Releases** (right side of the main page) and download the newest `.iso`.
   (Builds run in **Actions** and publish there automatically.)
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

School is on the tablet, so this laptop only has two modes: **Coding** (default 13:00-18:00 weekdays,
08:00-18:00 weekends) and **Free**. Change the times in the menu: **Mode times**.

- **Coding:** VS Code opens and compiles get CPU priority and protected memory; notifications paused.
- **Free:** everything normal.

Browser memory is capped (soft 6 GB, hard 10 GB) so 24 tabs can never starve your compiler.

## Robot / T-HMI / Pi

First login (once, in the background, needs internet): installs Arduino ESP32 board support
and `mpremote`. Installed: esptool, thonny, picocom, ssh, and `.local` name lookup so your Pi
is reachable as `raspberrypi.local`. Serial boards need no extra permissions.

## What is inside the image (works with no internet)

Everything is in the live image, so you can try it in a VM without Wi-Fi: desktop, VS Code, Arduino tools,
LibreOffice, Shotcut video editor, Nextcloud sync, Firefox, plus:

- **Boot logo:** your Elijah Laptop logo shows while the system starts.
- **Voice typing (Super+V):** press once to listen, press again and it types what you said, offline.
- **AI assistant (Super+A):** a small offline chat assistant (model: qwen2.5 1.5B). Nothing leaves the laptop.
- **Connect my server:** menu entry that links your Nextcloud server (files sync, office opens in the browser).
- **Locking:** the screen locks when idle and when you close the lid. In the live test session the password is `live`.

Give the VM at least 6 GB of RAM. Install-to-disk still downloads software, so it needs internet.
