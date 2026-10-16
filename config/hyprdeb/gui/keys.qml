// hyprdeb managed: install.sh overwrites this file (installed to ~/.local/share/hyprdeb/gui/keys.qml).
// The shortcuts list is read-only: it shows `hyprdeb keys --json` (the live binds of Hyprland, grouped) and changes nothing.
// Search filters as you type (key or text); Esc closes. Started by `hyprdeb gui --page shortcuts` (SUPER + /).
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: win
    title: "hyprdeb shortcuts"
    visible: true
    implicitWidth: 620
    implicitHeight: 720
    color: "#1c2232"

    readonly property string bin: Quickshell.env("HYPRDEB_BIN") || "hyprdeb"
    property var data_: null          // not "data": FloatingWindow already has a default property of that name
    property string error: ""
    property string query: ""
    readonly property color fg: "#e6e9f0"
    readonly property color dim: "#9aa3b8"
    readonly property color panel: "#2b3350"

    // The query as the Latin keys at the same physical positions (`layout_map` from hyprdeb keys --json, derived from the xkb data):
    // Persian letters typed by mistake still find the Latin text. The keyboard layout itself is never switched.
    readonly property string queryMapped: {
        var m = data_ && data_.layout_map ? data_.layout_map : {}
        var out = ""
        for (var i = 0; i < query.length; i++) out += (m[query[i]] !== undefined ? m[query[i]] : query[i])
        return out.toLowerCase()
    }

    // The groups with only the binds that match the search (all of them while it is empty). A bind is searched by its group name,
    // key text ("SUPER + SHIFT + V") and description; the raw query and the layout-mapped query are both tried.
    readonly property var shown: {
        if (!data_) return []
        var raw = query.trim().toLowerCase()
        var mapped = queryMapped.trim()
        var out = []
        for (var i = 0; i < data_.groups.length; i++) {
            var g = data_.groups[i]
            var items = g.binds.filter(function (b) {
                if (raw === "") return true
                var hay = (g.name + " " + b.keys + " " + b.text).toLowerCase()
                return hay.indexOf(raw) >= 0 || hay.indexOf(mapped) >= 0
            })
            if (items.length > 0) out.push({ name: g.name, icon: g.icon, binds: items })
        }
        return out
    }
    readonly property int shownCount: { var n = 0; for (var i = 0; i < shown.length; i++) n += shown[i].binds.length; return n }

    Process {
        id: loader
        command: [win.bin, "keys", "--json"]
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: (code, status) => {
            try {
                var j = JSON.parse(out.text)
                if (j.ok) win.data_ = j
                else win.error = j.error || "hyprdeb keys failed"
            } catch (e) {
                win.error = (err.text || out.text || "hyprdeb keys failed").replace("hyprdeb: error: ", "").trim()
            }
        }
    }

    // Same reason as the settings window: no hot reload (it crashes Quickshell on close, see docs/gotchas.md, Quickshell).
    Component.onCompleted: { Quickshell.watchFiles = false; loader.running = true; search.forceActiveFocus() }
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                visible: win.data_ !== null && win.data_.search_icon !== ""
                text: win.data_ ? win.data_.search_icon : ""
                font.family: "tabler-icons"; font.pixelSize: 19; color: win.dim
            }
            TextField {
                id: search
                Layout.fillWidth: true
                placeholderText: "Search shortcuts (key or text)"
                color: win.fg
                placeholderTextColor: win.dim
                font.pixelSize: 15
                selectByMouse: true
                background: Rectangle { color: win.panel; radius: 6 }
                onTextChanged: win.query = text
            }
        }

        Text {
            visible: win.error !== ""
            text: win.error
            color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
        }
        Text {
            visible: win.error === "" && win.data_ !== null && win.shownCount === 0
            text: "No shortcut matches “" + win.query + "”."
            color: win.dim; font.pixelSize: 14
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: col
                width: parent.width - 12
                spacing: 4

                Repeater {
                    model: win.shown
                    delegate: ColumnLayout {
                        id: grp
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.topMargin: 10
                            spacing: 8
                            Text {
                                visible: grp.modelData.icon !== ""
                                text: grp.modelData.icon; font.family: "tabler-icons"; font.pixelSize: 19; color: win.dim
                            }
                            Text { text: grp.modelData.name; color: win.fg; font.pixelSize: 17; font.bold: true }
                        }

                        Repeater {
                            model: grp.modelData.binds
                            delegate: RowLayout {
                                id: row
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 12
                                Rectangle {
                                    Layout.preferredWidth: 250
                                    Layout.preferredHeight: 26
                                    color: win.panel; radius: 5
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left; anchors.leftMargin: 8
                                        anchors.right: parent.right; anchors.rightMargin: 8
                                        text: row.modelData.keys
                                        color: win.fg; font.pixelSize: 13; font.family: "monospace"; elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.text
                                    color: row.modelData.source === "none" ? win.dim : win.fg
                                    font.pixelSize: 14; wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: win.data_ !== null
            text: win.data_ ? (win.query.trim() === "" ? win.data_.count + " shortcuts" : win.shownCount + " of " + win.data_.count + " shortcuts") + " · read-only · Esc closes" : ""
            color: win.dim; font.pixelSize: 12
        }
    }
}
