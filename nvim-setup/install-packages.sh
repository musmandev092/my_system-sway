#!/usr/bin/env bash
set -euo pipefail

sudo dnf install -y \
  neovim git ripgrep fd-find fzf gcc gcc-c++ make cmake unzip curl wget tar gzip \
  nodejs npm python3 python3-pip luarocks tree-sitter-cli \
  golang rust cargo rustfmt rust-analyzer clippy \
  wl-clipboard xclip

gh_release_asset() {
    local repo=$1 pat=$2 out=$3 rel name url sum
    rel=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest") || return 1
    read -r name url sum < <(python3 -I -c '
import json, re, sys
d = json.load(sys.stdin); pat = re.compile(sys.argv[1], re.I)
for a in d["assets"]:
    if pat.fullmatch(a["name"]) and (a.get("digest") or "").startswith("sha256:"):
        print(a["name"], a["browser_download_url"], a["digest"][7:]); break' "$pat" <<<"$rel") || return 1
    [ -n "${name:-}" ] || return 1
    curl -fsSL -o "$out" "$url" || return 1
    echo "$sum  $out" | sha256sum -c --status
}

tmp=$(mktemp -d)
if gh_release_asset jesseduffield/lazygit 'lazygit_[0-9.]+_linux_x86_64\.tar\.gz' "$tmp/lazygit.tgz"; then
  tar -xzf "$tmp/lazygit.tgz" -C "$tmp" lazygit
  install -m 755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"
else
  echo "lazygit: download or SHA-256 check failed, not installed" >&2
fi
rm -rf "$tmp"

echo
echo "=== DONE: packages installed ==="
nvim --version | head -1; git --version; node --version; lazygit --version | head -1
