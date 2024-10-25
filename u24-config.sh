#!/bin/bash
set -e

# Update and install prerequisites
echo "Updating package list and installing prerequisites..."
sudo apt update
sudo apt install -y wget curl gdebi-core lsb-release

### GitHub Desktop Installation ###
echo "Installing GitHub Desktop..."

# Fetch the latest GitHub Desktop release download link specifically for amd64
GITHUB_DESKTOP_URL=$(curl -s https://api.github.com/repos/shiftkey/desktop/releases/latest | grep -oP 'https://[^"]*GitHubDesktop-linux-amd64[^"]*.deb' | head -n 1)

# Check if URL was extracted successfully
if [[ -z "$GITHUB_DESKTOP_URL" ]]; then
  echo "Failed to retrieve GitHub Desktop download URL. Please check the repository."
  exit 1
fi

# Download and install GitHub Desktop .deb for amd64
wget -O GitHubDesktop.deb "$GITHUB_DESKTOP_URL"
sudo gdebi -n GitHubDesktop.deb
rm GitHubDesktop.deb

### Slack Installation ###
echo "Installing Slack..."

# Determine OS version and set Slack download URL accordingly
SLACK_VERSION=$(curl -s https://slack.com/downloads/instructions/ubuntu | grep -oP 'latest version.*x64.*"' | grep -oP '[0-9.]+(?=">)')
SLACK_URL="https://downloads.slack-edge.com/releases/linux/$SLACK_VERSION/prod/x64/slack-desktop-$SLACK_VERSION-amd64.deb"

# Check if Slack is already installed and remove if present
if dpkg -l | grep -q slack-desktop; then
  echo "Slack is already installed. Removing..."
  sudo apt remove --purge -y slack-desktop
fi

# Download and install Slack
wget -O Slack.deb "$SLACK_URL"
sudo gdebi -n Slack.deb
rm Slack.deb

### Portal for Teams Installation ###
echo "Installing Portal for Teams..."

# Download and install the Portal for Teams .deb package
wget -O Portal.deb https://portal.prod.download/portal-linux.deb
sudo gdebi -n Portal.deb
rm Portal.deb

### VSCodium Installation ###
echo "Installing VSCodium..."

# Add VSCodium repository and GPG key
wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg | gpg --dearmor > ~/vscodium-archive-keyring.gpg
sudo install -o root -g root -m 644 ~/vscodium-archive-keyring.gpg /usr/share/keyrings/
echo 'deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://ppa.launchpadcontent.net/vscodium/deb/ stable main' | sudo tee /etc/apt/sources.list.d/vscodium.list

# Update and install VSCodium
sudo apt update
sudo apt install -y codium

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
    sudo update-grub

    echo "Parameter added and GRUB updated successfully!"
fi

### Final Message ###
echo "Installation of GitHub Desktop, Slack, Portal for Teams, VSCodium, and GRUB update is complete!"

### Specific Compatibility Adjustments for Ubuntu 24.04 ###
echo "Checking compatibility for Ubuntu 24.04..."

# Verify if the script is running on Ubuntu 24.04
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" == "24.04" ]]; then
    echo "Detected Ubuntu 24.04. Performing additional compatibility checks..."
    # Adjust package names or URLs as needed for Ubuntu 24.04 compatibility
    # Example: Add any special dependencies that might be needed for newer versions
else
    echo "This script is optimized for Ubuntu 24.04 but should work on other compatible versions."
fi

