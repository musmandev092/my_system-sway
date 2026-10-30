#!/usr/bin/python3 -I
"""Doctor security audit: runs Lynis (open source, GPL-3.0, from Fedora) on this computer and prints its findings
for the Doctor panel. Lynis only reads the system; nothing is changed and nothing is sent anywhere by this script.

  security.py user          run without admin rights (no password, a few less tests)
  security.py full          run with admin rights (one polkit password prompt, all tests)
  security.py parse FILE    just read an existing Lynis report file

Output, one line per finding:
  SEC|score|tests|lynis version|mode
  WARN|id|area|what is wrong|detail      something Lynis considers a problem
  SUG|id|area|suggestion|detail          a way to make the system harder to attack
  FAIL|reason                            the audit could not run
"""
import os
import subprocess
import sys

AREAS = {
    "ACCT": "Accounting", "AUTH": "Passwords & login", "BANN": "Banners", "BOOT": "Boot & services",
    "CONT": "Containers", "CRYP": "Encryption", "DBS": "Databases", "DEB": "Packages", "FILE": "Files",
    "FINT": "File integrity", "FIRE": "Firewall", "HRDN": "Hardening", "HTTP": "Web server", "INSE": "Insecure services",
    "KRNL": "Kernel", "LDAP": "LDAP", "LOGG": "Logging", "MAIL": "Mail", "MALW": "Malware", "NAME": "DNS",
    "NETW": "Network", "PKGS": "Packages", "PRNT": "Printing", "SCHD": "Scheduled jobs", "SHLL": "Shell",
    "SNMP": "SNMP", "SQD": "Proxy", "SSH": "SSH", "STRG": "Storage", "TIME": "Time sync", "TOOL": "Security tools",
    "USB": "USB", "VIRT": "Virtualization", "ACCT-": "Accounting",
}


def area(test_id):
    return AREAS.get(test_id.split("-")[0], test_id.split("-")[0] or "Other")


def clean(s):
    return (s or "").replace("|", "/").replace("\n", " ").strip()


def detail(parts):
    for p in parts[3:5]:
        if p and p != "-":
            return clean(p)
    return ""


def parse(path, mode):
    score, tests, version = "", 0, ""
    items = []
    seen = set()
    with open(path, errors="replace") as f:
        for ln in f:
            ln = ln.rstrip("\n")
            if ln.startswith("hardening_index="):
                score = ln.split("=", 1)[1]
            elif ln.startswith("lynis_version="):
                version = ln.split("=", 1)[1]
            elif ln.startswith("tests_executed="):
                tests = len([t for t in ln.split("=", 1)[1].split("|") if t])
            elif ln.startswith(("warning[]=", "suggestion[]=")):
                kind = "WARN" if ln.startswith("warning") else "SUG"
                p = ln.split("=", 1)[1].split("|")
                if len(p) >= 2:
                    row = "%s|%s|%s|%s|%s" % (kind, clean(p[0]), area(p[0]), clean(p[1]), detail(p))
                    if row not in seen:  # a report that holds two runs would list everything twice
                        seen.add(row)
                        items.append(row)
    print("SEC|%s|%s|%s|%s" % (score, tests, version, mode))
    for it in sorted(items, key=lambda x: (x.startswith("SUG"), x)):
        print(it)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "parse":
        parse(sys.argv[2], "file")
        return
    mode = sys.argv[1] if len(sys.argv) > 1 else "user"
    cache = os.path.join(os.path.expanduser("~"), ".cache", "my_system-doctor")
    os.makedirs(cache, exist_ok=True)
    report, log = os.path.join(cache, "lynis-report.dat"), os.path.join(cache, "lynis.log")
    for p in (report, log):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass
    base = ["lynis", "audit", "system", "--quick", "--no-colors", "--quiet", "--report-file", report, "--logfile", log]
    if mode == "full":
        # pkexec cleans the environment, so the two paths go in as arguments of a tiny sh wrapper
        cmd = ["pkexec", "/bin/sh", "-c", base_cmd(base) + '; chown "$PKEXEC_UID" "$1" "$2"', "sh", report, log]
    else:
        cmd = base
    try:
        # output goes nowhere: Lynis leaves helper processes holding a pipe open, which would block us
        subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=340)
    except Exception as e:
        print("FAIL|%s" % e)
        return
    if not os.path.isfile(report) or os.path.getsize(report) == 0:
        print("FAIL|Lynis did not produce a report (is the lynis package installed? was the admin prompt cancelled?)")
        return
    parse(report, mode)


def base_cmd(base):
    # '"$1"' and '"$2"' are the report and log paths given after the script name
    out = []
    skip = 0
    for i, a in enumerate(base):
        if skip:
            skip -= 1
            continue
        if a == "--report-file":
            out += ["--report-file", '"$1"']
            skip = 1
        elif a == "--logfile":
            out += ["--logfile", '"$2"']
            skip = 1
        else:
            out.append(a)
    return " ".join(out)


main()
