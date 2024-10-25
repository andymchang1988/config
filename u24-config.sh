#!/bin/bash
set -e

# Update and install prerequisites
echo "Updating package list and installing prerequisites..."
sudo apt update && sudo apt dist-upgrade -y
if snap list | grep -q codium; then
    echo "VSCodium is already installed via snap. Skipping installation."
elif snap find codium &>/dev/null; then
    echo "Installing VSCodium via snap..."
    sudo snap install codium || { echo "Failed to install VSCodium via snap. Please check for potential dependency issues."; exit 1; }
else
    echo "Attempting to install VSCodium via apt..."
    sudo apt install -y codium || { echo "Failed to install VSCodium via apt. Please check for potential dependency issues."; exit 1; }
fi

### GRUB Parameter Update ###
echo "Adding 'i915.enable_dpcd_backlight=3' to GRUB_CMDLINE_LINUX_DEFAULT..."

# Define the parameter to add
PARAMETER="i915.enable_dpcd_backlight=3"

# Backup the original GRUB config file
sudo cp /etc/default/grub /etc/default/grub.bak

# Check if the parameter is already present in the GRUB_CMDLINE_LINUX_DEFAULT
if grep -q "$PARAMETER" /etc/default/grub; then
    echo "Parameter already present in GRUB_CMDLINE_LINUX_DEFAULT."
else
    echo "Adding parameter to GRUB_CMDLINE_LINUX_DEFAULT..."
    
    # Use sed to append the parameter to the GRUB_CMDLINE_LINUX_DEFAULT line
    sudo sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"\(.*\)\"/\"\1 $PARAMETER\"/" /etc/default/grub

    # Update GRUB configuration
    echo "Updating GRUB..."
sudo update-grub || { echo "Failed to update GRUB. Please check for potential issues with the configuration."; exit 1; }

    echo "Parameter added and GRUB updated successfully!"
fi

### Portal for Teams Installation ###

# Install Portal for Teams via Snap
echo "Installing Teams for Linux via Snap..."
if snap list | grep -q teams-for-linux; then
    echo "Teams for Linux is already installed via Snap. Skipping installation."
else
    echo "Installing Teams for Linux via Snap..."
    sudo snap install teams-for-linux || { echo "Failed to install Teams for Linux via Snap. Please check for potential issues."; exit 1; }
fi

### Cinnamon Desktop Installation ###

# Install Cinnamon Desktop
if dpkg -l | grep -q cinnamon-desktop-environment; then
    echo "Cinnamon Desktop is already installed. Skipping installation."
else
    echo "Installing Cinnamon Desktop..."
    sudo apt install -y cinnamon-desktop-environment || { echo "Failed to install Cinnamon Desktop. Please check for potential dependency issues."; exit 1; }
fi

# Set Cinnamon as the default desktop environment
if [ -f /usr/share/xsessions/cinnamon.desktop ]; then
    echo "Setting Cinnamon as the default desktop environment..."
    if [ -d /etc/lightdm ]; then
    sudo bash -c 'echo "[Seat:*]" > /etc/lightdm/lightdm.conf'
    sudo bash -c 'echo "user-session=cinnamon" >> /etc/lightdm/lightdm.conf'
    echo "Cinnamon has been set as the default desktop environment."
elif [ -d /etc/gdm3 ]; then
    echo "Setting Cinnamon as the default desktop environment for GDM..."
    sudo bash -c 'echo "[daemon]" > /etc/gdm3/custom.conf'
    sudo bash -c 'echo "DefaultSession=cinnamon" >> /etc/gdm3/custom.conf'
    echo "Cinnamon has been set as the default desktop environment for GDM."
else
    echo "No suitable display manager configuration found. Please verify the display manager."
    exit 1
fi
    echo "Cinnamon has been set as the default desktop environment."
else
    echo "Cinnamon desktop session file not found. Please verify the installation."
    exit 1
fi

### Set System to Dark Mode ###

# Set GNOME or Cinnamon to dark mode if available
if [ "$(gsettings get org.gnome.desktop.interface gtk-theme)" != "Adwaita-dark" ]; then
    echo "Setting system to dark mode..."
    sudo -u $SUDO_USER gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark" || { echo "Failed to set dark mode. Please check the settings availability."; }
else
    echo "System is already in dark mode."
fi

### Import Bookmarks into Firefox ###

# Import bookmarks from GitHub repository into Firefox
BOOKMARK_URL="https://raw.githubusercontent.com/andymchang1988/config/main/bm.html"
BOOKMARK_FILE="/tmp/bm.html"

wget -O "$BOOKMARK_FILE" "$BOOKMARK_URL" || { echo "Failed to download bookmarks from $BOOKMARK_URL."; exit 1; }

if [ -f "$BOOKMARK_FILE" ]; then
    echo "Importing bookmarks into Firefox..."
    sudo -u $SUDO_USER sudo -u $SUDO_USER firefox --no-remote --new-instance --import-bookmarks "$BOOKMARK_FILE" || { echo "Failed to import bookmarks into Firefox. Please check for issues."; exit 1; }
    rm "$BOOKMARK_FILE"
else
    echo "Bookmark file not found. Please check the download."
    exit 1
fi

### Final Message ###
echo "Installation of GitHub Desktop, Slack, Teams for Linux, VSCodium, and GRUB update is complete!"
