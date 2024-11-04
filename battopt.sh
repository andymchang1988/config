#!/bin/bash
set -e

# Detect OS and version
OS_NAME=$(lsb_release -is)
OS_VERSION=$(lsb_release -rs)

if [[ "$OS_NAME" != "Ubuntu" || "$OS_VERSION" != "24.04" ]]; then
  echo "This script is intended for Ubuntu 24.04. Your system is running $OS_NAME $OS_VERSION. Exiting."
  exit 1
fi

# Update package list
echo "Updating package list..."
sudo apt update && sudo apt upgrade -y

# Install necessary packages for battery optimization
echo "Installing necessary packages..."
sudo apt install -y tlp tlp-rdw powertop acpi

# Enable TLP for power optimization
echo "Enabling TLP..."
sudo systemctl enable tlp
sudo systemctl start tlp

# Optimize power settings using Powertop
echo "Running Powertop to auto-tune power settings..."
sudo powertop --auto-tune || echo "Powertop auto-tune encountered an issue but continuing..."

# Set CPU governor to power save for better battery life
echo "Setting CPU governor to 'powersave'..."
for CPU in /sys/devices/system/cpu/cpu[0-9]*; do
  GOVERNOR_PATH="$CPU/cpufreq/scaling_governor"
  if [ -f "$GOVERNOR_PATH" ]; then
    echo "powersave" | sudo tee "$GOVERNOR_PATH"
  fi
done

# Disable Turbo Boost for battery optimization
echo "Disabling Intel Turbo Boost..."
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
  echo "1" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo
else
  echo "Turbo Boost control not available. Skipping..."
fi

# Reduce screen brightness to save battery
echo "Reducing screen brightness..."
if command -v brightnessctl >/dev/null 2>&1; then
  echo "Reducing screen brightness using brightnessctl..."
  sudo brightnessctl set 50%
else
  echo "brightnessctl not found. Skipping screen brightness adjustment."
fi

# Disable Bluetooth if not needed
echo "Disabling Bluetooth for battery optimization..."
BLUETOOTH_STATUS=$(rfkill list bluetooth | grep -i "bluetooth" | grep -i "Soft blocked: no" || true)
if [ -n "$BLUETOOTH_STATUS" ]; then
  sudo rfkill block bluetooth
fi


# Final message
echo "Battery optimization complete. The system has been configured for improved battery life."

