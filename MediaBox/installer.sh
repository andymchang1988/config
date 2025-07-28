#!/bin/bash
# MediaBox Launcher - Complete Pi5 Installer
# Run this script on a fresh Raspberry Pi OS 64-bit installation
# Usage: curl -sSL https://your-domain.com/install.sh | sudo bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MEDIABOX_USER="mediabox"
MEDIABOX_PASS="MediaBox2025!1"
INSTALL_DIR="/opt/mediabox"
FALLBACK_DIR="$HOME/mbox-install"
HOSTNAME="mbox"
SERVICE_NAME="mediabox-launcher"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Create installation directory
setup_directories() {
    log "Setting up directories..."
    
    if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        ACTUAL_INSTALL_DIR="$INSTALL_DIR"
    else
        warn "Cannot create $INSTALL_DIR, using fallback"
        ACTUAL_INSTALL_DIR="$FALLBACK_DIR"
        mkdir -p "$ACTUAL_INSTALL_DIR"
    fi
    
    mkdir -p "$ACTUAL_INSTALL_DIR"/{scripts,logs,config,assets}
    log "Installation directory: $ACTUAL_INSTALL_DIR"
}

# Create mediabox user
create_user() {
    log "Creating mediabox user..."
    
    if id "$MEDIABOX_USER" &>/dev/null; then
        log "User $MEDIABOX_USER already exists"
    else
        useradd -m -s /bin/bash "$MEDIABOX_USER"
        echo "$MEDIABOX_USER:$MEDIABOX_PASS" | chpasswd
        usermod -aG sudo,audio,video,input,plugdev "$MEDIABOX_USER"
        log "Created user: $MEDIABOX_USER"
    fi
}

# Set hostname
set_hostname() {
    log "Setting hostname to $HOSTNAME..."
    hostnamectl set-hostname "$HOSTNAME"
    echo "127.0.1.1 $HOSTNAME.local $HOSTNAME" >> /etc/hosts
}

# Update system and install dependencies
install_dependencies() {
    log "Updating system and installing dependencies..."
    
    apt update && apt upgrade -y
    
    # Core system packages
    apt install -y \
        curl wget git \
        nodejs npm \
        chromium-browser \
        xorg xserver-xorg-video-all \
        openbox \
        pulseaudio pulseaudio-utils \
        alsa-utils \
        ssh avahi-daemon \
        zenity \
        flatpak \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
        python3-pip \
        unclutter \
        xboxdrv
    
    # Install Electron globally
    npm install -g electron
    
    log "Dependencies installed successfully"
}

# Setup Flatpak
setup_flatpak() {
    log "Setting up Flatpak..."
    
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    # Install Jellyfin Theater in background
    nohup flatpak install -y flathub org.jellyfin.JellyfinTheater > "$ACTUAL_INSTALL_DIR/logs/flatpak.log" 2>&1 &
}

# Create main Electron application
create_electron_app() {
    log "Creating Electron application..."
    
    # Create package.json
    cat > "$ACTUAL_INSTALL_DIR/package.json" << 'EOF'
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
    "electron": "^latest"
  }
}
EOF

    # Create main.js (Electron main process)
    cat > "$ACTUAL_INSTALL_DIR/main.js" << 'EOF'
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
    
    // Hide menu bar
    mainWindow.setMenuBarVisibility(false);
    
    // Show when ready
    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
        
        // Hide cursor after 3 seconds
        setTimeout(() => {
            mainWindow.webContents.insertCSS('* { cursor: none !important; }');
        }, 3000);
    });

    // Handle window closed
    mainWindow.on('closed', () => {
        mainWindow = null;
    });

    // Prevent new window creation
    mainWindow.webContents.setWindowOpenHandler(() => {
        return { action: 'deny' };
    });
}

// App event handlers
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

// IPC handlers for launching apps
ipcMain.handle('launch-app', async (event, appCommand) => {
    return new Promise((resolve, reject) => {
        console.log('Launching:', appCommand);
        
        // Special handling for different app types
        if (appCommand.includes('sudo')) {
            // Handle system commands
            exec(appCommand, { shell: true }, (error, stdout, stderr) => {
                if (error) {
                    reject(error);
                } else {
                    resolve({ success: true, output: stdout });
                }
            });
        } else {
            // Launch regular applications
            const child = spawn(appCommand, [], { 
                shell: true, 
                detached: true,
                stdio: 'ignore'
            });
            
            child.unref();
            launchedProcess = child;
            
            // Monitor process
            child.on('exit', (code) => {
                console.log(`App exited with code ${code}`);
                launchedProcess = null;
                // Return focus to launcher
                if (mainWindow) {
                    mainWindow.focus();
                }
            });
            
            resolve({ success: true, pid: child.pid });
        }
    });
});

// System info handlers
ipcMain.handle('get-system-info', async () => {
    return {
        hostname: require('os').hostname(),
        platform: process.platform,
        arch: process.arch,
        resolution: '1920x1080' // Will be detected by renderer
    };
});

// Power management
ipcMain.handle('shutdown', async () => {
    exec('sudo shutdown now');
});

ipcMain.handle('reboot', async () => {
    exec('sudo reboot');
});

// Load apps configuration
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

// Prevent app from quitting when all windows are closed (keep running for controller)
app.on('before-quit', (event) => {
    if (launchedProcess) {
        // Allow app to quit if we launched something
        return;
    }
    // Prevent quit for controller navigation
    event.preventDefault();
});
EOF

    # Copy the HTML file from the previous artifact (updated with IPC calls)
    cat > "$ACTUAL_INSTALL_DIR/index.html" << 'EOF'
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
        }

        .app-title {
            font-size: 1.5rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: #ffffff;
        }

        .app-description {
            font-size: 0.9rem;
            opacity: 0.7;
            color: #cccccc;
        }

        .status-bar {
            position: fixed;
            bottom: 20px;
            left: 20px;
            right: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: rgba(0, 0, 0, 0.5);
            padding: 1rem 2rem;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            font-size: 0.9rem;
        }

        .system-info {
            display: flex;
            gap: 2rem;
        }

        .controls-hint {
            opacity: 0.8;
        }

        .loading {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            display: none;
            text-align: center;
            z-index: 1000;
        }

        .spinner {
            width: 50px;
            height: 50px;
            border: 3px solid rgba(78, 205, 196, 0.3);
            border-top: 3px solid #4ecdc4;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin: 0 auto 1rem;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .notification {
            position: fixed;
            top: 20px;
            right: 20px;
            background: rgba(78, 205, 196, 0.9);
            color: #000;
            padding: 1rem 2rem;
            border-radius: 10px;
            transform: translateX(100%);
            transition: transform 0.3s ease;
            z-index: 1000;
        }

        .notification.show {
            transform: translateX(0);
        }

        @media (max-width: 1366px) {
            .grid {
                grid-template-columns: repeat(3, 1fr);
            }
        }

        @media (max-width: 1024px) {
            .grid {
                grid-template-columns: repeat(2, 1fr);
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">🎮 MediaBox</div>
            <div class="subtitle">Pi5 Edition - Your Entertainment Hub</div>
        </div>
        
        <div class="grid" id="appGrid">
            <!-- Apps will be loaded dynamically -->
        </div>
    </div>

    <div class="status-bar">
        <div class="system-info">
            <span id="hostname">mbox.local</span>
            <span id="resolution">1920x1080</span>
            <span id="controller">🎮 Ready</span>
        </div>
        <div class="controls-hint">
            Use controller D-pad or arrow keys • A/Enter to launch • B/Esc to back
        </div>
    </div>

    <div class="loading" id="loading">
        <div class="spinner"></div>
        <div>Launching...</div>
    </div>

    <div class="notification" id="notification"></div>

    <script>
        const { ipcRenderer } = require('electron');

        class MediaBoxLauncher {
            constructor() {
                this.apps = [];
                this.selectedIndex = 0;
                this.controllerConnected = false;
                this.init();
            }

            async init() {
                await this.loadApps();
                this.renderApps();
                this.setupEventListeners();
                this.detectResolution();
                this.checkControllerStatus();
                await this.updateSystemInfo();
            }

            async loadApps() {
                try {
                    this.apps = await ipcRenderer.invoke('load-apps');
                } catch (error) {
                    console.error('Failed to load apps:', error);
                    // Use default apps as fallback
                    this.apps = [
                        {
                            id: 'jellyfin',
                            title: 'Jellyfin',
                            description: 'Media Server & Player',
                            icon: '🎬',
                            command: 'flatpak run org.jellyfin.JellyfinTheater',
                            category: 'media'
                        },
                        {
                            id: 'youtube',
                            title: 'YouTube',
                            description: 'Watch videos online',
                            icon: '📺',
                            command: 'chromium-browser --kiosk --app=https://youtube.com/tv',
                            category: 'media'
                        },
                        {
                            id: 'netflix',
                            title: 'Netflix',
                            description: 'Streaming service',
                            icon: '🎭',
                            command: 'chromium-browser --kiosk --app=https://netflix.com',
                            category: 'media'
                        },
                        {
                            id: 'xbox-cloud',
                            title: 'Xbox Cloud',
                            description: 'Game streaming',
                            icon: '☁️',
                            command: 'chromium-browser --kiosk --app=https://xbox.com/play',
                            category: 'gaming'
                        },
                        {
                            id: 'retroarch',
                            title: 'RetroArch',
                            description: 'Retro gaming emulator',
                            icon: '🕹️',
                            command: 'retroarch',
                            category: 'gaming'
                        },
                        {
                            id: 'steamlink',
                            title: 'Steam Link',
                            description: 'PC game streaming',
                            icon: '🚂',
                            command: 'steamlink',
                            category: 'gaming'
                        },
                        {
                            id: 'wifi-config',
                            title: 'WiFi Setup',
                            description: 'Configure network',
                            icon: '📶',
                            command: 'DISPLAY=:0 sudo nmtui',
                            category: 'system'
                        },
                        {
                            id: 'shutdown',
                            title: 'Power',
                            description: 'Shutdown or restart',
                            icon: '⚡',
                            command: 'power',
                            category: 'system'
                        }
                    ];
                }
            }

            renderApps() {
                const grid = document.getElementById('appGrid');
                grid.innerHTML = '';

                this.apps.forEach((app, index) => {
                    const tile = document.createElement('div');
                    tile.className = 'app-tile';
                    tile.dataset.index = index;
                    
                    tile.innerHTML = `
                        <div class="app-icon">${app.icon}</div>
                        <div class="app-title">${app.title}</div>
                        <div class="app-description">${app.description}</div>
                    `;

                    tile.addEventListener('click', () => this.launchApp(index));
                    grid.appendChild(tile);
                });

                this.updateSelection();
            }

            setupEventListeners() {
                document.addEventListener('keydown', (e) => {
                    switch(e.key) {
                        case 'ArrowUp':
                            e.preventDefault();
                            this.navigate(-4);
                            break;
                        case 'ArrowDown':
                            e.preventDefault();
                            this.navigate(4);
                            break;
                        case 'ArrowLeft':
                            e.preventDefault();
                            this.navigate(-1);
                            break;
                        case 'ArrowRight':
                            e.preventDefault();
                            this.navigate(1);
                            break;
                        case 'Enter':
                        case ' ':
                            e.preventDefault();
                            this.launchApp(this.selectedIndex);
                            break;
                        case 'Escape':
                            e.preventDefault();
                            this.showNotification('Use Power tile to shutdown');
                            break;
                    }
                });

                window.addEventListener('gamepadconnected', (e) => {
                    this.controllerConnected = true;
                    this.updateControllerStatus();
                    this.showNotification('Controller connected!');
                });

                window.addEventListener('gamepaddisconnected', (e) => {
                    this.controllerConnected = false;
                    this.updateControllerStatus();
                    this.showNotification('Controller disconnected');
                });
            }

            navigate(direction) {
                const newIndex = this.selectedIndex + direction;
                if (newIndex >= 0 && newIndex < this.apps.length) {
                    this.selectedIndex = newIndex;
                    this.updateSelection();
                }
            }

            updateSelection() {
                const tiles = document.querySelectorAll('.app-tile');
                tiles.forEach((tile, index) => {
                    tile.classList.toggle('selected', index === this.selectedIndex);
                });

                if (tiles[this.selectedIndex]) {
                    tiles[this.selectedIndex].scrollIntoView({
                        behavior: 'smooth',
                        block: 'center'
                    });
                }
            }

            async launchApp(index) {
                const app = this.apps[index];
                if (!app) return;

                if (app.command === 'power') {
                    this.showPowerMenu();
                    return;
                }

                this.showLoading();
                this.showNotification(`Launching ${app.title}...`);

                try {
                    const result = await ipcRenderer.invoke('launch-app', app.command);
                    this.hideLoading();
                    
                    if (result.success) {
                        this.showNotification(`${app.title} launched successfully!`);
                    } else {
                        this.showNotification(`Failed to launch ${app.title}`);
                    }
                } catch (error) {
                    this.hideLoading();
                    this.showNotification(`Error launching ${app.title}: ${error.message}`);
                }
            }

            async showPowerMenu() {
                const choice = confirm('Choose power option:\nOK = Shutdown\nCancel = Restart');
                if (choice) {
                    this.showNotification('Shutting down...');
                    await ipcRenderer.invoke('shutdown');
                } else {
                    this.showNotification('Restarting...');
                    await ipcRenderer.invoke('reboot');
                }
            }

            showLoading() {
                document.getElementById('loading').style.display = 'block';
            }

            hideLoading() {
                document.getElementById('loading').style.display = 'none';
            }

            showNotification(message) {
                const notification = document.getElementById('notification');
                notification.textContent = message;
                notification.classList.add('show');
                setTimeout(() => {
                    notification.classList.remove('show');
                }, 3000);
            }

            detectResolution() {
                const resolution = `${screen.width}x${screen.height}`;
                document.getElementById('resolution').textContent = `📺 ${resolution}`;
            }

            updateControllerStatus() {
                const status = this.controllerConnected ? '🎮 Connected' : '🎮 Ready';
                document.getElementById('controller').textContent = status;
            }

            async updateSystemInfo() {
                try {
                    const sysInfo = await ipcRenderer.invoke('get-system-info');
                    document.getElementById('hostname').textContent = `🏠 ${sysInfo.hostname}.local`;
                } catch (error) {
                    console.error('Failed to get system info:', error);
                }
            }

            checkControllerStatus() {
                setInterval(() => {
                    const gamepads = navigator.getGamepads();
                    for (let gamepad of gamepads) {
                        if (gamepad && gamepad.connected) {
                            this.handleControllerInput(gamepad);
                        }
                    }
                }, 100);
            }

            handleControllerInput(gamepad) {
                const buttons = gamepad.buttons;
                
                // Debounce controller input
                if (this.controllerInputCooldown > Date.now()) return;
                
                if (buttons[12] && buttons[12].pressed) { // D-pad up
                    this.navigate(-4);
                    this.controllerInputCooldown = Date.now() + 200;
                } else if (buttons[13] && buttons[13].pressed) { // D-pad down
                    this.navigate(4);
                    this.controllerInputCooldown = Date.now() + 200;
                } else if (buttons[14] && buttons[14].pressed) { // D-pad left
                    this.navigate(-1);
                    this.controllerInputCooldown = Date.now() + 200;
                } else if (buttons[15] && buttons[15].pressed) { // D-pad right
                    this.navigate(1);
                    this.controllerInputCooldown = Date.now() + 200;
                }

                if (buttons[0] && buttons[0].pressed) { // A button
                    this.launchApp(this.selectedIndex);
                    this.controllerInputCooldown = Date.now() + 500;
                }
            }
        }

        document.addEventListener('DOMContentLoaded', () => {
            new MediaBoxLauncher();
        });

        document.addEventListener('contextmenu', (e) => e.preventDefault());
    </script>
</body>
</html>
EOF

    # Install npm dependencies
    cd "$ACTUAL_INSTALL_DIR"
    npm install
}

# Create apps configuration
create_apps_config() {
    log "Creating apps configuration..."
    
    cat > "$ACTUAL_INSTALL_DIR/config/apps.json" << 'EOF'
[
    {
        "id": "jellyfin",
        "title": "Jellyfin",
        "description": "Media Server & Player",
        "icon": "🎬",
        "command": "flatpak run org.jellyfin.JellyfinTheater",
        "category": "media",
        "enabled": true
    },
    {
        "id": "youtube",
        "title": "YouTube",
        "description": "Watch videos online",
        "icon": "📺",
        "command": "chromium-browser --kiosk --app=https://youtube.com/tv",
        "category": "media",
        "enabled": true
    },
    {
        "id": "netflix",
        "title": "Netflix",
        "description": "Streaming service",
        "icon": "🎭",
        "command": "chromium-browser --kiosk --app=https://netflix.com",
        "category": "media",
        "enabled": true
    },
    {
        "id": "xbox-cloud",
        "title": "Xbox Cloud",
        "description": "Game streaming",
        "icon": "☁️",
        "command": "chromium-browser --kiosk --app=https://xbox.com/play",
        "category": "gaming",
        "enabled": true
    },
    {
        "id": "retroarch",
        "title": "RetroArch",
        "description": "Retro gaming emulator",
        "icon": "🕹️",
        "command": "retroarch",
        "category": "gaming",
        "enabled": true
    },
    {
        "id": "steamlink",
        "title": "Steam Link",
        "description": "PC game streaming",
        "icon": "🚂",
        "command": "steamlink",
        "category": "gaming",
        "enabled": false
    },
    {
        "id": "wifi-config",
        "title": "WiFi Setup",
        "description": "Configure network",
        "icon": "📶",
        "command": "DISPLAY=:0 sudo nmtui",
        "category": "system",
        "enabled": true
    },
    {
        "id": "file-manager",
        "title": "Files",
        "description": "Browse files",
        "icon": "📁",
        "command": "pcmanfm",
        "category": "system",
        "enabled": true
    },
    {
        "id": "shutdown",
        "title": "Power",
        "description": "Shutdown or restart",
        "icon": "⚡",
        "command": "power",
        "category": "system",
        "enabled": true
    }
]
EOF
}

# Create bootstrap script for background app installation
create_bootstrap_script() {
    log "Creating bootstrap script..."
    
    cat > "$ACTUAL_INSTALL_DIR/scripts/bootstrap.sh" << 'EOF'
#!/bin/bash
# Background installation of applications

LOG_FILE="/opt/mediabox/logs/bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "$(date): Starting background app installation..."

# Install RetroArch
echo "Installing RetroArch..."
apt install -y retroarch retroarch-assets

# Install additional gaming packages
echo "Installing gaming packages..."
apt install -y \
    jstest-gtk \
    joystick \
    steamlink

# Install media packages
echo "Installing media packages..."
apt install -y \
    vlc \
    mpv \
    pcmanfm

# Configure controller support
echo "Configuring controller support..."
systemctl enable xboxdrv

# Set permissions
chown -R mediabox:mediabox /opt/mediabox
chmod +x /opt/mediabox/scripts/*.sh

echo "$(date): Background installation completed"
EOF

    chmod +x "$ACTUAL_INSTALL_DIR/scripts/bootstrap.sh"
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=MediaBox Launcher
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
User=$MEDIABOX_USER
Group=$MEDIABOX_USER
Environment=DISPLAY=:0
Environment=HOME=/home/$MEDIABOX_USER
Environment=XDG_RUNTIME_DIR=/run/user/1000
WorkingDirectory=$ACTUAL_INSTALL_DIR
ExecStartPre=/bin/bash -c 'until pgrep -x "Xorg"; do sleep 1; done'
ExecStart=/usr/bin/electron $ACTUAL_INSTALL_DIR
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical-session.target
EOF
}

# Setup auto-login and X11
setup_autologin() {
    log "Setting up auto-login and X11..."
    
    # Configure auto-login
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > "/etc/systemd/system/getty@tty1.service.d/override.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $MEDIABOX_USER --noclear %I \$TERM
EOF

    # Create X11 startup script
    cat > "/home/$MEDIABOX_USER/.xinitrc" << 'EOF'
#!/bin/bash
# Start X11 services
xset s off         # Disable screensaver
xset -dpms         # Disable power management
xset s noblank     # Disable screen blanking
unclutter -idle 3 -root &  # Hide cursor after 3 seconds

# Start window manager
openbox-session &

# Wait for window manager
sleep 2

# Start MediaBox Launcher
cd /opt/mediabox && electron .
EOF

    # Create .bash_profile to start X on login
    cat > "/home/$MEDIABOX_USER/.bash_profile" << 'EOF'
# Auto-start X11 on login to tty1
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF

    # Set ownership
    chown "$MEDIABOX_USER:$MEDIABOX_USER" "/home/$MEDIABOX_USER/.xinitrc"
    chown "$MEDIABOX_USER:$MEDIABOX_USER" "/home/$MEDIABOX_USER/.bash_profile"
    chmod +x "/home/$MEDIABOX_USER/.xinitrc"
}

# Configure SSH and Avahi
setup_services() {
    log "Setting up SSH and Avahi services..."
    
    # Enable SSH
    systemctl enable ssh
    systemctl start ssh
    
    # Configure Avahi for .local hostname
    systemctl enable avahi-daemon
    systemctl start avahi-daemon
    
    # Enable Xbox controller support
    systemctl enable xboxdrv
    
    # Enable MediaBox launcher service
    systemctl enable "$SERVICE_NAME"
    
    log "Services configured successfully"
}

# Configure audio
setup_audio() {
    log "Setting up audio configuration..."
    
    # Add user to audio group
    usermod -aG audio "$MEDIABOX_USER"
    
    # Configure PulseAudio for system mode
    cat > "/etc/pulse/system.pa" << 'EOF'
#!/usr/bin/pulseaudio -nF
# Load audio drivers
load-module module-alsa-sink
load-module module-alsa-source device=hw:1,0
load-module module-native-protocol-unix auth-anonymous=1 socket=/tmp/pulse-socket
EOF

    # Set audio permissions
    echo "$MEDIABOX_USER ALL=(ALL) NOPASSWD: /usr/bin/pulseaudio" >> /etc/sudoers.d/mediabox-audio
}

# Create configuration files
create_configs() {
    log "Creating configuration files..."
    
    # Settings configuration
    cat > "$ACTUAL_INSTALL_DIR/config/settings.json" << 'EOF'
{
    "display": {
        "resolution": "auto",
        "fullscreen": true,
        "autoHideCursor": true,
        "cursorTimeout": 3000
    },
    "controller": {
        "enabled": true,
        "type": "xbox",
        "deadzone": 0.2
    },
    "network": {
        "ssh": true,
        "hostname": "mbox",
        "avahi": true
    },
    "system": {
        "autoStart": true,
        "backgroundInstall": true,
        "updateCheck": false
    },
    "ui": {
        "theme": "dark",
        "gridColumns": 4,
        "showDescriptions": true,
        "animationsEnabled": true
    }
}
EOF

    # Openbox configuration
    mkdir -p "/home/$MEDIABOX_USER/.config/openbox"
    cat > "/home/$MEDIABOX_USER/.config/openbox/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>no</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow">
      <name>sans</name>
      <size>8</size>
      <weight>bold</weight>
      <slant>normal</slant>
    </font>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>MediaBox</name>
    </names>
    <popupTime>875</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popupShow>Nonpixel</popupShow>
    <popupPosition>Center</popupPosition>
    <popupFixedPosition>
      <x>10</x>
      <y>10</y>
    </popupFixedPosition>
  </resize>
  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <dock>
    <position>TopLeft</position>
    <floatingX>0</floatingX>
    <floatingY>0</floatingY>
    <noStrut>no</noStrut>
    <stacking>Above</stacking>
    <direction>Vertical</direction>
    <autoHide>no</autoHide>
    <hideDelay>300</hideDelay>
    <showDelay>300</showDelay>
    <moveButton>Middle</moveButton>
  </dock>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="A-Escape">
      <action name="Lower"/>
      <action name="FocusToBottom"/>
      <action name="Unfocus"/>
    </keybind>
  </keyboard>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
    <screenEdgeWarpMouse>false</screenEdgeWarpMouse>
  </mouse>
  <menu>
    <file>menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <submenuHideDelay>400</submenuHideDelay>
    <applicationIcons>yes</applicationIcons>
    <manageDesktops>yes</manageDesktops>
  </menu>
  <applications>
    <application name="*">
      <decor>no</decor>
      <maximized>true</maximized>
    </application>
  </applications>
</openbox_config>
EOF

    chown -R "$MEDIABOX_USER:$MEDIABOX_USER" "/home/$MEDIABOX_USER/.config"
}

# Create utility scripts
create_utility_scripts() {
    log "Creating utility scripts..."
    
    # Update script
    cat > "$ACTUAL_INSTALL_DIR/scripts/update.sh" << 'EOF'
#!/bin/bash
# MediaBox Update Script

echo "Updating MediaBox system..."

# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Flatpak apps
flatpak update -y

# Update npm packages
cd /opt/mediabox && npm update

# Restart services
sudo systemctl restart mediabox-launcher

echo "Update completed!"
EOF

    # Backup script
    cat > "$ACTUAL_INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
# MediaBox Backup Script

BACKUP_DIR="/home/mediabox/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="mediabox_backup_$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating backup: $BACKUP_FILE"

tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
    /opt/mediabox/config/ \
    /home/mediabox/.config/ \
    /etc/systemd/system/mediabox-launcher.service

echo "Backup created: $BACKUP_DIR/$BACKUP_FILE"
EOF

    # Network info script
    cat > "$ACTUAL_INSTALL_DIR/scripts/network-info.sh" << 'EOF'
#!/bin/bash
# Display network information

echo "=== MediaBox Network Information ==="
echo "Hostname: $(hostname).local"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "SSH Status: $(systemctl is-active ssh)"
echo "Avahi Status: $(systemctl is-active avahi-daemon)"
echo "WiFi Status: $(iwconfig 2>/dev/null | grep -q "ESSID" && echo "Connected" || echo "Not connected")"
echo "=================================="
EOF

    chmod +x "$ACTUAL_INSTALL_DIR/scripts/"*.sh
}

# Set up sudoers for mediabox user
setup_sudoers() {
    log "Setting up sudoers configuration..."
    
    cat > "/etc/sudoers.d/mediabox" << 'EOF'
# MediaBox user permissions
mediabox ALL=(ALL) NOPASSWD: /sbin/shutdown
mediabox ALL=(ALL) NOPASSWD: /sbin/reboot
mediabox ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart mediabox-launcher
mediabox ALL=(ALL) NOPASSWD: /usr/bin/nmtui
mediabox ALL=(ALL) NOPASSWD: /usr/bin/apt update
mediabox ALL=(ALL) NOPASSWD: /usr/bin/apt upgrade
EOF
}

# Final system configuration
final_setup() {
    log "Performing final system setup..."
    
    # Set ownership of all MediaBox files
    chown -R "$MEDIABOX_USER:$MEDIABOX_USER" "$ACTUAL_INSTALL_DIR"
    chown -R "$MEDIABOX_USER:$MEDIABOX_USER" "/home/$MEDIABOX_USER"
    
    # Set execute permissions
    chmod +x "$ACTUAL_INSTALL_DIR/main.js"
    chmod +x "$ACTUAL_INSTALL_DIR/scripts/"*.sh
    
    # Enable boot to console (for auto-login)
    systemctl set-default multi-user.target
    
    # Start background installation
    log "Starting background app installation..."
    nohup "$ACTUAL_INSTALL_DIR/scripts/bootstrap.sh" > "$ACTUAL_INSTALL_DIR/logs/bootstrap.log" 2>&1 &
    
    log "MediaBox installation completed!"
}

# Create uninstall script
create_uninstall_script() {
    log "Creating uninstall script..."
    
    cat > "$ACTUAL_INSTALL_DIR/scripts/uninstall.sh" << 'EOF'
#!/bin/bash
# MediaBox Uninstaller

echo "Uninstalling MediaBox..."

# Stop and disable services
sudo systemctl stop mediabox-launcher
sudo systemctl disable mediabox-launcher
sudo systemctl stop xboxdrv
sudo systemctl disable xboxdrv

# Remove service files
sudo rm -f /etc/systemd/system/mediabox-launcher.service
sudo systemctl daemon-reload

# Remove auto-login
sudo rm -f /etc/systemd/system/getty@tty1.service.d/override.conf

# Remove sudoers file
sudo rm -f /etc/sudoers.d/mediabox

# Remove installation directory
sudo rm -rf /opt/mediabox

# Remove user (optional - commented out for safety)
# sudo userdel -r mediabox

# Reset hostname (optional)
read -p "Reset hostname to 'raspberrypi'? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo hostnamectl set-hostname raspberrypi
    sudo sed -i '/mbox/d' /etc/hosts
fi

echo "MediaBox uninstalled. Reboot recommended."
EOF

    chmod +x "$ACTUAL_INSTALL_DIR/scripts/uninstall.sh"
}

# Print installation summary
print_summary() {
    log "
╔════════════════════════════════════════════════════════════════╗
║                    MEDIABOX INSTALLATION COMPLETE             ║
╠════════════════════════════════════════════════════════════════╣
║  Installation Directory: $ACTUAL_INSTALL_DIR
║  User: $MEDIABOX_USER (Password: $MEDIABOX_PASS)
║  Hostname: $HOSTNAME.local
║  
║  Services Enabled:
║  ├─ SSH (port 22)
║  ├─ Avahi (.local hostname resolution)
║  ├─ Xbox controller support
║  └─ MediaBox Launcher (auto-start)
║  
║  Next Steps:
║  1. Reboot the system: sudo reboot
║  2. The system will auto-login and start MediaBox
║  3. Access via SSH: ssh $MEDIABOX_USER@$HOSTNAME.local
║  4. Configure WiFi using the WiFi Setup tile
║  
║  Utility Scripts:
║  ├─ Update: $ACTUAL_INSTALL_DIR/scripts/update.sh
║  ├─ Backup: $ACTUAL_INSTALL_DIR/scripts/backup.sh
║  ├─ Network Info: $ACTUAL_INSTALL_DIR/scripts/network-info.sh
║  └─ Uninstall: $ACTUAL_INSTALL_DIR/scripts/uninstall.sh
║  
║  Logs: $ACTUAL_INSTALL_DIR/logs/
╚════════════════════════════════════════════════════════════════╝
"
}

# Main installation flow
main() {
    log "Starting MediaBox Pi5 Installation..."
    
    check_root
    setup_directories
    create_user
    set_hostname
    install_dependencies
    setup_flatpak
    create_electron_app
    create_apps_config
    create_bootstrap_script
    create_systemd_service
    setup_autologin
    setup_services
    setup_audio
    create_configs
    create_utility_scripts
    setup_sudoers
    create_uninstall_script
    final_setup
    print_summary
    
    log "Installation complete! Reboot to start MediaBox."
    
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting..."
        reboot
    fi
}

# Run main installation
main "$@"