#!/usr/bin/python3 -I
"""Doctor log reader. Prints one line per finding for the Doctor panel (read-only, changes nothing).
Every line carries a scope (User / System / Kernel) and a category (Sway, DMS, Kernel, System services, Apps)
so the panel can build its filter buttons from what is really in the logs:

  CRASH|time|program|signal|pid|scope|category     an app that crashed this boot (core dump)
  FAILED|unit|scope|result|category                a systemd unit that failed
  ERR|count|source|scope|category|latest message   errors this boot, grouped by program and message
  NOTE|text                                        something the reader could not look at
"""
import collections
import datetime
import json
import re
import subprocess

ANSI = re.compile(r"\x1b\[[0-9;]*m")
# lines some programs log as "error" priority although they are only debug or info chatter
NOISE = re.compile(r"level=(debug|info)\b|\[DEBUG\]|\[INFO\]|\bINFO\b|\bDEBUG\b", re.I)
# sway, quickshell and dms write their own errors at normal priority, with the word ERROR in the text
OWN_ERR = re.compile(r"\[ERROR\]|\bERROR\b|\bFATAL\b|\bCRIT\b")
OWN_SOURCES = ("sway", "qs", "dms", "dms-greeter", "greetd", "swaybg", "swaynag", "waybar")

SWAY = ("sway", "swaybg", "swaynag", "swayidle", "swaylock", "waybar", "xdg-desktop-portal-wlr", "xdpw")
DMS = ("qs", "quickshell", "dms", "dms-greeter", "greetd", "dankdash", "matugen")
SYSTEM_WORDS = ("systemd", "dbus", "udev", "polkit", "networkmanager", "bluetooth", "wpa_supplicant", "pipewire",
                "wireplumber", "xdg-", "gvfs", "gcr", "dconf", "tracker", "accounts", "upower", "fwupd", "cups",
                "firewalld", "auditd", "sddm", "gdm", "login", "pam", "sudo", "kernel", "gnome-keyring", "rtkit")


def category(src):
    s = (src or "").lower()
    if s == "kernel":
        return "Kernel"
    if any(s == w or s.startswith(w + "-") or s.startswith(w + ".") for w in SWAY):
        return "Sway"
    if any(s == w or s.startswith(w + "-") or s.startswith(w + ".") for w in DMS):
        return "DMS"
    if any(w in s for w in SYSTEM_WORDS):
        return "System services"
    return "Apps"


def run(cmd, limit=25):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=limit)
        return r.stdout, r.returncode
    except Exception:
        return "", 1


def text(msg, n=190):
    if isinstance(msg, list):
        msg = bytes(msg).decode(errors="replace")
    msg = ANSI.sub("", msg or "").replace("\n", " ").replace("|", "/").strip()
    return msg[:n]


def shape(msg):
    """Same message with the numbers blanked, so 'Page-flip failed on card 1' and '... card 2' group together."""
    return re.sub(r"\d+", "#", msg)[:70]


def scope_of(entry, src):
    if src == "kernel":
        return "Kernel"
    return "System" if str(entry.get("_UID", "")) == "0" else "User"


# ---- crashes this boot (core dumps)
boot = ""
try:
    up = float(open("/proc/uptime").read().split()[0])
    boot = (datetime.datetime.now() - datetime.timedelta(seconds=up)).strftime("%Y-%m-%d %H:%M:%S")
except Exception:
    pass
args = ["coredumpctl", "list", "--no-pager", "--no-legend", "--json=short"]
if boot:
    args += ["--since", boot]
out, rc = run(args)
try:
    for d in json.loads(out or "[]"):
        exe = (d.get("exe") or d.get("comm") or "unknown").split("/")[-1]
        t = d.get("time", 0)
        when = datetime.datetime.fromtimestamp(t / 1e6).strftime("%H:%M:%S") if isinstance(t, (int, float)) else str(t)[:19]
        sc = "System" if d.get("uid") == 0 else "User"
        print("CRASH|%s|%s|signal %s|pid %s|%s|%s" % (when, exe, d.get("sig", ""), d.get("pid", ""), sc, category(exe)))
except Exception:
    pass

# ---- failed units
for scope, cmd in (("System", ["systemctl", "--failed", "--no-legend", "--plain"]),
                   ("User", ["systemctl", "--user", "--failed", "--no-legend", "--plain"])):
    out, _ = run(cmd, 10)
    for ln in out.splitlines():
        p = ln.split()
        if p:
            print("FAILED|%s|%s|%s|%s" % (p[0], scope, " ".join(p[2:4]), category(p[0].rsplit(".", 1)[0])))

# ---- errors this boot, grouped by program and message
groups = collections.OrderedDict()


def add(entry, src, msg):
    if not msg or NOISE.search(msg):
        return
    g = groups.setdefault((src, shape(msg)), {"n": 0, "msg": "", "scope": scope_of(entry, src)})
    g["n"] += 1
    g["msg"] = msg


seen = set()
for scope in ([], ["--user"]):
    out, rc = run(["journalctl"] + scope + ["-b", "-p", "err", "-o", "json", "--no-pager", "-n", "8000"])
    if not out and rc != 0 and not scope:
        print("NOTE|Could not read the system journal (add your user to the systemd-journal group to see system errors).")
    for ln in out.splitlines():
        try:
            e = json.loads(ln)
        except Exception:
            continue
        key = e.get("__CURSOR") or ln
        if key in seen:
            continue
        seen.add(key)
        add(e, e.get("SYSLOG_IDENTIFIER") or e.get("_COMM") or "unknown", text(e.get("MESSAGE")))

    # sway, quickshell and dms log their errors at normal priority, so look for the word ERROR
    cmd = ["journalctl"] + scope + ["-b", "-o", "json", "--no-pager", "-n", "20000"]
    for s_ in OWN_SOURCES:
        cmd += ["_COMM=" + s_]
    out, rc = run(cmd)
    for ln in out.splitlines():
        try:
            e = json.loads(ln)
        except Exception:
            continue
        key = e.get("__CURSOR") or ln
        if key in seen:
            continue
        seen.add(key)
        msg = text(e.get("MESSAGE"))
        if OWN_ERR.search(msg):
            add(e, e.get("SYSLOG_IDENTIFIER") or e.get("_COMM") or "unknown", msg)

for (src, _), g in sorted(groups.items(), key=lambda kv: -kv[1]["n"])[:40]:
    print("ERR|%d|%s|%s|%s|%s" % (g["n"], src, g["scope"], category(src), g["msg"]))
