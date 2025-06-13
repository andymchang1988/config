#!/bin/bash

# Update system
echo "🔄 Updating system..."
sudo pacman -Syu --noconfirm

# Core packages (official repos)
echo "📦 Installing core packages via pacman..."
sudo pacman -S --noconfirm intel-linux-graphics-installer vim yay mesa intel-ucode linux-firmware mixxx xf86-video-intel linux-headers vulkan-intel intel-media-driver libva-intel-driver libva-utils

# AUR packages from apps list file
AUR_APPS_FILE="apps.txt"

if [[ -f "$AUR_APPS_FILE" ]]; then
    echo "📄 Installing AUR packages from $AUR_APPS_FILE..."
    while IFS= read -r app || [[ -n "$app" ]]; do
        [[ -z "$app" || "$app" == \#* ]] && continue  # Skip empty lines or comments
        echo "➡️  Installing $app..."
        yay -S --noconfirm "$app"
    done < "$AUR_APPS_FILE"
else
    echo "❌ Error: $AUR_APPS_FILE not found."
    exit 1
fi

# Modify GRUB configuration
GRUB_FILE="/etc/default/grub"
CMDLINE="i915.enable_dcpd_backlight=3 i915.enable_dp_mst=0 i915.enable_psr2_sel_fetch=1"

if [ -f "$GRUB_FILE" ]; then
    echo "⚙️ Updating GRUB configuration..."
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${CMDLINE}\"|" "$GRUB_FILE"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    echo "✅ GRUB updated."
else
    echo "❌ Error: $GRUB_FILE not found."
    exit 1
fi

echo "🎉 Setup complete. Please reboot to apply changes."
