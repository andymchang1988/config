#!/bin/bash
# MediaBox Debian Package Builder
# Creates a .deb package for easy installation

# Package information
PACKAGE_NAME="mediabox-launcher"
PACKAGE_VERSION="1.0.0"
PACKAGE_ARCH="arm64"
MAINTAINER="MediaBox Team <mediabox@example.com>"
DESCRIPTION="Full-screen media center launcher for Raspberry Pi 5"

# Create package directory structure
create_package_structure() {
    echo "Creating Debian package structure..."
    
    PKG_DIR="${PACKAGE_NAME}_${PACKAGE_VERSION}_${PACKAGE_ARCH}"
    
    mkdir -p "$PKG_DIR"/{DEBIAN,opt/mediabox/{scripts,logs,config,assets},etc/systemd/system,home/mediabox/.config/openbox}
    
    # Create DEBIAN/control file
    cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $PACKAGE_VERSION
Architecture: $PACKAGE_ARCH
Maintainer: $MAINTAINER
Depends: nodejs (>= 14), npm, chromium-browser, xorg, openbox, pulseaudio, ssh, avahi-daemon, flatpak, zenity, xboxdrv, unclutter
Recommends: retroarch, steamlink
Section: multimedia
Priority: optional
Homepage: https://github.com/mediabox-pi5
Description: $DESCRIPTION
 MediaBox Launcher is a full-screen, controller-friendly dashboard designed
 for Raspberry Pi 5. It provides a unified interface for media consumption
 and gaming, with support for Xbox controllers, WiFi configuration, and
 remote access via SSH.
 .
 Features:
  - Electron-based full-screen launcher
  - Xbox controller navigation
  - Jellyfin, YouTube, Netflix, Xbox Cloud Gaming
  - RetroArch retro gaming
  - WiFi configuration GUI
  - SSH/SFTP remote access
  - Auto-boot to dashboard
EOF

    # Create preinst script
    cat > "$PKG_DIR/DEBIAN/preinst" << 'EOF'
#!/bin/bash
set -e

echo "Preparing MediaBox installation..."

# Stop any existing services
systemctl stop mediabox-launcher 2>/dev/null || true
systemctl disable mediabox-launcher 2>/dev/null || true

exit 0
EOF

    # Create postinst script
    cat > "$PKG_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

MEDIABOX_USER="mediabox"
MEDIABOX_PASS="MediaBox2025!1"
INSTALL_DIR="/opt/mediabox"
HOSTNAME="mbox"

echo "Configuring MediaBox system..."

# Create mediabox user if it doesn't exist
if ! id "$MEDIABOX_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$MEDIABOX_USER"
    echo "$MEDIABOX_USER:$MEDIABOX_PASS" | chpasswd
    usermod -aG sudo,audio,video,input,plugdev "$MEDIABOX_USER"
fi

# Set hostname
hostnamectl set-hostname "$HOSTNAME"
if ! grep -q "mbox.local" /etc/hosts; then
    echo "127.0.1.1 $HOSTNAME.local $HOSTNAME" >> /etc/hosts
fi

# Install npm dependencies
cd "$INSTALL_DIR"
npm install --production

# Set ownership
chown -R "$MEDIABOX_USER:$MEDIABOX_USER" "$INSTALL_DIR"
chown -R "$MEDIABOX_USER:$MEDIABOX_USER" "/home/$MEDIABOX_USER"

# Setup auto-login
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOFINNER
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $MEDIABOX_USER --noclear %I \$TERM
EOFINNER

# Setup sudoers
cat > /etc/sudoers.d/mediabox << EOFINNER
mediabox ALL=(ALL) NOPASSWD: /sbin/shutdown
mediabox ALL=(ALL) NOPASSWD: /sbin/reboot
mediabox ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart mediabox-launcher
mediabox ALL=(ALL) NOPASSWD: /usr/bin/nmtui
EOFINNER

# Enable services
systemctl enable ssh
systemctl enable avahi-daemon
systemctl enable xboxdrv
systemctl enable mediabox-launcher

# Setup Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Start background installation
echo "Starting background app installation..."
nohup /opt/mediabox/scripts/bootstrap.sh > /opt/mediabox/logs/bootstrap.log 2>&1 &

echo "MediaBox installation complete!"
echo "Reboot to start the system: sudo reboot"
echo "SSH access: ssh mediabox@mbox.local (password: MediaBox2025!1)"

exit 0
EOF

    # Create prerm script
    cat > "$PKG_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

echo "Stopping MediaBox services..."

systemctl stop mediabox-launcher 2>/dev/null || true
systemctl disable mediabox-launcher 2>/dev/null || true

exit 0
EOF

    # Create postrm script
    cat > "$PKG_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

if [ "$1" = "purge" ]; then
    echo "Purging MediaBox configuration..."
    
    # Remove sudoers file
    rm -f /etc/sudoers.d/mediabox
    
    # Remove auto-login configuration
    rm -rf /etc/systemd/system/getty@tty1.service.d
    
    # Reload systemd
    systemctl daemon-reload
    
    echo "MediaBox purged. User 'mediabox' and /opt/mediabox preserved."
    echo "Run 'sudo userdel -r mediabox' to remove user if desired."
fi

exit 0
EOF

    # Make scripts executable
    chmod 755 "$PKG_DIR/DEBIAN"/{postinst,preinst,prerm,postrm}
    
    # Copy application files to package
    echo "Copying application files..."
    
    # Copy package.json
    cat > "$PKG_DIR/opt/mediabox/package.json" << 'EOF'
{
  "name": "mediabox-launcher",
  "version": "1.0.0",
  "description": "MediaBox Pi5 Launcher",
  "main": "main.js",
  "scripts": {
    "start": "electron .",
    "dev": "electron . --dev"
  },
  "keywords": ["mediabox", "raspberry-pi", "launcher"],
  "author": "MediaBox Team",
  "license": "MIT",
  "dependencies": {
    "electron": "^25.0.0"
  }
}
EOF

    # Copy Electron main.js (from the complete installer)
    cp_main_js_to_package "$PKG_DIR"
    
    # Copy HTML interface
    cp_html_to_package "$PKG_DIR"
    
    # Copy apps configuration
    cp_apps_config_to_package "$PKG_DIR"
    
    # Copy scripts
    cp_scripts_to_package "$PKG_DIR"
    
    # Copy systemd service
    cp_systemd_service_to_package "$PKG_DIR"
    
    # Copy user configuration files
    cp_user_configs_to_package "$PKG_DIR"
    
    echo "Package structure created: $PKG_DIR"
}

# Function to copy main.js to package
cp_main_js_to_package() {
    local pkg_dir="$1"
    cat > "$pkg_dir/opt/mediabox/main.js" << 'EOF'
const { app, BrowserWindow, ipcMain, shell } = require('electron');
const { exec, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

let mainWindow;
let launchedProcess = null;

function createWindow() {
    mainWindow = new BrowserWindow({
        width: 1920,
        height: 1080,
        fullscreen: true,
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false,
            enableRemoteModule: true
        },
        show: false,
        frame: false,
        titleBarStyle: 'hidden',
        backgroundColor: '#0f0f23'
    });

    mainWindow.loadFile('index.html');
    mainWindow.setMenuBarVisibility(false);
    
    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
        setTimeout(() => {
            mainWindow.webContents.insertCSS('* { cursor: none !important; }');
        }, 3000);
    });

    mainWindow.on('closed', () => {
        mainWindow = null;
    });

    mainWindow.webContents.setWindowOpenHandler(() => {
        return { action: 'deny' };
    });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') {
        app.quit();
    }
});

app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
        createWindow();
    }
});

// IPC handlers
ipcMain.handle('launch-app', async (event, appCommand) => {
    return new Promise((resolve, reject) => {
        console.log('Launching:', appCommand);
        
        if (appCommand.includes('sudo')) {
            exec(appCommand, { shell: true }, (error, stdout, stderr) => {
                if (error) {
                    reject(error);
                } else {
                    resolve({ success: true, output: stdout });
                }
            });
        } else {
            const child = spawn(appCommand, [], { 
                shell: true, 
                detached: true,
                stdio: 'ignore'
            });
            
            child.unref();
            launchedProcess = child;
            
            child.on('exit', (code) => {
                console.log(`App exited with code ${code}`);
                launchedProcess = null;
                if (mainWindow) {
                    mainWindow.focus();
                }
            });
            
            resolve({ success: true, pid: child.pid });
        }
    });
});

ipcMain.handle('get-system-info', async () => {
    return {
        hostname: require('os').hostname(),
        platform: process.platform,
        arch: process.arch,
        resolution: '1920x1080'
    };
});

ipcMain.handle('shutdown', async () => {
    exec('sudo shutdown now');
});

ipcMain.handle('reboot', async () => {
    exec('sudo reboot');
});

ipcMain.handle('load-apps', async () => {
    try {
        const appsPath = path.join(__dirname, 'config', 'apps.json');
        const appsData = fs.readFileSync(appsPath, 'utf8');
        return JSON.parse(appsData);
    } catch (error) {
        console.error('Error loading apps:', error);
        return [];
    }
});

app.on('before-quit', (event) => {
    if (launchedProcess) {
        return;
    }
    event.preventDefault();
});
EOF
}

# Function to copy HTML to package  
cp_html_to_package() {
    local pkg_dir="$1"
    # Copy the complete HTML from the earlier artifact
    cat > "$pkg_dir/opt/mediabox/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MediaBox Launcher</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #0f0f23 0%, #1a1a2e 50%, #16213e 100%);
            color: #ffffff;
            overflow: hidden;
            cursor: none;
        }

        .container {
            width: 100vw;
            height: 100vh;
            display: flex;
            flex-direction: column;
            padding: 2rem;
        }

        .header {
            text-align: center;
            margin-bottom: 3rem;
        }

        .logo {
            font-size: 3rem;
            font-weight: bold;
            background: linear-gradient(45deg, #ff6b6b, #4ecdc4, #45b7d1);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }

        .subtitle {
            font-size: 1.2rem;
            opacity: 0.8;
            color: #a0a0a0;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 2rem;
            flex: 1;
            padding: 0 2rem;
            overflow-y: auto;
        }

        .app-tile {
            background: rgba(255, 255, 255, 0.05);
            border: 2px solid rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            padding: 2rem;
            text-align: center;
            transition: all 0.3s ease;
            cursor: pointer;
            backdrop-filter: blur(10px);
            position: relative;
            overflow: hidden;
        }

        .app-tile:hover, .app-tile.selected {
            transform: translateY(-5px) scale(1.02);
            border-color: #4ecdc4;
            box-shadow: 0 20px 40px rgba(78, 205, 196, 0.3);
        }

        .app-tile::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: linear-gradient(45deg, transparent, rgba(78, 205, 196, 0.1), transparent);
            opacity: 0;
            transition: opacity 0.3s ease;
        }

        .app-tile:hover::before, .app-tile.selected::before {
            opacity: 1;
        }

        .app-icon {
            font-size: 4rem;
            margin-bottom: 1rem;
            display: block;