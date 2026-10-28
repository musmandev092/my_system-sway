#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/VMs/fedora-iso"
SRC="$DIR/Fedora-Everything-netinst-x86_64-44-1.7.iso"
KS="$HERE/ks.cfg"
KS_DUAL="$HERE/ks-dualboot.cfg"

[ -f "$SRC" ] || { echo "missing $SRC (download and verify it first)" >&2; exit 1; }
command -v mkksiso >/dev/null || { echo "mkksiso not found: sudo dnf install lorax" >&2; exit 1; }
command -v ksvalidator >/dev/null && {
    printf 'network --hostname=test\ntimezone UTC --utc\nignoredisk --only-use=vda\nautopart\nuser --name=test\nreboot\n' > /tmp/ks-machine.cfg
    ksvalidator -v F44 "$KS"
    ksvalidator -v F44 "$KS_DUAL"
}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
rsync -a --exclude='target/' --exclude='.git/' --exclude='__pycache__/' --exclude='*.log' \
      --exclude='*.bak' --exclude='*.bak.*' "$HERE/../" "$STAGE/my_system/"

rm -f "$DIR/my_system-fedora44.iso" "$DIR/my_system-fedora44-dualboot.iso" "$DIR/my_system-fedora44-vm.iso"
mkksiso --skip-mkefiboot --ks "$KS" -a "$STAGE/my_system" -c "fbcon=font:TER16x32" "$SRC" "$DIR/my_system-fedora44.iso"
mkksiso --skip-mkefiboot --ks "$KS_DUAL" -a "$STAGE/my_system" -c "fbcon=font:TER16x32" "$SRC" "$DIR/my_system-fedora44-dualboot.iso"
mkksiso --skip-mkefiboot --ks "$KS" -a "$STAGE/my_system" -c "fbcon=font:TER16x32 console=tty0 console=ttyS0,115200" \
        "$SRC" "$DIR/my_system-fedora44-vm.iso"
ls -lh "$DIR"/my_system-fedora44*.iso
