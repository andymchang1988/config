#!/bin/bash
echo "Vim Vi fix. This links `vi` to use `vim` in cases like `vi test.txt`"
sudo pacman -S vim vim-runtime --noconfirm

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

echo "✅ Fixes applied! Restart your terminal and test 'vi test.txt'"

