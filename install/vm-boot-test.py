#!/usr/bin/env python3
"""Boot the installed test VM, unlock LUKS, log in on the serial console,
run checks, save a screenshot of the login screen, then power off.

Runs in the `iso` toolbox:  python3 ~/Projects/my_system/install/vm-boot-test.py
Test values only (from ks.cfg's VM branch): LUKS "vmtest-luks", user test/test.
"""
import os, re, socket, subprocess, sys, time

VM = os.path.expanduser("~/VMs/test")
OVMF = "/usr/share/edk2/ovmf"
SER = f"{VM}/serial.sock"
MON = f"{VM}/monitor.sock"
LOG = open(f"{VM}/boot-serial.log", "wb")

for p in (SER, MON):
    if os.path.exists(p):
        os.unlink(p)

qemu = subprocess.Popen([
    "qemu-system-x86_64", "-name", "my_system-boot", "-enable-kvm", "-machine", "q35",
    "-cpu", "host", "-smp", "4", "-m", "8192",
    "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}/OVMF_CODE.fd",
    "-drive", f"if=pflash,format=raw,file={VM}/vars.fd",
    "-drive", f"file={VM}/disk.qcow2,if=virtio,format=qcow2",
    "-nic", "user,model=virtio-net-pci", "-device", "virtio-vga", "-display", "none",
    "-chardev", f"socket,id=s0,path={SER},server=on,wait=off", "-serial", "chardev:s0",
    "-monitor", f"unix:{MON},server,nowait",
])

def connect(path, tries=60):
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            return s
        except OSError:
            time.sleep(1)
    sys.exit(f"cannot connect to {path}")

ser = connect(SER)
ser.settimeout(1)
buf = b""

def wait_for(pattern, timeout):
    """Read serial output until regex `pattern` matches; return the text read."""
    global buf
    end = time.time() + timeout
    rx = re.compile(pattern.encode())
    while time.time() < end:
        try:
            chunk = ser.recv(65536)
            if not chunk:
                break
            LOG.write(chunk); LOG.flush()
            buf += chunk
        except socket.timeout:
            pass
        m = rx.search(buf)
        if m:
            out, buf = buf[:m.end()], buf[m.end():]
            return out.decode(errors="replace")
    raise TimeoutError(f"timed out waiting for {pattern!r}")

def send(text):
    ser.sendall(text.encode())

def monitor(cmd):
    m = connect(MON, 5)
    m.settimeout(5)
    time.sleep(0.3)
    m.recv(65536)
    m.sendall((cmd + "\n").encode())
    time.sleep(2)
    m.close()

try:
    print("booting; waiting for the disk passphrase prompt ...", flush=True)
    wait_for(r"[Pp]assphrase", 300)
    time.sleep(1)
    send("vmtest-luks\r")
    print("passphrase sent; waiting for the login prompt ...", flush=True)
    wait_for(r"login: ", 300)
    time.sleep(45)
    monitor(f"screendump {VM}/login-screen.png -f png")
    send("test\r"); wait_for(r"Password: ", 30); send("test\r")
    wait_for(r"\$ $", 60)
    checks = r"""
printf '==%s==\n' BEGIN
echo "## kernel:"; uname -r
echo "## installed:"; rpm -q niri dms dms-greeter greetd claude-desktop brave-origin toolbox nvidia-kmod-control nautilus sushi ptyxis cups | sed 's/^/  /'
echo "## packages total: $(rpm -qa | wc -l)"
echo "## boot target: $(systemctl get-default)"
echo "## greetd: $(systemctl is-enabled greetd) / $(systemctl is-active greetd)"
echo "## dms with niri: $(ls /etc/systemd/user/niri.service.wants/ 2>/dev/null)"
echo "## disk:"; lsblk -o NAME,FSTYPE,MOUNTPOINTS | sed 's/^/  /'
echo "## claude-desktop-verify:"; claude-desktop-verify 2>&1 | tail -1
echo "## repos:"; ls /etc/yum.repos.d/ | sed 's/^/  /'
echo "## kickstart post log end:"; echo test | sudo -S tail -3 /root/ks-post.log 2>/dev/null | sed 's/^/  /'
echo "## ks-done:"; echo test | sudo -S cat /root/ks-done 2>/dev/null
echo "## unsigned packages:"; echo test | sudo -S cat /root/unsigned-packages.txt 2>/dev/null | sed 's/^/  /'
echo "## failed units:"; systemctl --failed --no-legend | sed 's/^/  /'
echo "## graphics:"; ls /dev/dri/ | sed 's/^/  /'
echo "## greetd status:"; systemctl status greetd --no-pager -n 0 | sed -n '1,4p' | sed 's/^/  /'
echo "## login-screen log:"; echo test | sudo -S journalctl -b --no-pager -o cat -u greetd 2>/dev/null | tail -25 | sed 's/^/  /'
echo "## niri/greeter errors:"; echo test | sudo -S journalctl -b --no-pager -o short-monotonic -p warning 2>/dev/null | grep -iE 'niri|greet|quickshell|dms|egl|gbm|drm' | tail -25 | sed 's/^/  /'
printf '==%s==\n' END
"""
    for line in checks.strip().splitlines():
        send(line + "\r")
        time.sleep(0.05)
    out = wait_for(r"==END==", 240)
    print(out[out.rfind("==BEGIN==") + 10:].replace("\r", ""), flush=True)
    send("echo test | sudo -S poweroff\r")
    qemu.wait(timeout=120)
except Exception as e:
    print(f"BOOT TEST ERROR: {e}", flush=True)
    print(buf.decode(errors="replace")[-2000:], flush=True)
    monitor(f"screendump {VM}/error-screen.png -f png")
    qemu.kill()
    sys.exit(1)
print(f"screenshot: {VM}/login-screen.png", flush=True)
