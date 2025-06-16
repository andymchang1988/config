#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Please run this script with sudo: sudo ./setup.sh"
  exit 1
fi


echo "🚀 Resetting Vim and Vi configurations..."

# Backup and remove old configs
echo "📦 Backing up old Vim configs..."
for file in ~/.vimrc /etc/vimrc /etc/vim/vimrc /usr/share/vim/vim*/defaults.vim; do
    if [ -f "$file" ]; then
        echo "🔹 Backing up $file -> $file.bak"
        sudo mv "$file" "$file.bak"
    fi
done

# Create a fresh vimrc
echo "📝 Creating a clean ~/.vimrc with proper insert mode settings..."
echo "set nocompatible" > ~/.vimrc

# Ensure the system-wide vimrc exists
if [ -d /etc/vim ]; then
    echo "set nocompatible" | sudo tee /etc/vim/vimrc > /dev/null
else
    echo "set nocompatible" | sudo tee /etc/vimrc > /dev/null
fi

# Fix vi symlink if needed
echo "🔍 Checking 'vi' symlink..."
vi_path=$(which vi 2>/dev/null)
if [ -n "$vi_path" ]; then
    target=$(readlink -f "$vi_path")
    if [[ "$target" != "/usr/bin/vim" ]]; then
        echo "❌ 'vi' is not linked to Vim! Fixing..."
        sudo ln -sf /usr/bin/vim /usr/bin/vi
    else
        echo "✅ 'vi' is correctly linked to Vim."
    fi
else
    echo "❌ 'vi' not found! Installing Vim..."
    sudo pacman -S vim --noconfirm
fi

# Ensure full Vim is installed (not vim-tiny)
if vim --version | grep -q "+tiny"; then
    echo "❌ Detected minimal Vim version! Installing full Vim..."
    sudo pacman -S vim --noconfirm
else
    echo "✅ Full Vim installation detected."
fi

USER_HOME=$(eval echo "~$SUDO_USER")
YAY_DIR="/opt/yay"
MSF_DB_USER="nope-mfs"
MSF_DB_PASS="mfcons2025!1"
MSF_DB_NAME="msf_database"
LIMINE_CFG="/boot/limine.cfg"
KERNEL_PARAM="i915.enable_dpcd_backlight=3"

echo "[*] Installing base-devel and git..."
pacman -Sy --noconfirm base-devel git

echo "[*] Cleaning and preparing yay directory..."
rm -rf "$YAY_DIR"
mkdir -p "$YAY_DIR"
chown -R "$SUDO_USER:$SUDO_USER" "$YAY_DIR"

echo "[*] Installing yay as $SUDO_USER..."
sudo -u "$SUDO_USER" bash <<EOF
cd "$YAY_DIR"
git clone https://aur.archlinux.org/yay.git .
makepkg -si --noconfirm
EOF

echo "[*] Installing packages via yay as $SUDO_USER..."
sudo -u "$SUDO_USER" yay -Sy --noconfirm \
  mesa mesa-utils vulkan-intel libva-intel-driver intel-media-driver xf86-video-intel \
  sof-firmware alsa-utils pipewire pipewire-pulse wireplumber \
  steam minecraft-launcher teams vscodium github-desktop-bin opera audacity mixxx filezilla \
  metasploit postgresql

echo "[*] Initializing PostgreSQL cluster if not already initialized..."
PGDATA="/var/lib/postgres/data"
if [ ! -f "$PGDATA/PG_VERSION" ]; then
  sudo -u postgres initdb --locale=C.UTF-8 --encoding=UTF8 -D "$PGDATA"
  echo "[+] PostgreSQL initialized."
else
  echo "[=] PostgreSQL already initialized at $PGDATA."
fi

echo "[*] Enabling and starting PostgreSQL..."
systemctl enable --now postgresql

echo "[*] Creating PostgreSQL user and Metasploit database..."
sudo -u postgres psql <<EOF
DO
\$do\$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_user WHERE usename = '$MSF_DB_USER') THEN
      CREATE USER "$MSF_DB_USER" WITH PASSWORD '$MSF_DB_PASS';
   END IF;
END
\$do\$;

CREATE DATABASE $MSF_DB_NAME OWNER "$MSF_DB_USER";
EOF

echo "[*] Writing Metasploit database config for $SUDO_USER..."
MSF_CFG_DIR="$USER_HOME/.msf4"
mkdir -p "$MSF_CFG_DIR"
cat > "$MSF_CFG_DIR/database.yml" <<EOF
production:
  adapter: postgresql
  database: $MSF_DB_NAME
  username: $MSF_DB_USER
  password: $MSF_DB_PASS
  host: 127.0.0.1
  port: 5432
  pool: 75
  timeout: 5
EOF
chown -R "$SUDO_USER:$SUDO_USER" "$MSF_CFG_DIR"

echo "[*] Creating SSH key for $SUDO_USER if not already present..."
SSH_KEY="$USER_HOME/.ssh/id_rsa"
if [ ! -f "$SSH_KEY" ]; then
  sudo -u "$SUDO_USER" ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N ""
fi

echo "[*] Adding SSH alias to .bashrc..."
BASHRC="$USER_HOME/.bashrc"
ALIAS_STRING="alias dfe='ssh dfe-admin@192.168.86.69 -i ~/.ssh/id_rsa'"
if ! grep -q "$ALIAS_STRING" "$BASHRC"; then
  echo "$ALIAS_STRING" >> "$BASHRC"
  chown "$SUDO_USER:$SUDO_USER" "$BASHRC"
fi

echo "[*] Setting Limine kernel parameter for Intel backlight fix..."
if [ -f "$LIMINE_CFG" ]; then
  if ! grep -q "$KERNEL_PARAM" "$LIMINE_CFG"; then
    sed -i "/^    KERNEL_OPTIONS=/ s/\"$/ $KERNEL_PARAM\"/" "$LIMINE_CFG"
    echo "[+] Kernel parameter set in Limine."
  else
    echo "[=] Kernel parameter already present."
  fi
else
  echo "[!] Limine config not found at $LIMINE_CFG"
fi

echo "[✓] Setup complete. You can now run Metasploit with 'msfconsole'. Reboot recommended."
