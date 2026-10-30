s() { echo test | sudo -S "$@" 2>/dev/null; }
ok()  { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; }
chk() { local what=$1; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }

echo "## system"
echo "  kernel $(uname -r), $(rpm -qa | wc -l) packages, target $(systemctl get-default)"
chk "disk is LUKS-encrypted"            sh -c 'lsblk -o FSTYPE | grep -q crypto_LUKS'
chk "root is btrfs"                     sh -c 'findmnt -no FSTYPE / | grep -qx btrfs'
chk "no failed services"                sh -c '[ -z "$(systemctl --failed --no-legend)" ]'
pend=$(s dnf -q check-upgrade | grep -cE '\.(x86_64|noarch)')
chk "fully updated ($pend pending)"     test "$pend" -eq 0
echo "  sway $(rpm -q --qf '%{VERSION}' sway), kernels: $(rpm -q kernel | tr '\n' ' ')"
echo "  NVIDIA modules for: $(rpm -qa 'kmod-nvidia-*' --qf '%{NAME}\n' | sed 's/kmod-nvidia-//; s/-615.*//' | tr '\n' ' ')"
systemctl --failed --no-legend | sed 's/^/        /'

echo "## desktop"
chk "login screen (greetd) running"     systemctl is-active greetd
chk "quickshell is 0.3+ (DMS build)"    sh -c 'rpm -q quickshell | grep -q "^quickshell-0\.[3-9]"'
chk "sway is 1.12"                     sh -c 'sway --version | grep -q 1.12'
chk "Fedora copies of DMS deps hidden"  test -f /etc/dnf/repos.override.d/50-dms-copr.repo
for p in quickshell danksearch dgop matugen dms dms-greeter sway sway-config-fedora; do printf '        %s\n' "$(rpm -q $p)"; done

echo "## apps"
for p in claude-desktop brave-origin chromium microsoft-edge-stable toolbox nautilus sushi ptyxis papers loupe showtime snapshot cups system-config-printer nvidia-kmod-control; do
    chk "$p" rpm -q "$p"
done
chk "claude-desktop files verified"     claude-desktop-verify

echo "## repos + signatures"
ls /etc/yum.repos.d/ | sed 's/^/        /'
chk "dnf sees all repos (refresh)"      s dnf -q makecache
echo "  packages with no signature: $(s cat /root/unsigned-packages.txt | wc -l)"
s cat /root/unsigned-packages.txt | sed 's/^/        /'

echo "## kickstart %post"
s tail -4 /root/ks-post.log | sed 's/^/        /'
s cat /root/ks-done | sed 's/^/        /'
