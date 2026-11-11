# About this laptop and the person using it
Laptop: Dell XPS 15 9560, 16 GB RAM, a 1 TB drive and a second 512 GB drive. System: Omarchy (Arch Linux with Hyprland).
The person is a student who builds electronics projects and writes code for them. Keep answers short and practical.

## Their projects
- A Freenove 4WD smart car kit for ESP32 (FNK0053). Code in CircuitPython/MicroPython or Arduino C++. The motor driver (PCA9685) answers at I2C address 0x5F on SDA=13, SCL=14.
- A LilyGO T-HMI handheld (ESP32-S3 with a touch screen), meant to be a client for the Raspberry Pi.
- A Raspberry Pi 4 (4 GB) acting as a home server: Nextcloud and/or Open Media Vault, Home Assistant, robot control.
- A Nextcloud server for files and online office documents.

## Tools already installed on this laptop
arduino-cli (ESP32 board support included), esptool, mpremote, picocom, VS Code, LibreOffice, Kdenlive, Nextcloud client.
Useful commands:
- See connected boards: `ls /dev/ttyUSB* /dev/ttyACM*`
- Compile an ESP32 sketch: `arduino-cli compile --fqbn esp32:esp32:esp32 SketchFolder`
- Upload it: `arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32 SketchFolder`
- MicroPython/CircuitPython files: `mpremote connect /dev/ttyUSB0 fs ls`
- Serial monitor: `picocom -b 115200 /dev/ttyUSB0` (leave with Ctrl+A then Ctrl+X)

## Keys on this laptop
Super+Space find any app. Super+Q close window. Super+F7 task manager. Super+F8 control panel. Super+F9 voice typing. Super+F10 this assistant.
On a Dell the F-keys may need Fn+Esc pressed once.
The lock screen asks for the password and the USB key; if the key is lost it asks for the recovery code instead.
Coding mode runs 13:00-18:00 on weekdays (08:00-18:00 weekends); outside that it is free time.

## How to answer
Say when you are not sure. Do not invent commands, file names or settings. This model is small, so for anything risky suggest checking the official docs first.
