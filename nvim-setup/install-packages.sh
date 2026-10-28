#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y \
  neovim git ripgrep fd-find fzf gcc gcc-c++ make cmake unzip curl wget tar gzip \
  nodejs npm python3 python3-pip luarocks tree-sitter-cli \
  golang rust cargo rustfmt rust-analyzer clippy \
  wl-clipboard xclip

ver=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/lazygit.tgz" "https://github.com/jesseduffield/lazygit/releases/download/v${ver}/lazygit_${ver}_Linux_x86_64.tar.gz"
tar -xzf "$tmp/lazygit.tgz" -C "$tmp" lazygit
install -m 755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"
rm -rf "$tmp"

echo
echo "=== DONE: packages installed ==="
nvim --version | head -1; git --version; node --version; lazygit --version | head -1
