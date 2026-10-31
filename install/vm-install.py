#!/usr/bin/env python3
"""Install my_system-fedora44-vm.iso into a fresh UEFI VM, answering the
installer's questions over the serial console like a person would.
Test answers: computer vmtest, user test / test, disk password = account password (test).

Runs in the `iso` toolbox:  python3 vm-install.py [--questions-only]
  --questions-only  answer "no" at the end: tests the questions, installs nothing
"""
import os, re, shutil, socket, subprocess, sys, time

ISO = os.path.expanduser("~/VMs/fedora-iso/my_system-fedora44-vm.iso")
VM = os.path.expanduser("~/VMs/test")
OVMF = "/usr/share/edk2/ovmf"
SER = f"{VM}/questions.sock"
CON = f"{VM}/install-serial.log"

ANSWERS = [
    (r"Computer name.*\[", "vmtest"),
    (r"Time zone \[", ""),
    (r"Full name \[", "Test User"),
    (r"Username \[", "test"),
    (r"  Password: ", "test"),
    (r"  Password \(again\): ", "test"),
    (r"same password as your account\? \[", "y"),
    (r"Install on disk number \[", ""),
    (r"Type WIPE to erase /dev/[a-z0-9]+: ", "WIPE"),
    (r"Install now\? \(yes/no\): ", "yes"),
]

QUESTIONS_ONLY = "--questions-only" in sys.argv
if QUESTIONS_ONLY:
    ANSWERS[-1] = (ANSWERS[-1][0], "no")

if not os.path.exists(ISO):
    sys.exit(f"missing {ISO} (run build-iso.sh)")
shutil.rmtree(VM, ignore_errors=True)
os.makedirs(VM)
subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", f"{VM}/disk.qcow2", "60G"], check=True)
shutil.copy(f"{OVMF}/OVMF_VARS.fd", f"{VM}/vars.fd")
log = open(f"{VM}/questions.log", "wb")

qemu = subprocess.Popen([
    "qemu-system-x86_64", "-name", "my_system-install", "-enable-kvm", "-machine", "q35",
    "-cpu", "host", "-smp", "18", "-m", "32768",
    "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF}/OVMF_CODE.fd",
    "-drive", f"if=pflash,format=raw,file={VM}/vars.fd",
    "-drive", f"file={VM}/disk.qcow2,if=virtio,format=qcow2",
    "-cdrom", ISO, "-boot", "once=d",
    "-nic", "user,model=virtio-net-pci", "-device", "virtio-vga", "-display", "none",
    "-serial", f"file:{CON}",
    "-chardev", f"socket,id=s1,path={SER},server=on,wait=off", "-serial", "chardev:s1",
    "-monitor", f"unix:{VM}/monitor.sock,server,nowait", "-no-reboot",
])

for _ in range(60):
    try:
        ser = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); ser.connect(SER); break
    except OSError:
        time.sleep(1)
else:
    sys.exit("no serial socket")
ser.settimeout(1)
buf = b""

def wait_for(pattern, timeout):
    global buf
    rx, end = re.compile(pattern.encode()), time.time() + timeout
    while time.time() < end:
        try:
            chunk = ser.recv(65536)
            if not chunk:
                break
            log.write(chunk); log.flush(); buf += chunk
        except socket.timeout:
            pass
        m = rx.search(buf)
        if m:
            buf = buf[m.end():]
            return
        if b"INSTALL STOPPED" in buf:
            raise RuntimeError("installer stopped: " + buf[-400:].decode(errors="replace"))
    raise TimeoutError(f"timed out waiting for {pattern!r}")

try:
    for i, (prompt, answer) in enumerate(ANSWERS):
        wait_for(prompt, 600 if i == 0 else 60)
        time.sleep(0.3)
        ser.sendall((answer + "\r").encode())
        print(f"answered: {prompt.strip()!r:45} -> {'*' * len(answer) if 'assword' in prompt else answer!r}", flush=True)
    if QUESTIONS_ONLY:
        try:
            wait_for(r"zzz-never", 60)
        except RuntimeError as e:
            print("installer stopped as expected:", str(e).split("INSTALL STOPPED:")[-1].split("\n")[0].strip(), flush=True)
        else:
            print("ERROR: installer did not stop", flush=True)
        qemu.kill()
        tail = re.sub(rb"\x1b\[[0-9;?]*[a-zA-Z]", b"", open(f"{VM}/questions.log", "rb").read()).decode(errors="replace")
        print(tail[tail.rfind("=== Summary"):tail.rfind("=== Summary") + 600], flush=True)
        sys.exit(0)
    print("installing ...", flush=True)
    while qemu.poll() is None:
        try:
            chunk = ser.recv(65536)
            if chunk:
                log.write(chunk); log.flush()
        except socket.timeout:
            pass
        except OSError:
            break
    qemu.wait()
except Exception as e:
    print(f"VM INSTALL ERROR: {e}", flush=True)
    qemu.kill()
    sys.exit(1)
text = open(f"{VM}/install-serial.log", "rb").read().decode(errors="replace")
print("finished: reboot seen" if "reboot: Restarting system" in text or "reboot: Power down" in text
      else "finished (check install-serial.log)", flush=True)
