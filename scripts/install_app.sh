sudo pacman -Syyu
sudo pacman -S git base-devel --needed

git clone https://aur.archlinux.org/yay.git ~/
cd ~/yay
makepkg -si
cd ~
sudo yay -Syyu

# Install apps
echo "📦 Installing applications..."

yay -S --noconfirm \
    google-chrome \
    antigravity-bin \
    postman-bin \
    dbeaver \
    obsidian \
    obs-studio \
    visual-studio-code-bin \
    slack-desktop \
    fcitx5 fcitx5-configtool fcitx5-unikey fcitx5-gtk fcitx5-qt \
    mongodb-compass \
    docker-desktop

echo "✅ All apps installed!"
