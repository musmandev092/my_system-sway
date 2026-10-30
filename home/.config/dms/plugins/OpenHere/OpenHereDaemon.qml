import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string folder: ""
    property int selectedIndex: 0

    property bool pointerMoved: false
    property point pointerStart: Qt.point(-1, -1)
    readonly property string cwdScript: Quickshell.env("HOME") + "/.local/bin/open-here-cwd"

    function inToolbox(prog) {
        return "'" + Quickshell.env("HOME") + "/.local/bin/open-here-toolbox' dev " + prog;
    }

    readonly property var entries: [
        { label: "Claude Code", hint: "claude", icon: "smart_toy", cmd: d => ["ptyxis", "-s", "-d", d, "-x", "claude"] },
        { label: "Antigravity", hint: "agy", icon: "rocket_launch", cmd: d => ["ptyxis", "-s", "-d", d, "-x", "agy"] },
        { label: "VS Code", hint: "code", icon: "code", cmd: d => ["code", d] },
        { label: "Files", hint: "nautilus", icon: "folder_open", cmd: d => ["nautilus", "--new-window", d] },
        { label: "Terminal", hint: "ptyxis", icon: "terminal", cmd: d => ["ptyxis", "-s", "--new-window", "-d", d] },
        { label: "Neovim", hint: "toolbox dev: nvim", icon: "edit_note", cmd: d => ["ptyxis", "-s", "-d", d, "-x", root.inToolbox("nvim")] },
        { label: "Lazygit", hint: "toolbox dev: lazygit", icon: "account_tree", cmd: d => ["ptyxis", "-s", "-d", d, "-x", root.inToolbox("lazygit")] },
        { label: "Copy path", hint: "wl-copy", icon: "content_copy", cmd: d => ["wl-copy", "--", d] }
    ]

    function prettyPath(p) {
        const home = Quickshell.env("HOME");
        if (p === home)
            return "~";
        return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p;
    }

    function openFor(dir) {
        folder = dir || Quickshell.env("HOME");
        selectedIndex = 0;
        pointerMoved = false;
        pointerStart = Qt.point(-1, -1);
        modal.open();
    }

    property bool opening: false

    function openFromFocus() {
        opening = true;
        Proc.runCommand("openHere.cwd", [cwdScript], (out, code) => {
            if (!root.opening)
                return;
            root.opening = false;
            const dir = (out || "").trim();
            root.openFor(code === 0 && dir.startsWith("/") ? dir : "");
        }, 0);
    }

    function run(index) {
        const e = entries[index];
        if (!e || !folder)
            return;
        modal.close();
        Quickshell.execDetached({
            command: e.cmd(folder),
            workingDirectory: folder
        });
        if (e.label === "Copy path")
            ToastService.showInfo(I18n.tr("Path copied"), prettyPath(folder));
    }

    IpcHandler {
        target: "openHere"

        function toggle(): string {
            if (modal.shouldBeVisible || root.opening) {
                root.opening = false;
                modal.close();
                return "closed";
            }
            root.openFromFocus();
            return "opening";
        }

        function open(dir: string): string {
            root.openFor(dir);
            return "opened " + root.folder;
        }

        function run(entry: string): string {
            let i = parseInt(entry) - 1;
            if (isNaN(i))
                i = root.entries.findIndex(e => e.label.toLowerCase() === entry.toLowerCase());
            if (i < 0 || i >= root.entries.length)
                return "unknown entry: " + entry;
            if (modal.shouldBeVisible) {
                root.run(i);
                return root.entries[i].label + " in " + root.folder;
            }
            Proc.runCommand("openHere.cwd", [root.cwdScript], (out, code) => {
                const dir = (out || "").trim();
                root.folder = code === 0 && dir.startsWith("/") ? dir : Quickshell.env("HOME");
                root.run(i);
            }, 0);
            return root.entries[i].label;
        }

        function close(): string {
            root.opening = false;
            modal.close();
            return "closed";
        }

        function status(): string {
            return (modal.shouldBeVisible ? "open " : "closed ") + root.folder;
        }
    }

    DModal {
        id: modal

        layerNamespace: "dms:open-here"
        keepPopoutsOpen: true
        shouldBeVisible: false
        modalWidth: 420
        modalHeight: contentLoader?.item?.implicitHeight ?? 560
        enableShadow: true
        onBackgroundClicked: close()

        onShouldHaveFocusChanged: {
            if (shouldHaveFocus)
                Qt.callLater(() => modalFocusScope.forceActiveFocus());
        }

        modalFocusScope.Keys.onPressed: event => {
            const n = root.entries.length;
            if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + n) {
                root.run(event.key - Qt.Key_1);
                event.accepted = true;
                return;
            }
            switch (event.key) {
            case Qt.Key_Up:
            case Qt.Key_Backtab:
            case Qt.Key_K:
                root.selectedIndex = (root.selectedIndex - 1 + n) % n;
                break;
            case Qt.Key_Down:
            case Qt.Key_Tab:
            case Qt.Key_J:
                root.selectedIndex = (root.selectedIndex + 1) % n;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                root.run(root.selectedIndex);
                break;
            case Qt.Key_Escape:
                modal.close();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        content: Component {
            Item {
                anchors.fill: parent
                implicitHeight: column.implicitHeight + Theme.spacingL * 2

                Column {
                    id: column
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        DIcon {
                            name: "folder"
                            size: Theme.iconSize + 4
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Theme.iconSize - 4 - Theme.spacingM
                            spacing: 2

                            StyledText {
                                text: I18n.tr("Open Here")
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                text: root.prettyPath(root.folder)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                                width: parent.width
                                elide: Text.ElideMiddle
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        Repeater {
                            model: root.entries

                            Rectangle {
                                id: row
                                required property int index
                                required property var modelData
                                readonly property bool isSelected: root.selectedIndex === index

                                width: parent.width
                                height: 48
                                radius: Theme.cornerRadius
                                color: isSelected ? Theme.primaryHoverLight : (mouse.containsMouse && root.pointerMoved ?Theme.foregroundColor(Theme.chipSurface, true) : "transparent")
                                border.color: isSelected ? Theme.focusRingColor : "transparent"
                                border.width: isSelected ? Theme.outlineWidthFocused : 0

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingM

                                    DIcon {
                                        name: row.modelData.icon
                                        size: Theme.iconSize
                                        color: row.isSelected ? Theme.primary : Theme.surfaceText
                                        filled: row.isSelected
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: row.modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 130
                                    }

                                    StyledText {
                                        text: row.modelData.hint
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceTextMedium
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Theme.iconSize - 130 - 20 - Theme.spacingM * 3
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        width: 20
                                        height: 20
                                        radius: Theme.cornerRadiusXS
                                        color: Theme.chipSurface
                                        anchors.verticalCenter: parent.verticalCenter

                                        StyledText {
                                            text: (row.index + 1).toString()
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Theme.fontWeightMedium
                                            color: Theme.surfaceTextMedium
                                            anchors.centerIn: parent
                                        }
                                    }
                                }

                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: m => {
                                        const p = mapToItem(null, m.x, m.y);
                                        if (!root.pointerMoved) {
                                            if (root.pointerStart.x < 0) {
                                                root.pointerStart = p;
                                                return;
                                            }
                                            if (Math.abs(p.x - root.pointerStart.x) + Math.abs(p.y - root.pointerStart.y) < 4)
                                                return;
                                            root.pointerMoved = true;
                                        }
                                        root.selectedIndex = row.index;
                                    }
                                    onClicked: root.run(row.index)
                                }
                            }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingXS
                        opacity: 0.5

                        DIcon {
                            name: "keyboard"
                            size: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: I18n.tr("1-8 or arrows, Enter to open, Esc to close")
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceText
                        }
                    }
                }
            }
        }
    }
}
