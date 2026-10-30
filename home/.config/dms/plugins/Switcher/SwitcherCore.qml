import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Sway only: window list from `swaymsg -t get_tree`, previews from `grim -T <foreign toplevel id>`.
Scope {
    id: root

    property real cornerRadius: 1
    property color scrim: "#c0101014"
    property color cardColor: "#2b2b32"
    property color cardSelected: "#3d4c73"
    property color accent: "#89b4fa"
    property color textColor: "#e8e8ee"
    property color dimColor: "#a0a0ac"

    property string kind: "windows"
    property bool shown: false
    property var items: []
    property var groups: []
    property int sel: 0
    property var mru: []
    property int stamp: 0
    property string outputName: ""
    property bool keysShown: false
    property var keyRows: []
    property string keyFilter: ""
    property int keySel: 0
    readonly property var filteredRows: {
        const words = keyFilter.toLowerCase().split(/\s+/).filter(w => w.length);
        if (!words.length) return keyRows;
        return keyRows.filter(r => {
            const t = (r.key + " " + r.label + " " + r.cmd).toLowerCase();
            return words.every(w => t.indexOf(w) >= 0);
        });
    }
    readonly property string cacheDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sway-switcher"

    function sh(args) { Quickshell.execDetached(args); }

    function walk(node, ws, out, wsList) {
        const kids = (node.nodes || []).concat(node.floating_nodes || []);
        for (const c of kids) {
            let w = ws;
            if (c.type === "workspace") {
                if (c.name === "__i3_scratch") continue;
                w = { name: c.name, items: [], focused: false };
                wsList.push(w);
            }
            if (c.pid && c.foreign_toplevel_identifier && w) {
                const it = { id: c.id, ident: c.foreign_toplevel_identifier,
                             appId: c.app_id || (c.window_properties ? c.window_properties.class : "") || "",
                             title: c.name || "", ws: w.name, focused: !!c.focused };
                w.items.push(it);
                out.push(it);
                if (c.focused) w.focused = true;
            }
            root.walk(c, w, out, wsList);
        }
    }

    function mruRank(id) { const i = mru.indexOf(id); return i < 0 ? 1e6 : i; }

    function build(treeJson, wanted) {
        const tree = JSON.parse(treeJson);
        const flat = [], wsList = [];
        walk(tree, null, flat, wsList);
        let focusedWs = wsList.find(w => w.focused);
        for (const o of (tree.nodes || [])) {
            if (o.type === "output" && JSON.stringify(o).indexOf('"focused":true') >= 0) { outputName = o.name; break; }
        }
        if (!focusedWs) focusedWs = wsList[0];
        if (wanted === "windows") {
            const list = (focusedWs ? focusedWs.items : []).slice().sort((a, b) => mruRank(a.id) - mruRank(b.id));
            items = list;
            groups = [{ name: focusedWs ? focusedWs.name : "", items: list }];
            sel = list.length > 1 ? 1 : 0;
        } else {
            const gs = wsList.filter(w => w.items.length > 0).sort((a, b) => parseInt(a.name) - parseInt(b.name));
            const list = [];
            for (const g of gs) for (const it of g.items) list.push(it);
            items = list;
            groups = gs;
            const f = list.findIndex(i => i.focused);
            sel = f < 0 ? 0 : f;
        }
    }

    // ---- shortcut list: every bindsym of the Fedora spin, DMS and your own config, merged by `sway-keys --write` ----
    readonly property var keyLabels: [
        [/^exec dms ipc call spotlight toggle$/, "App launcher"],
        [/^exec dms ipc call spotlight-bar toggle$/, "Quick search bar"],
        [/^exec dms ipc call clipboard toggle$/, "Clipboard history"],
        [/^exec dms ipc call powermenu toggle$/, "Power menu"],
        [/^exec dms ipc call lock lock$/, "Lock screen"],
        [/^exec dms ipc call night toggle$/, "Night light"],
        [/^exec dms ipc call dash toggle wallpaper$/, "Wallpapers"],
        [/^exec dms ipc call dash toggle media$/, "Media panel"],
        [/^exec dms ipc call notepad toggle$/, "Notepad"],
        [/^exec dms ipc call notepad toggleExpand$/, "Notepad (large)"],
        [/^exec dms ipc call notifications toggle$/, "Notification centre"],
        [/^exec dms ipc call settings focusOrToggle$/, "DMS settings"],
        [/^exec dms ipc call inhibit toggle$/, "Idle inhibit"],
        [/^exec dms ipc call processlist focusOrToggle$/, "Task manager"],
        [/^exec dms ipc call color-picker toggle$/, "Colour picker"],
        [/^exec dms ipc call openHere toggle$/, "Open Here"],
        [/^exec dms ipc outputs cycleProfile$/, "Display profile"],
        [/^exec dms ipc call audio increment/, "Volume up"],
        [/^exec dms ipc call audio decrement/, "Volume down"],
        [/^exec dms ipc call audio micmute/, "Mic mute"],
        [/^exec dms ipc call audio mute/, "Mute"],
        [/^exec dms ipc call brightness increment/, "Brightness up"],
        [/^exec dms ipc call brightness decrement/, "Brightness down"],
        [/^exec dms ipc call mpris playPause/, "Play / pause"],
        [/^exec dms ipc call mpris next/, "Next track"],
        [/^exec dms ipc call mpris previous/, "Previous track"],
        [/^exec ptyxis/, "Terminal"],
        [/screenshot-notify full$/, "Screenshot: screen (Edit button)"],
        [/screenshot-notify$/, "Screenshot: area (Edit button)"],
        [/^exec grimshot .*area/, "Screenshot: area"],
        [/^exec grimshot save output/, "Screenshot: screen"],
        [/^exec grimshot save active/, "Screenshot: window"],
        [/^exec gnome-calculator/, "Calculator"],
        [/^exec dms ipc call switcher open windows/, "Switch windows"],
        [/^exec dms ipc call switcher open overview/, "All workspaces"],
        [/^exec dms ipc call switcher open keys/, "This shortcut list"],
        [/^exec dms ipc call doctor toggle/, "System doctor"],
        [/^kill$/, "Close window"],
        [/^reload$/, "Reload Sway config"],
        [/^fullscreen/, "Fullscreen"],
        [/^floating toggle$/, "Float / tile"],
        [/^focus mode_toggle$/, "Focus tiled / floating"],
        [/^focus parent$/, "Focus parent"],
        [/^focus (left|right|up|down)$/, "Focus $1"],
        [/^move (left|right|up|down)$/, "Move window $1"],
        [/^workspace number (\d+)$/, "Go to workspace $1"],
        [/^move container to workspace number (\d+)$/, "Send window to workspace $1"],
        [/^workspace next$/, "Next workspace"],
        [/^workspace prev$/, "Previous workspace"],
        [/^splith$/, "Split side by side"],
        [/^splitv$/, "Split top / bottom"],
        [/^layout stacking$/, "Layout: stacking"],
        [/^layout tabbed$/, "Layout: tabbed"],
        [/^layout toggle split$/, "Layout: toggle split"],
        [/^move scratchpad$/, "Send to scratchpad"],
        [/^scratchpad show$/, "Show scratchpad"],
        [/^mode "resize"$/, "Resize mode"],
        [/^mode "passthrough"$/, "Passthrough mode"],
        [/swaynag .*exit sway/, "Exit Sway"]
    ]

    function prettyKey(k, vars) {
        let s = k;
        for (const n in vars) s = s.split(n).join(vars[n]);
        return s.replace(/Mod4/g, "Super").replace(/Mod1/g, "Alt").replace(/Control/g, "Ctrl").replace(/\+/g, " + ");
    }

    function labelFor(cmd) {
        const first = cmd.split(";")[0].trim();
        for (const [re, lab] of keyLabels) {
            const m = re.exec(first);
            if (m) return lab.replace(/\$(\d)/g, (_, i) => m[+i] || "");
        }
        return first.replace(/^exec\s+/, "");
    }

    function parseKeys(text) {
        const vars = {}, rows = [];
        for (const ln of text.split("\n")) {
            const s = ln.trim();
            let m = /^set\s+(\$\S+)\s+(.+)$/.exec(s);
            if (m) { vars[m[1]] = m[2]; continue; }
            m = /^bindsym\s+((?:--\S+\s+)*)(\S+)\s+(.+)$/.exec(s);
            if (m) {
                let cmd = m[3];
                for (const n in vars) cmd = cmd.split(n).join(vars[n]);
                rows.push({ key: prettyKey(m[2], vars), label: labelFor(cmd), cmd: cmd });
            }
        }
        keyRows = rows;
    }

    function openKeys() {
        kind = "keys";
        keyFilter = "";
        keySel = 0;
        keysProc.running = true;
    }

    // Click (or Enter) on a shortcut: close the list, then run the same Sway command the key would run.
    function runKey(row) {
        if (!row) return;
        close(false);
        Quickshell.execDetached(["sh", "-c", 'sleep 0.25; swaymsg "$1" >/dev/null 2>&1', "sh", row.cmd]);
    }

    function moveKey(delta) {
        const n = filteredRows.length;
        if (!n) return;
        keySel = Math.max(0, Math.min(n - 1, keySel + delta));
        const top = Math.floor(keySel / 2) * 30, f = keysFlick;
        if (top < f.contentY) f.contentY = top;
        else if (top + 30 > f.contentY + f.height) f.contentY = top + 30 - f.height;
    }

    function scrollKeys(dir) {
        const f = keysFlick;
        const step = 260 * (dir === "up" ? -1 : 1);
        f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + step));
    }

    function open(wanted) {
        if (wanted === "keys") { openKeys(); return; }
        kind = wanted === "overview" ? "overview" : "windows";
        treeProc.want = kind;
        treeProc.command = ["swaymsg", "-t", "get_tree", "-r"];
        treeProc.running = true;
    }

    // Two alternating file names per window, so a new capture never reuses the previous image URL.
    // `stamp` is only published to the cards (shownStamp) once grim has finished writing the files.
    property int shownStamp: -1
    function capture() {
        shownStamp = -1;
        stamp = (stamp + 1) % 2;
        capProc.command = ["sh", "-c",
            'd="$1"; s="$2"; shift 2; mkdir -p "$d"; for id in "$@"; do grim -T "$id" "$d/$id-$s.png" 2>/dev/null & done; wait',
            "sh", cacheDir, String(stamp)].concat(items.map(i => i.ident));
        capProc.running = true;
    }

    function close(resetMode) {
        shown = false;
        keysShown = false;
        if (resetMode) sh(["swaymsg", "mode", "default"]);
    }

    function next() { if (items.length) sel = (sel + 1) % items.length; }
    function prev() { if (items.length) sel = (sel - 1 + items.length) % items.length; }
    function jumpGroup(delta) {
        if (!items.length || groups.length < 2) return;
        const g = groups.findIndex(x => x.name === items[sel].ws);
        const t = (g + delta + groups.length) % groups.length;
        sel = items.indexOf(groups[t].items[0]);
    }
    // A quick Alt+Tab tap releases Alt before the list and previews are ready: remember it and switch as soon as they are.
    property bool pendingCommit: false
    function commit() {
        if (!shown && (treeProc.running || capProc.running)) { pendingCommit = true; return; }
        const it = items[sel];
        close(false);
        if (it) sh(["swaymsg", "[con_id=" + it.id + "] focus"]);
        sh(["swaymsg", "mode", "default"]);
    }

    Process {
        id: treeProc
        property string want: "windows"
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.build(text, treeProc.want); } catch (e) { console.warn("switcher: " + e); root.close(true); return; }
                if (root.items.length === 0) { root.pendingCommit = false; root.close(true); return; }
                if (root.pendingCommit) { root.pendingCommit = false; root.commit(); return; }
                root.capture();
            }
        }
    }

    Process {
        id: keysProc
        command: ["sh", "-c", '"$HOME/.local/bin/sway-keys" --write >/dev/null && cat "${XDG_RUNTIME_DIR:-/tmp}/sway-keys.conf"']
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseKeys(text);
                root.keysShown = root.keyRows.length > 0;
                if (!root.keysShown) root.close(true);
            }
        }
    }

    Process {
        id: capProc
        onRunningChanged: if (!running && root.items.length > 0) {
            if (root.pendingCommit) { root.pendingCommit = false; root.commit(); return; }
            root.shownStamp = root.stamp;
            root.shown = true;
        }
    }

    // most recently used order, for Alt+Tab
    Process {
        running: true
        command: ["swaymsg", "-t", "subscribe", "-m", '["window"]']
        stdout: SplitParser {
            onRead: line => {
                try {
                    const ev = JSON.parse(line);
                    if (ev.change === "focus" && ev.container) {
                        const id = ev.container.id;
                        root.mru = [id].concat(root.mru.filter(x => x !== id)).slice(0, 200);
                    } else if (ev.change === "close" && ev.container) {
                        root.mru = root.mru.filter(x => x !== ev.container.id);
                    }
                } catch (e) {}
            }
        }
    }

    IpcHandler {
        target: "switcher"
        function open(kind: string): string { root.open(kind); return "ok"; }
        function next(): string { root.next(); return "ok"; }
        function prev(): string { root.prev(); return "ok"; }
        function up(): string { root.jumpGroup(-1); return "ok"; }
        function down(): string { root.jumpGroup(1); return "ok"; }
        function commit(): string { root.commit(); return "ok"; }
        function cancel(): string { root.close(true); return "ok"; }
        function scroll(dir: string): string { root.scrollKeys(dir); return "ok"; }
        function keysFilter(text: string): string { root.keyFilter = text; root.keySel = 0; return "ok"; }
        function keysRun(): string { root.runKey(root.filteredRows[root.keySel]); return "ok"; }
    }

    PanelWindow {
        id: keysWin
        visible: root.keysShown
        screen: Quickshell.screens.find(s => s.name === root.outputName) || Quickshell.screens[0]
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.keysShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "switcher-keys"

        onVisibleChanged: if (visible) { search.text = ""; search.forceActiveFocus(); }

        Rectangle {
            anchors.fill: parent
            color: root.scrim
            MouseArea { anchors.fill: parent; onClicked: root.close(false) }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1100)
                height: parent.height - 120
                radius: root.cornerRadius
                color: root.cardColor
                border.width: 1
                border.color: root.accent

                Row {
                    id: head
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
                    spacing: 16
                    height: 34

                    Rectangle {
                        width: 340
                        height: 34
                        radius: root.cornerRadius
                        color: root.scrim
                        border.width: 1
                        border.color: root.accent
                        TextInput {
                            id: search
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.textColor
                            font.pixelSize: 15
                            clip: true
                            focus: true
                            onTextChanged: { root.keyFilter = text; root.keySel = 0; keysFlick.contentY = 0; }
                            Keys.onEscapePressed: root.close(false)
                            Keys.onDownPressed: root.moveKey(1)
                            Keys.onUpPressed: root.moveKey(-1)
                            Keys.onReturnPressed: root.runKey(root.filteredRows[root.keySel])
                            Keys.onEnterPressed: root.runKey(root.filteredRows[root.keySel])
                            Text {
                                visible: search.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Type to search shortcuts..."
                                color: root.dimColor
                                font.pixelSize: 15
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filteredRows.length + " of " + root.keyRows.length + "     Up / Down + Enter or click runs it     Esc closes"
                        color: root.dimColor
                        font.pixelSize: 13
                    }
                }

                Flickable {
                    id: keysFlick
                    anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 14; margins: 18 }
                    contentWidth: width
                    contentHeight: grid.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Flow {
                        id: grid
                        width: keysFlick.width
                        spacing: 0
                        Repeater {
                            model: root.filteredRows
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.keySel
                                width: grid.width / 2
                                height: 30
                                radius: root.cornerRadius
                                color: selected ? root.cardSelected : "transparent"

                                Rectangle {
                                    id: chip
                                    anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                    width: Math.min(parent.width * 0.5, keyText.implicitWidth + 16)
                                    height: 24
                                    radius: root.cornerRadius
                                    color: root.cardSelected
                                    border.width: selected ? 1 : 0
                                    border.color: root.accent
                                    Text {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: modelData.key
                                        color: root.textColor
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, chip.parent.width * 0.5 - 16)
                                    }
                                }
                                Text {
                                    anchors { left: chip.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: modelData.label
                                    color: selected ? root.textColor : root.dimColor
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.keySel = index
                                    onClicked: root.runKey(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
