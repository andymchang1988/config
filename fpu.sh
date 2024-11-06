#!/bin/bash

# Set up log files
LOG_FILE="./install_log.txt"
ERROR_LOG_FILE="./error_log.txt"
touch $LOG_FILE $ERROR_LOG_FILE

# Function to log messages
log() {
    echo "$(date): $1" | tee -a $LOG_FILE
}

# Function to log errors
log_error() {
    echo "$(date): ERROR - $1" | tee -a $ERROR_LOG_FILE
}

log "Starting the first-boot setup script."

# Step 1: Check the OS and distribution
OS=$(grep -E '^ID=' /etc/os-release | awk -F= '{print $2}' | tr -d '"')
VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | awk -F= '{print $2}' | tr -d '"')
log "Detected OS: $OS, Version: $VERSION"

# Step 2: Install updates, upgrades, and system packages
log "Updating the package list and upgrading the system."
if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ] || [ "$OS" == "pop" ]; then
    sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y || log_error "Failed to update and upgrade packages on $OS."
    sudo apt install -y neofetch || log_error "Failed to install neofetch."
    sudo apt install -y flatpak || log_error "Failed to install flatpak."

    if [ "$OS" == "pop" ]; then
        sudo apt install -y pop-desktop || log_error "Failed to ensure Pop!_OS desktop environment packages."
    fi

    sudo apt install -y ubuntu-restricted-extras || log_error "Failed to install third-party media drivers."
elif [ "$OS" == "fedora" ]; then
    sudo dnf upgrade -y || log_error "Failed to upgrade packages on $OS."
    sudo dnf install -y neofetch flatpak || log_error "Failed to install neofetch or flatpak."
    sudo dnf groupinstall -y "Multimedia" --exclude=PackageKit-gstreamer-plugin || log_error "Failed to install third-party media drivers."
elif [ "$OS" == "arch" ] || [ "$OS" == "manjaro" ]; then
    sudo pacman -Syu --noconfirm || log_error "Failed to update and upgrade packages on $OS."
    sudo pacman -S --noconfirm neofetch flatpak || log_error "Failed to install neofetch or flatpak."
    sudo pacman -S --noconfirm gstreamer gst-plugins-base gst-plugins-good gst-plugins-ugly gst-libav || log_error "Failed to install third-party media drivers."
else
    log_error "Unsupported OS: $OS. Exiting script."
    exit 1
fi

log "System updated and necessary packages installed."

# Step 3: Enable and add Flathub repository if not already added
log "Setting up Flathub repository for Flatpak."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || log_error "Failed to add Flathub repository."

# Step 4: Verify if required applications are available on Flathub and install them
declare -a flatpak_apps=("org.chromium.Chromium" "com.visualstudio.code" "com.slack.Slack" "com.github.IsmaelMartinez.teams_for_linux" "io.github.pwr_solaar.solaar" "com.github.iwalton3.jellyfin-media-player" "com.spotify.Client" "io.github.shiftey.Desktop")

log "Checking for required Flatpak applications on Flathub."
for app in "${flatpak_apps[@]}"; do
    if flatpak search $app | grep -q $app; then
        log "$app is available on Flathub. Proceeding with installation."
        sudo flatpak install -y flathub $app || log_error "Failed to install $app."
    else
        log_error "$app not found on Flathub."
    fi
done

log "Flatpak applications installed successfully."

log "First-boot setup completed successfully."

exit 0
