s() { echo test | sudo -S "$@" 2>/dev/null; }
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
chk() { local w=$1; shift; if "$@" >/dev/null 2>&1; then ok "$w"; else bad "$w"; fi; }

echo "## answers became the system"
chk "computer name is vmtest"          sh -c '[ "$(hostname)" = vmtest ]'
chk "time zone Asia/Karachi"           sh -c 'timedatectl show -p Timezone --value | grep -qx Asia/Karachi'
chk "user is an administrator (wheel)" sh -c 'id -nG | grep -qw wheel'
chk "full name Test User"              sh -c 'getent passwd test | cut -d: -f5 | grep -q "Test User"'
chk "no passphrase in saved kickstart" sh -c '! echo test | sudo -S grep -q passphrase /root/anaconda-ks.cfg'

echo "## installer did the system part"
chk "my_system copied to ~/Projects"   test -x ~/Projects/my_system/apply.sh
chk "my_system owned by the user"      sh -c '[ "$(stat -c %U ~/Projects/my_system/apply.sh)" = test ]'
chk "cursor installed"                 rpm -q cursor
chk "i2c udev rule"                    test -f /etc/udev/rules.d/60-i2c-display.rules
chk "dnf keeps 3 kernels"              grep -q '^installonly_limit=3$' /etc/dnf/dnf.conf
chk "GRUB font"                        grep -q '^GRUB_FONT=' /etc/default/grub
chk "Chromium flags hook"              grep -q 'my_system: per-user Chromium flags' /etc/chromium/chromium.conf
chk "greetd running"                   systemctl is-active greetd
chk "fully updated"                    sh -c '[ "$(echo test | sudo -S dnf -q check-upgrade 2>/dev/null | grep -cE "\.(x86_64|noarch)")" -eq 0 ]'
s tail -3 /root/ks-post-nochroot.log | sed 's/^/        /'

echo "## first login: personal setup runs by itself"
chk "first-run service enabled"        test -L ~/.config/systemd/user/default.target.wants/my-system-firstrun.service
echo "  waiting for it to finish (up to 25 min) ..."
for _ in $(seq 150); do
    [ -f ~/.local/state/my_system/firstrun.done ] && break
    systemctl --user is-active -q my-system-firstrun.service || { [ -f ~/.local/state/my_system/firstrun.log ] && break; }
    sleep 10
done
chk "first-run finished (done marker)" test -f ~/.local/state/my_system/firstrun.done
grep -E 'ok|!!|mason:|treesitter:' ~/.local/state/my_system/firstrun.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g; s/^/        /' | tail -30
chk "custom.sh linked"                 test -L ~/.bashrc.d/custom.sh
chk "starship"                         ~/.local/bin/starship --version
chk "agy"                              ~/.local/bin/agy --version
chk "sway: DMS binds linked"            test -L ~/.config/sway/config.d/91-dms.conf
chk "Chromium Google sign-in flags"    grep -q oauth2-client-id ~/.config/chromium-flags.conf
chk "dev toolbox: nvim"                toolbox run -c dev nvim --version
chk "dev toolbox: cargo"               toolbox run -c dev cargo --version
