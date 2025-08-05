#!/bin/bash
set -e

echo "[*] Updating system..."
sudo apt update && sudo apt full-upgrade -y

echo "[*] Installing core packages..."
sudo apt install -y \
  lightdm xinit x11-xserver-utils \
  matchbox-window-manager zenity whiptail \
  chromium-browser steamlink \
  pegasus-frontend \
  python3-pip python3-evdev \
  bluetooth bluez blueman \
  git curl unzip xdotool wmctrl

echo "[*] Creating directories..."
mkdir -p ~/.config/autostart
mkdir -p ~/.pegasus/config/metadata/collections

echo "[*] Writing app launcher metadata..."
cat <<EOF > ~/.pegasus/config/metadata/collections/apps.pegasus.txt
collection: Media Apps

game: Steam Link
    launch: steamlink
    file: /usr/games/steamlink

game: Jellyfin
    launch: chromium-browser --kiosk http://localhost:8096
    file: /usr/bin/chromium-browser

game: Xbox Cloud Gaming
    launch: chromium-browser --kiosk https://xbox.com/play
    file: /usr/bin/chromium-browser
EOF

echo "[*] Setting up Pegasus autostart..."
cat <<EOF > ~/.config/autostart/pegasus.desktop
[Desktop Entry]
Type=Application
Exec=/usr/bin/pegasus-fe
Name=Pegasus
X-GNOME-Autostart-enabled=true
EOF

echo "[*] Adding Select+Start exit script..."
sudo tee /usr/local/bin/controller-exit-watcher.py > /dev/null <<'PYEOF'
#!/usr/bin/env python3
import evdev
from evdev import InputDevice, categorize, ecodes
import subprocess
import time

def find_gamepad():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for dev in devices:
        if 'Xbox' in dev.name or 'Gamepad' in dev.name:
            return dev
    return None

gamepad = find_gamepad()
if not gamepad:
    exit(1)

buttons = set()
for event in gamepad.read_loop():
    if event.type == ecodes.EV_KEY:
        keyevent = categorize(event)
        if keyevent.keystate == keyevent.key_down:
            buttons.add(keyevent.keycode)
        elif keyevent.keystate == keyevent.key_up:
            buttons.discard(keyevent.keycode)

        if 'BTN_SELECT' in buttons and 'BTN_START' in buttons:
            subprocess.call(['pkill', 'chromium'])
            subprocess.call(['xdotool', 'key', 'Escape'])
            time.sleep(1)
PYEOF

sudo chmod +x /usr/local/bin/controller-exit-watcher.py

echo "[*] Creating systemd service for exit watcher..."
sudo tee /etc/systemd/system/controller-exit-watcher.service > /dev/null <<EOF
[Unit]
Description=Controller Exit Watcher
After=multi-user.target

[Service]
ExecStart=/usr/local/bin/controller-exit-watcher.py
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable controller-exit-watcher.service

echo "[*] Installing onscreen keyboard toggle script..."
sudo tee /usr/local/bin/toggle-keyboard.sh > /dev/null <<'EOF'
#!/bin/bash
if pgrep matchbox-keyboard; then
    pkill matchbox-keyboard
else
    matchbox-keyboard &
fi
EOF

sudo chmod +x /usr/local/bin/toggle-keyboard.sh

echo "[*] Installing controller pairing listener..."
sudo tee /usr/local/bin/bt-xbox-pair.sh > /dev/null <<'EOF'
#!/bin/bash
bluetoothctl power on
while true; do
    DEV=$(bluetoothctl devices | grep -i xbox | awk '{print $2}')
    if [ -n "$DEV" ]; then
        INFO=$(bluetoothctl info "$DEV")
        if [[ "$INFO" == *"not connected"* ]]; then
            if command -v zenity &>/dev/null && [ "$DISPLAY" ]; then
                zenity --question --text="Xbox controller found. Pair now?" --timeout=10
                [ $? -eq 0 ] && bluetoothctl pair "$DEV" && bluetoothctl trust "$DEV" && bluetoothctl connect "$DEV"
            else
                whiptail --yesno "Xbox controller found. Pair now?" 10 60
                [ $? -eq 0 ] && bluetoothctl pair "$DEV" && bluetoothctl trust "$DEV" && bluetoothctl connect "$DEV"
            fi
        fi
    fi
    sleep 5
done
EOF

sudo chmod +x /usr/local/bin/bt-xbox-pair.sh

echo "[*] Creating systemd service for auto-pair..."
sudo tee /etc/systemd/system/bt-xbox-pair.service > /dev/null <<EOF
[Unit]
Description=Auto-pair Xbox controllers on detection
After=bluetooth.target

[Service]
ExecStart=/usr/local/bin/bt-xbox-pair.sh
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable bt-xbox-pair.service

echo "[*] Setup complete. Reboot to launch Pegasus."
