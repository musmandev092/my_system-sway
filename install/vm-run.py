#!/usr/bin/env python3
"""Boot the installed test VM, unlock LUKS, log in as `test` on the serial
console, run a shell script, print its output, save a screenshot, power off.

Usage (in the `iso` toolbox):
    python3 vm-run.py SCRIPT.sh [--screenshot NAME] [--settle SECONDS] [--share DIR]
SCRIPT runs as user `test` (sudo password: test). With --share DIR, DIR is
packed into an ISO and attached; the script can mount it from /dev/sr0.
Test values only (from ks.cfg's VM branch): LUKS "test", user test/test.
"""
import argparse, os, re, socket, subprocess, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("script")
ap.add_argument("--screenshot", default="screen")
ap.add_argument("--settle", type=int, default=45, help="seconds to wait after boot before the screenshot")
ap.add_argument("--share", help="directory to attach as a CD (packed with xorriso)")
ap.add_argument("--timeout", type=int, default=1800, help="seconds the script may run")
args = ap.parse_args()

VM = os.path.expanduser("~/VMs/test")
OVMF = "/usr/share/edk2/ovmf"
RENDER = os.path.realpath("/dev/dri/by-path/pci-0000:00:02.0-render")
SER, MON = f"{VM}/serial.sock", f"{VM}/monitor.sock"
LOG = open(f"{VM}/run-serial.log", "wb")
for p in (SER, MON):
    if os.path.exists(p):
        os.unlink(p)

cmd = [
    "qemu-system-x86_64", "-name", "my_system-run", "-enable-kvm", "-machine", "q35",
    "-cpu", "host", "-smp", "18", "-m", "32768",
    "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}/OVMF_CODE.fd",
    "-drive", f"if=pflash,format=raw,file={VM}/vars.fd",
    "-drive", f"file={VM}/disk.qcow2,if=virtio,format=qcow2",
    "-nic", "user,model=virtio-net-pci",
    "-device", "virtio-vga-gl", "-display", f"egl-headless,rendernode={RENDER}",
    "-chardev", f"socket,id=s0,path={SER},server=on,wait=off", "-serial", "chardev:s0",
    "-monitor", f"unix:{MON},server,nowait",
]
if args.share:
    share_iso = f"{VM}/share.iso"
    subprocess.run(["xorriso", "-as", "mkisofs", "-quiet", "-R", "-J", "-V", "SHARE",
                    "-o", share_iso, args.share], check=True)
    cmd += ["-drive", f"file={share_iso},media=cdrom,readonly=on"]
qemu = subprocess.Popen(cmd)

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

def screenshot(name):
    m = connect(MON, 5)
    m.settimeout(5)
    time.sleep(0.3)
    try:
        m.recv(65536)
    except socket.timeout:
        pass
    m.sendall(f"screendump {VM}/{name}.png -f png\n".encode())
    time.sleep(3)
    try:
        reply = m.recv(65536).decode(errors="replace").replace("(qemu)", "").strip()
        if reply and "screendump" not in reply:
            print(f"screendump said: {reply}", flush=True)
    except socket.timeout:
        pass
    m.close()

ANSI = re.compile(r"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[a-zA-Z]|\r")
try:
    wait_for(r"[Pp]assphrase", 300)
    time.sleep(1)
    send("test\r")
    wait_for(r"login: ", 300)
    time.sleep(args.settle)
    send("test\r"); wait_for(r"Password: ", 30); send("test\r")
    wait_for(r"(\$ |> |❯)", 90)
    import base64
    send("stty -echo; export PAGER=cat SYSTEMD_PAGER=cat\r")
    shot = ("u=$(id -u greeter); s=$(echo test | sudo -S sh -c \"ls /run/user/$u/sway-ipc.*.sock\" 2>/dev/null | head -1); "
            "w=$(echo test | sudo -S sh -c \"ls /run/user/$u/ | grep -m1 '^wayland-[0-9]*$'\" 2>/dev/null); "
            "echo test | sudo -S -u greeter env XDG_RUNTIME_DIR=/run/user/$u SWAYSOCK=$s WAYLAND_DISPLAY=$w "
            "grim /tmp/vm-shot.png >/dev/null 2>&1; sleep 2; "
            "printf '==%s==\\n' SHOT; echo test | sudo -S base64 -w0 /tmp/vm-shot.png 2>/dev/null; printf '\\n==%s==\\n' ENDSHOT\r")
    send(shot)
    raw = ANSI.sub("", wait_for(r"==ENDSHOT==", 60))
    m = re.search(r"==SHOT==\s*([A-Za-z0-9+/=]+)\s*==ENDSHOT==", raw)
    if m:
        open(f"{VM}/{args.screenshot}.png", "wb").write(base64.b64decode(m.group(1)))
    else:
        print("screenshot: none (no greeter sway running?)", flush=True)
    payload = base64.b64encode(open(args.script, "rb").read()).decode()
    send(f"echo {payload} | base64 -d > /tmp/run.sh; printf '==%s==\\n' START; bash /tmp/run.sh 2>&1; printf '==%s==\\n' DONE\r")
    out = wait_for(r"==DONE==", args.timeout)
    text = ANSI.sub("", out)
    print(text[text.rfind("==START==") + 10: text.rfind("==DONE==")], flush=True)
    send("echo test | sudo -S systemctl poweroff\r")
    try:
        qemu.wait(timeout=90)
    except subprocess.TimeoutExpired:
        qemu.kill()
except Exception as e:
    print(f"VM RUN ERROR: {e}", flush=True)
    print(ANSI.sub("", buf.decode(errors="replace"))[-3000:], flush=True)
    try:
        screenshot("error-screen")
    except SystemExit:
        pass
    qemu.kill()
    sys.exit(1)
print(f"screenshot: {VM}/{args.screenshot}.png", flush=True)
