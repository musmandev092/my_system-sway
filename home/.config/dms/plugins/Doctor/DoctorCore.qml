import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// System doctor: a checklist of the things that break this setup, every crash and error found in the
// logs this boot, and DMS's own `dms doctor` report. Read-only: it changes nothing.
Scope {
    id: root

    property real cornerRadius: 1
    property color scrim: "#c0101014"
    property color panelColor: "#2b2b32"
    property color accent: "#89b4fa"
    property color textColor: "#e8e8ee"
    property color dimColor: "#a0a0ac"
    readonly property color okColor: "#7bd88f"
    readonly property color warnColor: "#f2c94c"
    readonly property color badColor: "#f2777a"

    property bool shown: false
    property bool running: false
    property bool logsRunning: false
    property bool justCopied: false
    property var rows: []
    property var crashes: []
    property var failed: []
    property var errors: []
    property var kernel: []
    property var notes: []
    property string scopeFilter: ""
    property string catFilter: ""

    function passes(it) { return (!scopeFilter || it.scope === scopeFilter) && (!catFilter || it.cat === catFilter); }
    readonly property var shownCrashes: crashes.filter(passes)
    readonly property var shownFailed: failed.filter(passes)
    readonly property var shownErrors: errors.filter(passes)
    readonly property int totalItems: crashes.length + failed.length + errors.length
    readonly property int shownItems: shownCrashes.length + shownFailed.length + shownErrors.length

    // Filter buttons are built from what is really in the logs, the biggest group first.
    function tally(key) {
        const m = {};
        for (const arr of [crashes, failed, errors]) for (const it of arr) m[it[key]] = (m[it[key]] || 0) + 1;
        return Object.keys(m).map(k => ({ name: k, n: m[k] })).sort((a, b) => b.n - a.n);
    }
    readonly property var scopeChips: tally("scope")
    readonly property var catChips: tally("cat")

    // ---- security audit (Lynis), a second view of the same panel
    property string view: "doctor"
    property bool secRunning: false
    property bool secDone: false
    property string secMode: "user"
    property string secScore: ""
    property string secTests: ""
    property string secVersion: ""
    property string secFail: ""
    property var secWarn: []
    property var secSug: []
    property string secArea: ""
    readonly property string secScript: Qt.resolvedUrl("security.py").toString().replace("file://", "")
    readonly property var shownSecWarn: secWarn.filter(i => !secArea || i.area === secArea)
    readonly property var shownSecSug: secSug.filter(i => !secArea || i.area === secArea)
    readonly property var secAreaChips: {
        const m = {};
        for (const arr of [secWarn, secSug]) for (const it of arr) m[it.area] = (m[it.area] || 0) + 1;
        return Object.keys(m).map(k => ({ name: k, n: m[k] })).sort((a, b) => b.n - a.n);
    }
    readonly property color secColor: Number(secScore) >= 80 ? okColor : Number(secScore) >= 60 ? warnColor : badColor
    property string dmsReport: ""
    property string outputName: ""
    readonly property string logsScript: Qt.resolvedUrl("logs.py").toString().replace("file://", "")

    readonly property int okCount: rows.filter(r => r.level === "OK").length
    readonly property int warnCount: rows.filter(r => r.level === "WARN").length
    readonly property int badCount: rows.filter(r => r.level === "BAD").length
    readonly property bool anyBad: badCount > 0 || crashes.length > 0
    readonly property bool anyWarn: warnCount > 0 || failed.length > 0 || errors.length > 0 || kernel.length > 0

    // One line per check: LEVEL|label|detail
    readonly property string checks: `
ok()   { echo "OK|$1|$2"; }
warn() { echo "WARN|$1|$2"; }
bad()  { echo "BAD|$1|$2"; }

v=$(sway --version 2>/dev/null | awk '{print $3}')
case "$v" in 1.1[2-9]*|1.[2-9][0-9]*) ok "Sway" "$v";; "") bad "Sway" "not found";; *) warn "Sway" "$v (1.12 or newer wanted)";; esac

pgrep -x qs >/dev/null && ok "DMS shell" "running" || bad "DMS shell" "not running"

if lspci -n 2>/dev/null | grep -qE ' 030[02]: 10de:'; then
    if timeout 5 nvidia-smi -L >/dev/null 2>&1; then ok "NVIDIA driver" "$(timeout 5 nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
    else bad "NVIDIA driver" "NVIDIA card found but the driver is not working"; fi
    if lsmod | grep -qE '^(nouveau|nova_core)'; then bad "nouveau / nova_core" "an open-source NVIDIA driver is loaded"
    else ok "nouveau / nova_core" "not loaded"; fi
else ok "NVIDIA" "no NVIDIA card in this machine"; fi

rpm -q gnome-keyring-pam >/dev/null 2>&1 || warn "Keyring PAM" "gnome-keyring-pam is missing: browsers will ask for the keyring password"
if pgrep -u "$(id -u)" -x gnome-keyring-d >/dev/null 2>&1; then
    l=$(timeout 3 busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked 2>/dev/null)
    case "$l" in
        "b false") ok "Login keyring" "unlocked";;
        "b true")  warn "Login keyring" "locked: its password is not your login password";;
        *)         warn "Login keyring" "no 'login' keyring (created at your next login)";;
    esac
else warn "Login keyring" "keyring service not started yet"; fi

[ "$(systemctl is-active firewalld 2>/dev/null)" = active ] && ok "Firewall" "running" || bad "Firewall" "firewalld is not running"
se=$(getenforce 2>/dev/null); [ "$se" = Enforcing ] && ok "SELinux" "enforcing" || warn "SELinux" "\${se:-unknown}"

m=$(swaymsg -t get_outputs -r 2>/dev/null | python3 -I -c 'import json,sys;print(sum(1 for o in json.load(sys.stdin) if o["active"]))' 2>/dev/null)
[ "\${m:-0}" -gt 0 ] && ok "Monitors" "$m active" || bad "Monitors" "none found"

p=$(df --output=pcent / | tail -1 | tr -dc 0-9)
if [ "\${p:-0}" -lt 85 ]; then ok "Disk" "root is \${p}% full"; else warn "Disk" "root is \${p}% full"; fi

k=$(rpm -q kernel-core 2>/dev/null | wc -l); [ "$k" -le 2 ] && ok "Kernels" "$k installed" || warn "Kernels" "$k installed (installonly_limit should be 2)"
`

    function parseChecks(text) {
        const out = [];
        for (const ln of text.split("\n")) {
            const m = /^(OK|WARN|BAD)\|([^|]*)\|(.*)$/.exec(ln);
            if (m) out.push({ level: m[1], label: m[2], detail: m[3] });
        }
        rows = out;
    }

    function parseLogs(text) {
        const cr = [], fl = [], er = [], nt = [];
        for (const ln of text.split("\n")) {
            const p = ln.split("|");
            if (p[0] === "CRASH") cr.push({ when: p[1], what: p[2], sig: p[3] + ", " + p[4], scope: p[5], cat: p[6] });
            else if (p[0] === "FAILED") fl.push({ unit: p[1], scope: p[2], result: p[3], cat: p[4] });
            else if (p[0] === "ERR") er.push({ n: p[1], src: p[2], scope: p[3], cat: p[4], msg: p.slice(5).join("|") });
            else if (p[0] === "NOTE") nt.push(p.slice(1).join("|"));
        }
        crashes = cr; failed = fl; errors = er; kernel = []; notes = nt;
        scopeFilter = ""; catFilter = "";
    }

    function reportText() {
        let t = "System doctor report\n\n";
        for (const r of rows) t += "[" + r.level + "] " + r.label + ": " + r.detail + "\n";
        if (crashes.length) { t += "\nCrashes this boot\n"; for (const c of crashes) t += "  " + c.when + "  " + c.what + "  (" + c.sig + ")  [" + c.scope + ", " + c.cat + "]\n"; }
        if (failed.length) { t += "\nFailed services\n"; for (const f of failed) t += "  " + f.unit + "  [" + f.scope + ", " + f.cat + "]\n"; }
        if (errors.length) { t += "\nErrors in the logs this boot (count, source, latest message)\n"; for (const e of errors) t += "  " + e.n + "x  " + e.src + " [" + e.scope + ", " + e.cat + "]: " + e.msg + "\n"; }
        t += "\nDMS health report\n" + dmsReport + "\n";
        return t;
    }

    function secReportText() {
        let t = "Security audit (Lynis " + secVersion + ", " + secMode + " mode)\nHardening score: " + secScore + " / 100, " + secTests + " tests\n";
        if (secFail) t += secFail + "\n";
        if (secWarn.length) { t += "\nWarnings\n"; for (const w of secWarn) t += "  " + w.id + " [" + w.area + "] " + w.text + (w.detail ? " (" + w.detail + ")" : "") + "\n"; }
        if (secSug.length) { t += "\nSuggestions\n"; for (const w of secSug) t += "  " + w.id + " [" + w.area + "] " + w.text + (w.detail ? " (" + w.detail + ")" : "") + "\n"; }
        return t;
    }

    function copyReport() {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" | wl-copy', "sh", view === "security" ? secReportText() : reportText()]);
        justCopied = true;
    }

    function parseSec(text) {
        const w = [], g = [];
        secFail = "";
        for (const ln of text.split("\n")) {
            const p = ln.split("|");
            if (p[0] === "SEC") { secScore = p[1]; secTests = p[2]; secVersion = p[3]; }
            else if (p[0] === "WARN") w.push({ id: p[1], area: p[2], text: p[3], detail: p.slice(4).join("|") });
            else if (p[0] === "SUG") g.push({ id: p[1], area: p[2], text: p[3], detail: p.slice(4).join("|") });
            else if (p[0] === "FAIL") secFail = p.slice(1).join("|");
        }
        secWarn = w; secSug = g; secArea = ""; secDone = true;
    }

    // mode "user": no password, a few tests less. mode "full": asks for the admin password once, runs all tests.
    function runSecurity(mode) {
        view = "security";
        secMode = mode;
        secWarn = []; secSug = []; secScore = ""; secTests = ""; secFail = ""; secArea = "";
        secDone = false;
        secRunning = true;
        secProc.running = true;
        scrollTop();
    }

    function scrollTop() { flick.contentY = 0; }

    function open() {
        rows = []; crashes = []; failed = []; errors = []; kernel = []; notes = [];
        view = "doctor";
        dmsReport = "Running dms doctor ...";
        justCopied = false;
        running = true;
        logsRunning = true;
        shown = true;
        checkProc.running = true;
        logsProc.running = true;
        reportProc.running = true;
    }

    function close() { shown = false; }

    function colorFor(level) { return level === "OK" ? okColor : level === "WARN" ? warnColor : badColor; }

    Process {
        id: checkProc
        command: ["timeout", "25", "sh", "-c", root.checks]
        stdout: StdioCollector { onStreamFinished: root.parseChecks(text) }
        onRunningChanged: if (!running) root.running = false
    }

    Process {
        id: logsProc
        command: ["timeout", "40", "python3", "-I", root.logsScript]
        stdout: StdioCollector { onStreamFinished: root.parseLogs(text) }
        onRunningChanged: if (!running) root.logsRunning = false
    }

    Process {
        id: secProc
        command: ["timeout", "360", "python3", "-I", root.secScript, root.secMode]
        stdout: StdioCollector { onStreamFinished: root.parseSec(text) }
        onRunningChanged: if (!running) root.secRunning = false
    }

    Process {
        id: reportProc
        command: ["sh", "-c", "timeout 30 dms doctor 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const i = text.indexOf("System Health Check");
                root.dmsReport = (i >= 0 ? text.slice(i) : text).trim();
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 2500
        running: root.justCopied
        onTriggered: root.justCopied = false
    }

    IpcHandler {
        target: "doctor"
        function open(): string { root.open(); return "ok"; }
        function close(): string { root.close(); return "ok"; }
        function toggle(): string { if (root.shown) root.close(); else root.open(); return "ok"; }
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === root.outputName) || Quickshell.screens[0]
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "doctor"

        onVisibleChanged: if (visible) keyGrab.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: root.scrim
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1040)
                height: parent.height - 80
                radius: root.cornerRadius
                color: root.panelColor
                border.width: 1
                border.color: root.accent

                Item {
                    id: keyGrab
                    focus: true
                    anchors.fill: parent
                    Keys.onEscapePressed: root.close()
                    Keys.onUpPressed: flick.contentY = Math.max(0, flick.contentY - 120)
                    Keys.onDownPressed: flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + 120)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_C) { root.copyReport(); event.accepted = true; }
                        else if (event.key === Qt.Key_L) { root.runSecurity((event.modifiers & Qt.ShiftModifier) ? "full" : "user"); event.accepted = true; }
                        else if (event.key === Qt.Key_D) { root.view = "doctor"; root.scrollTop(); event.accepted = true; }
                        else if (root.view === "security" && event.key === Qt.Key_A) { root.secArea = ""; event.accepted = true; }
                        else if (root.view === "security" && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            const c = root.secAreaChips[event.key - Qt.Key_1];
                            if (c) root.secArea = root.secArea === c.name ? "" : c.name;
                            event.accepted = true;
                        }
                        else if (root.view === "security" && event.key === Qt.Key_R) { root.runSecurity(root.secMode); event.accepted = true; }
                        else if (event.key === Qt.Key_R) { root.open(); event.accepted = true; }
                        else if (event.key === Qt.Key_A) { root.scopeFilter = ""; root.catFilter = ""; event.accepted = true; }
                        else if (event.key === Qt.Key_U) { root.scopeFilter = root.scopeFilter === "User" ? "" : "User"; event.accepted = true; }
                        else if (event.key === Qt.Key_S) { root.scopeFilter = root.scopeFilter === "System" ? "" : "System"; event.accepted = true; }
                        else if (event.key === Qt.Key_K) { root.scopeFilter = root.scopeFilter === "Kernel" ? "" : "Kernel"; event.accepted = true; }
                        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            const c = root.catChips[event.key - Qt.Key_1];
                            if (c) root.catFilter = root.catFilter === c.name ? "" : c.name;
                            event.accepted = true;
                        }
                    }
                }

                Column {
                    id: head
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
                    spacing: 6

                    Text {
                        width: parent.width
                        visible: root.view === "doctor"
                        text: (root.running || root.logsRunning) ? "System doctor: checking ..." :
                              "System doctor:   " + root.okCount + " checks ok   " + root.warnCount + " to look at   " + root.badCount + " problems   "
                              + root.crashes.length + " crashes   " + root.failed.length + " failed services   " + root.errors.length + " kinds of errors in the logs"
                        color: root.anyBad ? root.badColor : root.anyWarn ? root.warnColor : root.okColor
                        font.pixelSize: 16
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        visible: root.view === "security"
                        text: root.secRunning ? "Security audit: running Lynis, this takes about a minute ..." :
                              root.secFail ? "Security audit could not run" :
                              "Security audit:   hardening score " + root.secScore + " / 100   " + root.secTests + " tests   " + root.secWarn.length + " warnings   " + root.secSug.length + " suggestions"
                        color: root.secRunning ? root.dimColor : root.secFail ? root.badColor : root.secColor
                        font.pixelSize: 16
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        text: root.justCopied ? "Report copied to the clipboard." :
                              root.view === "security" ? "d back to the doctor   l audit again   Shift+L audit with admin rights   c copies   Up / Down scrolls   1-9 area   a all   Esc closes" :
                              "Up / Down scrolls   c copies   r checks again   Esc closes   l security audit   Filters: u user, s system, k kernel, 1-9 kind, a all"
                        color: root.dimColor
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 6
                        visible: root.totalItems > 0 && root.view === "doctor"
                        Text { text: "Where:"; color: root.dimColor; font.pixelSize: 12; height: 24; verticalAlignment: Text.AlignVCenter }
                        Repeater {
                            model: [{ name: "", n: root.totalItems }].concat(root.scopeChips)
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: root.scopeFilter === modelData.name
                                height: 24
                                width: scopeLabel.implicitWidth + 18
                                radius: root.cornerRadius
                                color: on ? root.accent : "transparent"
                                border.width: 1
                                border.color: root.accent
                                Text {
                                    id: scopeLabel
                                    anchors.centerIn: parent
                                    text: (modelData.name || "All") + "  " + modelData.n
                                    color: parent.on ? root.panelColor : root.textColor
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.scopeFilter = (root.scopeFilter === modelData.name ? "" : modelData.name) }
                            }
                        }
                        Text { text: "   Kind:"; color: root.dimColor; font.pixelSize: 12; height: 24; verticalAlignment: Text.AlignVCenter }
                        Repeater {
                            model: [{ name: "", n: root.totalItems }].concat(root.catChips)
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool on: root.catFilter === modelData.name
                                height: 24
                                width: catLabel.implicitWidth + 18
                                radius: root.cornerRadius
                                color: on ? root.accent : "transparent"
                                border.width: 1
                                border.color: root.accent
                                Text {
                                    id: catLabel
                                    anchors.centerIn: parent
                                    text: (index > 0 ? index + " " : "") + (modelData.name || "All") + "  " + modelData.n
                                    color: parent.on ? root.panelColor : root.textColor
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.catFilter = (root.catFilter === modelData.name ? "" : modelData.name) }
                            }
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 6
                        visible: root.view === "security" && root.secAreaChips.length > 0
                        Text { text: "Area:"; color: root.dimColor; font.pixelSize: 12; height: 24; verticalAlignment: Text.AlignVCenter }
                        Repeater {
                            model: [{ name: "", n: root.secWarn.length + root.secSug.length }].concat(root.secAreaChips)
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool on: root.secArea === modelData.name
                                height: 24
                                width: areaLabel.implicitWidth + 18
                                radius: root.cornerRadius
                                color: on ? root.accent : "transparent"
                                border.width: 1
                                border.color: root.accent
                                Text {
                                    id: areaLabel
                                    anchors.centerIn: parent
                                    text: (index > 0 && index < 10 ? index + " " : "") + (modelData.name || "All") + "  " + modelData.n
                                    color: parent.on ? root.panelColor : root.textColor
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.secArea = (root.secArea === modelData.name ? "" : modelData.name) }
                            }
                        }
                    }
                }

                Flickable {
                    id: flick
                    anchors { top: head.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
                    contentWidth: width
                    contentHeight: root.view === "doctor" ? content.height : secContent.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: content
                        visible: root.view === "doctor"
                        width: flick.width
                        spacing: 14

                        // ---- checklist
                        Flow {
                            width: parent.width
                            Repeater {
                                model: root.rows
                                delegate: Item {
                                    required property var modelData
                                    width: content.width / 2
                                    height: 28
                                    Rectangle {
                                        id: dot
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: root.colorFor(modelData.level)
                                    }
                                    Text {
                                        id: lab
                                        anchors { left: dot.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                        width: 150
                                        text: modelData.label
                                        color: root.textColor
                                        font.pixelSize: 14
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors { left: lab.right; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                        text: modelData.detail
                                        color: modelData.level === "OK" ? root.dimColor : root.colorFor(modelData.level)
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        // ---- crashes
                        Column {
                            visible: root.shownCrashes.length > 0
                            width: parent.width
                            spacing: 4
                            Text { text: "Crashes this boot (core dumps): " + root.shownCrashes.length; color: root.badColor; font.pixelSize: 14; font.bold: true }
                            Repeater {
                                model: root.shownCrashes
                                delegate: Row {
                                    required property var modelData
                                    spacing: 14
                                    Text { text: modelData.when; color: root.dimColor; font.pixelSize: 13; width: 80 }
                                    Text { text: modelData.what; color: root.textColor; font.pixelSize: 13; font.bold: true; width: 200 }
                                    Text { text: modelData.sig; color: root.dimColor; font.pixelSize: 13 }
                                }
                            }
                        }

                        // ---- failed services
                        Column {
                            visible: root.shownFailed.length > 0
                            width: parent.width
                            spacing: 4
                            Text { text: "Failed services: " + root.shownFailed.length; color: root.warnColor; font.pixelSize: 14; font.bold: true }
                            Repeater {
                                model: root.shownFailed
                                delegate: Row {
                                    required property var modelData
                                    spacing: 14
                                    Text { text: modelData.unit; color: root.textColor; font.pixelSize: 13; font.bold: true }
                                    Text { text: "(" + modelData.scope + ")"; color: root.dimColor; font.pixelSize: 13 }
                                }
                            }
                        }

                        // ---- errors in the logs
                        Column {
                            visible: root.shownErrors.length > 0
                            width: parent.width
                            spacing: 4
                            Text { text: "Errors in the logs this boot: " + root.shownErrors.length + " kinds (how many times, from which program, latest message)"; color: root.warnColor; font.pixelSize: 14; font.bold: true }
                            Repeater {
                                model: root.shownErrors
                                delegate: Item {
                                    required property var modelData
                                    width: content.width
                                    height: 24
                                    Text {
                                        id: cnt
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        width: 62
                                        text: modelData.n + "x"
                                        color: Number(modelData.n) > 100 ? root.badColor : root.warnColor
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    Text {
                                        id: srcT
                                        anchors { left: cnt.right; verticalCenter: parent.verticalCenter }
                                        width: 180
                                        text: modelData.src
                                        color: root.textColor
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        anchors { left: srcT.right; right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: modelData.msg
                                        color: root.dimColor
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.totalItems > 0 && root.shownItems === 0
                            text: "Nothing found for this filter."
                            color: root.dimColor
                            font.pixelSize: 13
                        }

                        Column {
                            visible: root.notes.length > 0
                            width: parent.width
                            Repeater {
                                model: root.notes
                                delegate: Text {
                                    required property var modelData
                                    width: content.width
                                    text: modelData
                                    color: root.dimColor
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // ---- DMS's own report
                        Rectangle { width: parent.width; height: 1; color: root.accent; opacity: 0.4 }
                        Text { text: "DMS health report (dms doctor)"; color: root.dimColor; font.pixelSize: 13; font.bold: true }
                        Text {
                            width: parent.width
                            text: root.dmsReport
                            color: root.textColor
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.NoWrap
                        }
                    }

                    Column {
                        id: secContent
                        visible: root.view === "security"
                        width: flick.width
                        spacing: 14

                        Text {
                            visible: root.secFail !== ""
                            width: parent.width
                            text: root.secFail
                            color: root.badColor
                            font.pixelSize: 13
                            wrapMode: Text.WordWrap
                        }

                        Column {
                            visible: root.shownSecWarn.length > 0
                            width: parent.width
                            spacing: 6
                            Text { text: "Warnings (Lynis thinks these are real problems): " + root.shownSecWarn.length; color: root.badColor; font.pixelSize: 14; font.bold: true }
                            Repeater {
                                model: root.shownSecWarn
                                delegate: Column {
                                    required property var modelData
                                    width: secContent.width
                                    Row {
                                        spacing: 10
                                        Text { text: modelData.id; color: root.badColor; font.pixelSize: 12; font.bold: true; width: 96 }
                                        Text { text: modelData.area; color: root.dimColor; font.pixelSize: 12; width: 130; elide: Text.ElideRight }
                                        Text { text: modelData.text; color: root.textColor; font.pixelSize: 13; width: secContent.width - 250; elide: Text.ElideRight }
                                    }
                                    Text { visible: modelData.detail !== ""; x: 106; width: secContent.width - 120; text: modelData.detail; color: root.dimColor; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                            }
                        }

                        Column {
                            visible: root.shownSecSug.length > 0
                            width: parent.width
                            spacing: 6
                            Text { text: "Suggestions (ways to make the system harder to attack): " + root.shownSecSug.length; color: root.warnColor; font.pixelSize: 14; font.bold: true }
                            Repeater {
                                model: root.shownSecSug
                                delegate: Column {
                                    required property var modelData
                                    width: secContent.width
                                    Row {
                                        spacing: 10
                                        Text { text: modelData.id; color: root.warnColor; font.pixelSize: 12; font.bold: true; width: 96 }
                                        Text { text: modelData.area; color: root.dimColor; font.pixelSize: 12; width: 130; elide: Text.ElideRight }
                                        Text { text: modelData.text; color: root.textColor; font.pixelSize: 13; width: secContent.width - 250; elide: Text.ElideRight }
                                    }
                                    Text { visible: modelData.detail !== ""; x: 106; width: secContent.width - 120; text: modelData.detail; color: root.dimColor; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                            }
                        }

                        Text {
                            visible: root.secDone && root.secFail === "" && root.secWarn.length + root.secSug.length === 0
                            text: "Lynis found nothing to report."
                            color: root.okColor
                            font.pixelSize: 13
                        }
                        Text {
                            visible: root.secDone
                            width: parent.width
                            text: "Lynis " + root.secVersion + " (open source, GPL-3.0, from Fedora) ran on this computer only. Mode: " +
                                  (root.secMode === "full" ? "with admin rights, all tests." : "without admin rights, a few tests are skipped; Shift+L runs all of them.") +
                                  " Nothing was changed."
                            color: root.dimColor
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
