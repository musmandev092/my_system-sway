set -u
s() { echo test | sudo -S "$@" 2>/dev/null; }
s sh -c 'echo "test ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vmtest'

rpm -q tar rsync git-core >/dev/null 2>&1 || sudo dnf -y -q install tar rsync git-core

sudo mkdir -p /mnt/share && { mountpoint -q /mnt/share || sudo mount -o ro /dev/sr0 /mnt/share; }
mkdir -p ~/Projects && rm -rf ~/Projects/my_system && cp -r /mnt/share ~/Projects/my_system
chmod -R u+w ~/Projects/my_system
cd ~/Projects/my_system

echo test | sudo -S -v 2>/dev/null
( while sleep 60; do echo test | sudo -S -v 2>/dev/null; done ) &
KEEPALIVE=$!
trap 'kill $KEEPALIVE 2>/dev/null' EXIT

echo "##### apply.sh"
time ./apply.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
echo "##### apply.sh again (should change nothing)"
./apply.sh system home 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'updated|installed|copied|linked|!!' || echo "  nothing changed"

echo "##### checks"
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
chk() { local w=$1; shift; if "$@" >/dev/null 2>&1; then ok "$w"; else bad "$w"; fi; }
chk "cursor installed"                rpm -q cursor
chk "i2c udev rule"                   test -f /etc/udev/rules.d/60-i2c-display.rules
chk "dnf keeps 3 kernels"             grep -q '^installonly_limit=3$' /etc/dnf/dnf.conf
chk "GRUB font set"                   grep -q '^GRUB_FONT=/boot/grub2/fonts/adwaita-mono-48.pf2$' /etc/default/grub
chk "Chromium key hook"               grep -q 'my_system: Google sign-in keys' /etc/chromium/chromium.conf
chk "Chromium Intel decode"           grep -q '^GRAPHIC_DRIVER=intel$' /etc/chromium/chromium.conf
chk "custom.sh linked"                test -L ~/.bashrc.d/custom.sh
chk "nvim config linked"              test -L ~/.config/nvim
chk "fonts installed"                 sh -c 'fc-list | grep -qi "JetBrainsMono Nerd"'
chk "Urdu font installed"             sh -c 'fc-list | grep -qi "Jameel"'
chk "niri config loads DMS"           grep -q 'dms/' ~/.config/niri/config.kdl
chk "niri config valid"               niri validate -c ~/.config/niri/config.kdl
chk "DMS settings"                    test -f ~/.config/dms/settings.json
chk "starship"                        ~/.local/bin/starship --version
chk "lazygit"                         ~/.local/bin/lazygit --version
chk "dev toolbox exists"              podman container exists dev
chk "nvim inside dev"                 toolbox run -c dev nvim --version
chk "rust inside dev"                 toolbox run -c dev cargo --version
chk "go inside dev"                   toolbox run -c dev go version
chk "node inside dev"                 toolbox run -c dev node --version
chk "gh inside dev"                   toolbox run -c dev gh --version
chk "Chromium flags file has OAuth"   grep -q -- '--oauth2-client-id=77185425430' ~/.config/chromium-flags.conf
chromium-browser --headless=new --no-first-run --user-data-dir=/tmp/chr-test about:blank >/dev/null 2>&1 &
sleep 6
chk "running Chromium has the OAuth flags" sh -c 'pgrep -af chromium | grep -q -- "--oauth2-client-id=77185425430"'
pkill -f chr-test 2>/dev/null
echo "## a new login shell (custom.sh + starship):"
bash -lic 'type nvim | head -1; type fp | head -1; echo "starship hook: $(declare -F starship_precmd >/dev/null && echo yes || echo no)"' 2>/dev/null </dev/null | sed "s/^/  /"
echo "## LSP check (Rust file, inside dev):"
cd ~/Projects/my_system/nvim-setup/test 2>/dev/null && toolbox run -c dev nvim --headless rs/src/main.rs -c 'luafile ../check-file.lua' 2>/dev/null | head -1 | sed 's/^/  /'
