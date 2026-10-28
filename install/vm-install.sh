#!/bin/bash
set -euo pipefail

ISO="$HOME/VMs/fedora-iso/my_system-fedora44-vm.iso"
VM="$HOME/VMs/test"
OVMF=/usr/share/edk2/ovmf

[ -f "$ISO" ] || { echo "missing $ISO (run build-iso.sh)" >&2; exit 1; }
[ -r /dev/kvm ] || { echo "no /dev/kvm" >&2; exit 1; }

rm -rf "$VM"
mkdir -p "$VM"
qemu-img create -q -f qcow2 "$VM/disk.qcow2" 60G
cp "$OVMF/OVMF_VARS.fd" "$VM/vars.fd"

exec qemu-system-x86_64 \
    -name my_system-test -enable-kvm -machine q35 -cpu host -smp 4 -m 8192 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.fd" \
    -drive if=pflash,format=raw,file="$VM/vars.fd" \
    -drive file="$VM/disk.qcow2",if=virtio,format=qcow2 \
    -cdrom "$ISO" -boot once=d \
    -nic user,model=virtio-net-pci \
    -device virtio-vga -display none \
    -serial file:"$VM/install-serial.log" \
    -monitor unix:"$VM/monitor.sock",server,nowait \
    -no-reboot
