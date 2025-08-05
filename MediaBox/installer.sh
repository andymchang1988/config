#!/bin/bash
set -e

MEDIABOX_USER="mediabox"
MEDIABOX_PASS="MediaBox2025!1"
HOSTNAME="mbox"
INSTALL_DIR="/opt/mediabox"
FALLBACK_DIR="$HOME/mbox-install"
SERVICE_NAME="mediabox-launcher"
ELECTRON_VERSION="28.2.3"

APPS_JSON='[
  {
    "name": "Jellyfin",
    "exec": "flatpak run org.jellyfin.JellyfinMediaPlayer",
    "icon": "https://jellyfin.org/images/logos/icon.png"
  },
  {
    "name": "YouTube",
    "exec": "chromium-browser --app=https://youtube.com",
    "icon": "https://www.youtube.com/s/desktop/6cd4b62e/img/favicon_144x144.png"
  },
  {
    "name": "Netflix",
    "exec": "chromium-browser --app=https://www.netflix.com",
    "icon": "https://assets.nflxext.com/us/ffe/siteui/common/icons/nficon2016.png"
  },
  {
    "name": "Xbox Cloud Gaming",
    "exec": "chromium-browser --app=https://xbox.com/play",
    "icon": "https://compass-ssl.xbox.com/assets/6b/85/6b85c8b0-4a8c-4d4e-8850-93a90d4f667a.svg"
  },
  {
    "name": "RetroArch",
    "exec": "flatpak run org.libretro.RetroArch",
    "icon": "https://www.libretro.com/wp-content/uploads/2015/01/retroarch-150x150.png"
  },
  {
    "name": "SteamLink",
    "exec": "flatpak run com.valvesoftware.SteamLink",
    "icon": "https://upload.wikimedia.org/wikipedia/commons/8/8d/Steam_icon_logo.svg"
  },
  {
    "name": "Join WiFi",
    "exec": "'$INSTALL_DIR/scripts/wifi_gui.sh'",
    "icon": "network-wireless"
  },
  {
    "name": "Shutdown",
    "exec": "systemctl poweroff",
    "icon": "system-shutdown"
  },
  {
    "name": "Reboot",
    "exec": "systemctl reboot",
    "icon": "system-reboot"
  }
]'
SETTINGS_JSON='{
  "theme": "dark",
  "resolution": "auto"
}'

if [[ $EUID -ne 0 ]]; then
  echo "Run this as root (sudo bash installer.sh)."
  exit 1
fi

### HDMI force-hotplug config ###
echo "[*] Configuring /boot/config.txt for forced HDMI hotplug..."
CONFIG_TXT="/boot/config.txt"
function ensure_config_line() {
  local key="$1"
  local value="$2"
  grep -q "^$key=" "$CONFIG_TXT" && sudo sed -i "s|^$key=.*|$key=$value|" "$CONFIG_TXT" || echo "$key=$value" | sudo tee -a "$CONFIG_TXT"
}
ensure_config_line "hdmi_force_hotplug" "1"
ensure_config_line "hdmi_group" "2"
ensure_config_line "hdmi_mode" "82"
echo "[*] /boot/config.txt now forces HDMI output at 1080p, even if unplugged."

### Install dependencies ###
echo "[*] Installing dependencies..."
apt update && apt install -y sudo curl wget build-essential git xorg libnss3 libatk-bridge2.0-0 libgtk-3-0 libgbm1 \
  libasound2 zenity policykit-1 avahi-daemon xboxdrv joystick \
  openssh-server flatpak chromium-browser gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  python3 python3-pip nodejs npm

### User creation and lockdown ###
id -u $MEDIABOX_USER >/dev/null 2>&1 || useradd -m -s /bin/bash $MEDIABOX_USER
echo "$MEDIABOX_USER:$MEDIABOX_PASS" | chpasswd
usermod -aG sudo $MEDIABOX_USER

# Set all other users (except root/mediabox) to nologin
echo "[*] Disabling login for all users except 'mediabox' and 'root'..."
getent passwd | awk -F: '{print $1}' | while read user; do
  if [[ "$user" != "root" && "$user" != "$MEDIABOX_USER" ]]; then
    sudo usermod -s /usr/sbin/nologin "$user" 2>/dev/null || true
  fi
done
echo "Access denied. Please use the 'mediabox' account to log in." | sudo tee /etc/nologin.txt

### Autologin as mediabox in GUI ###
echo "[*] Setting LightDM to autologin as $MEDIABOX_USER..."
if ! grep -q '^\[Seat:\*\]' /etc/lightdm/lightdm.conf; then
  echo "[Seat:*]" | sudo tee -a /etc/lightdm/lightdm.conf
fi
sudo sed -i '/^autologin-user=/d' /etc/lightdm/lightdm.conf
echo "autologin-user=$MEDIABOX_USER" | sudo tee -a /etc/lightdm/lightdm.conf

### SSH: ONLY mediabox can log in ###
if ! grep -q "^AllowUsers $MEDIABOX_USER" /etc/ssh/sshd_config; then
  echo "AllowUsers $MEDIABOX_USER" | sudo tee -a /etc/ssh/sshd_config
  sudo systemctl reload ssh
fi

### Hostname ###
echo "$HOSTNAME" > /etc/hostname
hostnamectl set-hostname "$HOSTNAME"
if ! grep -q "$HOSTNAME" /etc/hosts; then
  echo "127.0.1.1 $HOSTNAME.local $HOSTNAME" >> /etc/hosts
fi

### Enable services ###
systemctl enable ssh
systemctl start ssh
systemctl enable avahi-daemon
systemctl start avahi-daemon

### Xboxdrv systemd ###
cat > /etc/systemd/system/xboxdrv.service <<EOF
[Unit]
Description=Xbox Controller Driver Daemon
After=network.target

[Service]
ExecStart=/usr/bin/xboxdrv --daemon --silent
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xboxdrv
systemctl start xboxdrv

### Install dir ###
if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
  TARGET_DIR="$INSTALL_DIR"
else
  TARGET_DIR="$FALLBACK_DIR"
  mkdir -p "$TARGET_DIR"
fi
chown -R $MEDIABOX_USER:$MEDIABOX_USER "$TARGET_DIR"
mkdir -p "$TARGET_DIR/scripts" "$TARGET_DIR/logs"

### Bootstrap script (background) ###
cat > "$TARGET_DIR/scripts/bootstrap.sh" <<'EOF'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt update

if ! command -v flatpak >/dev/null 2>&1; then
  apt install -y flatpak
fi
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.jellyfin.JellyfinMediaPlayer org.libretro.RetroArch com.valvesoftware.SteamLink
apt install -y gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
apt install -y chromium-browser
EOF
chmod +x "$TARGET_DIR/scripts/bootstrap.sh"

### WiFi join script ###
cat > "$TARGET_DIR/scripts/wifi_gui.sh" <<'EOF'
#!/bin/bash

# Scan and present SSID list
SSID=$(nmcli --fields SSID,SECURITY dev wifi list | awk 'NR>1 {print $1}' | sort | uniq | grep -v '^--$' | zenity --list --title="WiFi Networks" --column="SSID" --height=400 --width=400)

if [[ -z "$SSID" ]]; then
  zenity --error --text="No network selected."
  exit 1
fi

# Check if this network requires a password
SEC=$(nmcli -g SECURITY dev wifi list | grep -m1 "$SSID")
if [[ "$SEC" == "WPA"* || "$SEC" == "WEP" || "$SEC" == "RSN" ]]; then
  PASS=$(zenity --entry --title="WiFi Password" --text="Enter password for $SSID:" --hide-text)
  if [[ -z "$PASS" ]]; then
    zenity --error --text="No password entered."
    exit 1
  fi
  nmcli dev wifi connect "$SSID" password "$PASS" && zenity --info --text="Connected to $SSID!" || zenity --error --text="Failed to connect to $SSID."
else
  nmcli dev wifi connect "$SSID" && zenity --info --text="Connected to $SSID!" || zenity --error --text="Failed to connect to $SSID."
fi
EOF

chmod +x "$TARGET_DIR/scripts/wifi_gui.sh"


### JSON config files ###
echo "$APPS_JSON" > "$TARGET_DIR/apps.json"
echo "$SETTINGS_JSON" > "$TARGET_DIR/settings.json"
chown $MEDIABOX_USER:$MEDIABOX_USER "$TARGET_DIR"/*.json

### Electron app ###
cat > "$TARGET_DIR/package.json" <<EOF
{
  "name": "mediabox-launcher",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": {
    "start": "electron ."
  },
  "dependencies": {},
  "devDependencies": {
    "electron": "^$ELECTRON_VERSION"
  }
}
EOF

cat > "$TARGET_DIR/main.js" <<'EOF'
const { app, BrowserWindow } = require('electron')
const path = require('path')
app.disableHardwareAcceleration()
function createWindow () {
  const win = new BrowserWindow({
    width: 1280,
    height: 720,
    fullscreen: true,
    kiosk: true,
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  })
  win.loadFile('index.html')
}
app.on('ready', createWindow)
EOF

cat > "$TARGET_DIR/renderer.js" <<'EOF'
const fs = require('fs');
const apps = JSON.parse(fs.readFileSync('./apps.json'));
const grid = document.getElementById('app-grid');
apps.forEach(app => {
  let btn = document.createElement('button');
  btn.className = 'tile';
  btn.innerHTML = `<img src="${app.icon}" /><span>${app.name}</span>`;
  btn.onclick = () => {
    require('child_process').exec(app.exec, (err) => {});
    setTimeout(() => location.reload(), 5000);
  };
  grid.appendChild(btn);
});
EOF

cat > "$TARGET_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>MediaBox Dashboard</title>
  <style>
    body { background: #1e1e1e; color: #fff; margin: 0; font-family: sans-serif; }
    #app-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 2em; padding: 2em; }
    .tile { background: #232323; border-radius: 24px; box-shadow: 0 4px 16px #1116; padding: 2em; display: flex; flex-direction: column; align-items: center; border: none; cursor: pointer; transition: 0.2s; }
    .tile img { width: 64px; height: 64px; margin-bottom: 1em; }
    .tile:focus, .tile:hover { background: #2d3748; outline: 2px solid #5f99fc; }
    .tile span { margin-top: .5em; font-size: 1.2em; }
  </style>
</head>
<body>
  <div id="app-grid"></div>
  <script src="renderer.js"></script>
</body>
</html>
EOF

cd "$TARGET_DIR"
sudo -u $MEDIABOX_USER npm install --omit=dev --unsafe-perm
sudo -u $MEDIABOX_USER npm install electron@$ELECTRON_VERSION --unsafe-perm

chown -R $MEDIABOX_USER:$MEDIABOX_USER "$TARGET_DIR"

### Systemd launcher service ###
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=MediaBox Electron Launcher
After=network-online.target graphical.target avahi-daemon.service xboxdrv.service

[Service]
User=$MEDIABOX_USER
Environment=DISPLAY=:0
WorkingDirectory=$TARGET_DIR
ExecStart=/usr/bin/npm start
Restart=always

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME

### Autostart for desktop UI ###
AUTOSTART_DIR="/home/$MEDIABOX_USER/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/mediabox.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=MediaBox Launcher
Exec=/usr/bin/npm start --prefix $TARGET_DIR
X-GNOME-Autostart-enabled=true
EOF
chown -R $MEDIABOX_USER:$MEDIABOX_USER "$AUTOSTART_DIR"

### Kick off background app installer ###
nohup "$TARGET_DIR/scripts/bootstrap.sh" > "$TARGET_DIR/logs/bootstrap.log" 2>&1 &

### Verification ###
echo
echo "=================================="
echo "[*] VERIFYING INSTALLATION..."
sleep 2

FAIL=0

for svc in ssh avahi-daemon xboxdrv $SERVICE_NAME; do
  systemctl is-active --quiet $svc || { echo "Service $svc not active!"; FAIL=1; }
done

for file in "$TARGET_DIR/main.js" "$TARGET_DIR/index.html" "$TARGET_DIR/renderer.js" "$TARGET_DIR/apps.json" "$TARGET_DIR/settings.json"; do
  [[ -f "$file" ]] || { echo "Missing file: $file"; FAIL=1; }
done

echo "[*] Quick test: Electron dashboard will try to run (headless test)..."
sudo -u $MEDIABOX_USER bash -c "export DISPLAY=:0; cd $TARGET_DIR; timeout 10s npm start" &> "$TARGET_DIR/logs/frontend_test.log" || true
grep -q 'Electron' "$TARGET_DIR/logs/frontend_test.log" || { 
  echo "❌ Electron dashboard did not start cleanly. See $TARGET_DIR/logs/frontend_test.log"; 
  FAIL=1; 
}

if [[ ! -f "$AUTOSTART_DIR/mediabox.desktop" ]]; then
  echo "❌ Autostart .desktop file missing from $AUTOSTART_DIR"
  FAIL=1
fi

if [[ $FAIL -ne 0 ]]; then
  echo
  echo "---------------------"
  echo "❌ INSTALL FAILED VERIFICATION!"
  echo "See errors above."
  echo "--- Electron Frontend Test Log ---"
  tail -30 "$TARGET_DIR/logs/frontend_test.log" || true
  echo
  exit 1
fi

echo
echo "====================================="
echo "✅  MediaBox installation complete!"
echo "User: $MEDIABOX_USER / Pass: $MEDIABOX_PASS"
echo "Dashboard will launch after next reboot/login."
echo "Hostname: $HOSTNAME.local"
echo "Install dir: $TARGET_DIR"
echo "To re-run Electron dashboard: sudo -u $MEDIABOX_USER npm start --prefix $TARGET_DIR"
echo "====================================="
exit 0
