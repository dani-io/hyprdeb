// hyprdeb managed: install.sh overwrites this file (installed to ~/.local/share/hyprdeb/gui/shell.qml).
// The settings window is a thin layer: it reads `hyprdeb show --json` and runs `hyprdeb set KEY VALUE`. All validation,
// defaults and file writing live in bin/hyprdeb; the status line shows hyprdeb's own error text. Started by `hyprdeb gui`.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: win
    title: "hyprdeb settings"
    visible: true
    implicitWidth: 760
    implicitHeight: 720
    color: "#1c2232"

    readonly property string bin: Quickshell.env("HYPRDEB_BIN") || "hyprdeb"
    // not "data": FloatingWindow already has a default property of that name (it adopts the child items)
    property var cfg: null
    property string status: ""
    property bool statusError: false
    property bool busy: false
    readonly property color fg: "#e6e9f0"
    readonly property color dim: "#9aa3b8"
    readonly property color panel: "#2b3350"

    function icon(section) { return cfg && cfg.ok && cfg.icons ? (cfg.icons[section] || "") : "" }
    function limit(key, field) { return cfg && cfg.ok && cfg.limits ? cfg.limits[key][field] : 0 }
    function reload() { if (!loader.running) loader.running = true }
    // NAS: `hyprdeb nas status --json` (fast, never mounts) when the window opens and after each action; the window holds no NAS logic.
    // Connect / Open / Disconnect call `hyprdeb nas mount|open|unmount NAME`. Add / Edit / Test / Remove call `hyprdeb nas add|edit|test|remove
    // NAME --json ...`: the password goes to hyprdeb on stdin only (one line), the field is emptied after every Save / Test and when the form
    // closes; the CLI hands it to the root helper, polkit shows the administrator password dialog there, and the answer (or the helper's own
    // error text) is shown inline in the form.
    property var nas: null
    property bool nasBusy: false
    property string nasFormMode: ""            // "" (closed), "add" or "edit"
    property string nasFormName: ""
    property string nasFServer: ""
    property string nasFShare: ""
    property string nasFUser: ""
    property string nasFIdle: "10m"
    property string nasFormMsg: ""
    property bool nasFormErr: false
    property string nasConfirmRemove: ""       // name of the share waiting for "Remove NAS NAME?" to be answered
    property string nasPending: ""             // the password for the process that is about to start (memory only, emptied at once)
    function nasShares() { return nas && nas.ok && nas.shares ? nas.shares : [] }
    function refreshNas() { if (!nasLoader.running) nasLoader.running = true }
    function nasAction(verb, name) {
        if (nasBusy || busy) return
        nasBusy = true
        setStatus(verb === "unmount" ? "Disconnecting (a password dialog may appear)..." : verb === "mount" ? "Connecting..." : "Opening...", false)
        nasAct.verb = verb
        nasAct.command = [bin, "nas", verb, name]
        nasAct.running = true
    }
    function nasClearPassword() { nasPass.text = ""; nasPending = "" }
    function nasCloseForm() { nasFormMode = ""; nasFormMsg = ""; nasFormErr = false; nasClearPassword() }
    function nasOpenAdd() {
        nasConfirmRemove = ""; nasClearPassword()
        nasFormMode = "add"; nasFormName = ""; nasFServer = ""; nasFShare = ""; nasFUser = ""; nasFIdle = "10m"; nasFormMsg = ""; nasFormErr = false
    }
    function nasOpenEdit(s) {
        nasConfirmRemove = ""; nasClearPassword()
        nasFormMode = "edit"; nasFormName = s.name; nasFServer = s.server; nasFShare = s.share; nasFUser = s.username || ""
        nasFIdle = s.idle_unmount; nasFormMsg = ""; nasFormErr = false
    }
    function nasNameOk(n) { return /^[a-z0-9][a-z0-9-]{0,14}$/.test(n) }
    // verb: "add" | "edit" | "test"; the form fields are the arguments, the password field is the only secret
    function nasSubmit(verb) {
        if (nasBusy || busy) return
        var adding = nasFormMode === "add"
        if (adding && !nasNameOk(nasFormName)) { nasFormMsg = "Name: 1 to 15 characters from a-z, 0-9 and '-' (it is also the folder /mnt/NAME)."; nasFormErr = true; return }
        if (nasFServer.trim() === "" || nasFShare.trim() === "" || nasFUser.trim() === "") { nasFormMsg = "Server, share and user name are needed."; nasFormErr = true; return }
        if (adding && nasPass.text === "") { nasFormMsg = "Type the password for the new NAS."; nasFormErr = true; return }
        var cmd = [bin, "nas", verb]
        if (verb !== "test" || !adding) cmd.push(nasFormName)
        cmd.push("--server", nasFServer.trim(), "--share", nasFShare.trim(), "--username", nasFUser.trim())
        if (verb !== "test") cmd.push("--idle", nasFIdle.trim() === "" ? "10m" : nasFIdle.trim())
        cmd.push("--json")
        nasRun(verb, cmd, nasPass.text,
               verb === "test" ? "Testing (a password dialog may appear)..." : "Saving (a password dialog may appear)...")
    }
    function nasRemove(name) {
        if (nasBusy || busy) return
        nasRun("remove", [bin, "nas", "remove", name, "--yes", "--json"], "", "Removing (a password dialog may appear)...")
    }
    function nasRun(verb, cmd, password, text) {
        nasBusy = true
        nasFormMsg = ""; nasFormErr = false
        setStatus(text, false)
        nasPending = password + "\n"
        nasMgmt.verb = verb
        nasMgmt.stdinEnabled = verb !== "remove"
        nasMgmt.command = cmd
        nasMgmt.running = true
        nasGuard.restart()
    }
    // VPN: `hyprdeb vpn status --json` when the window opens and after each action. On / Off only call `hyprdeb vpn on|off` (on runs with
    // --keep: a tunnel with no traffic stays on and shows "Turn off" here, instead of switching itself off under the user).
    property var vpn: null
    property bool vpnBusy: false
    function refreshVpn() { if (!vpnLoader.running) vpnLoader.running = true }
    function vpnOk() { return vpn && !vpn.error }
    function vpnAction(verb, name) {
        if (vpnBusy || busy) return
        vpnBusy = true
        setStatus(verb === "on" ? "Turning the VPN on (up to 10 s)..." : "Turning the VPN off...", false)
        vpnAct.verb = verb
        vpnAct.command = verb === "on" ? [bin, "vpn", "on", name, "--keep"] : [bin, "vpn", "off", name]
        vpnAct.running = true
    }
    // Printers: `hyprdeb print status --json` (read-only checks), then `print jobs --json` when CUPS answers; Cancel runs `print cancel ID`,
    // the test page runs `print testpage --yes` after a confirmation (one sheet of paper). A 15 s guard ends a check that hangs.
    property var prn: null
    property var prnJobs: null
    property bool prnBusy: false
    property bool prnConfirmTest: false
    function refreshPrn() {
        if (prnBusy) return
        prnBusy = true
        prnGuard.restart()
        prnStatus.running = true
    }
    function prnState(label) {
        if (!prn || !prn.checks) return ""
        for (var i = 0; i < prn.checks.length; i++) if (prn.checks[i].label === label) return prn.checks[i].state
        return ""
    }
    function prnConfigured() { return prn && prn.checks && prnState("settings") === "ok" }
    function prnReady() { return prnConfigured() && prnState("CUPS") === "ok" && prnState("queue") === "ok" }
    function prnColor(state) { return state === "ok" ? "#9fd3a8" : state === "fail" ? "#ff6b6b" : state === "info" ? "#ffcf6b" : win.dim }
    function prnAge(s) { return s < 90 ? s + " s" : s < 5400 ? Math.round(s / 60) + " min" : s < 129600 ? Math.round(s / 3600) + " h" : Math.round(s / 86400) + " d" }
    function prnRun(cmd, text) {
        if (prnBusy) return
        prnBusy = true
        setStatus(text, false)
        prnGuard.restart()
        prnAct.command = cmd
        prnAct.running = true
    }
    // The selected profile is [vpn] default (set with `hyprdeb set vpn.default NAME`), so the quick menu and `hyprdeb vpn on` use the same one.
    // While a tunnel is on the selection is that tunnel (and cannot be changed). With several profiles and no default nothing is selected.
    function vpnSelected() {
        if (!vpnOk() || vpn.profiles.length === 0) return ""
        if (vpn.active) return vpn.active.name
        if (vpn.default && vpnExists(vpn.default)) return vpn.default
        return vpn.profiles.length === 1 ? vpn.profiles[0].name : ""
    }
    function vpnSelectedActive() { return vpnOk() && vpn.active !== null }
    property bool vpnConfirmDelete: false
    property bool vpnRenaming: false
    property string vpnRenameTo: ""
    property bool vpnReplaceMode: false
    function vpnRun(verb, cmd, text) {
        if (vpnBusy || busy) return
        vpnBusy = true
        setStatus(text, false)
        vpnAct.verb = verb
        vpnAct.command = cmd
        vpnAct.running = true
    }
    // VPN import: the pasted text reaches `hyprdeb vpn import - --name NAME` on stdin only (never on a command line, never in a
    // property that outlives the call, never logged); the paste box is emptied as soon as the text has been written, and when the window closes.
    property bool vpnAddOpen: false
    property string vpnNewName: ""
    property string vpnFile: ""
    property bool vpnScrub: true
    property bool vpnConfirmReplace: false
    property string vpnPending: ""        // text held for the one write into the import process; emptied right after
    function vpnNameOk(n) { return /^[a-z0-9][a-z0-9-]{0,10}$/.test(n) }
    function vpnExists(n) {
        if (!vpnOk()) return false
        for (var i = 0; i < vpn.profiles.length; i++) if (vpn.profiles[i].name === n) return true
        return false
    }
    // The paste box shows PrivateKey / PresharedKey values masked: when a pasted text has such lines, the real text moves to vpnRaw (memory
    // only), the box shows the masked copy and becomes read-only until "Clear text". Import sends vpnText() unchanged.
    property string vpnRaw: ""
    property bool vpnMasked: false
    readonly property var vpnKeyLine: /^(\s*(?:PrivateKey|PresharedKey)\s*=\s*)\S+/mi
    function vpnText() { return vpnMasked ? vpnRaw : vpnPaste.text }
    function vpnMaskPaste() {
        if (vpnMasked || !vpnKeyLine.test(vpnPaste.text)) return
        vpnRaw = vpnPaste.text
        vpnMasked = true
        vpnPaste.text = vpnRaw.replace(/^(\s*(?:PrivateKey|PresharedKey)\s*=\s*)\S+/gmi, "$1\u2022\u2022\u2022\u2022\u2022")
    }
    function vpnClearPaste() { vpnMasked = false; vpnRaw = ""; vpnPaste.text = ""; vpnPending = "" }
    function vpnImport(replace) {
        if (vpnBusy || busy) return
        if (!vpnNameOk(vpnNewName)) { setStatus("Name: 1 to 11 characters from a-z, 0-9 and '-', not starting with '-'.", true); return }
        if (vpnFile === "" && vpnText().trim() === "") { setStatus("Paste the configuration text, or choose a file.", true); return }
        if (vpnExists(vpnNewName) && !replace) { vpnConfirmReplace = true; return }
        vpnConfirmReplace = false
        vpnBusy = true
        setStatus("Importing (a few seconds)...", false)
        var cmd = [bin, "vpn", "import", vpnFile !== "" ? vpnFile : "-", "--name", vpnNewName]
        if (replace) cmd.push("--replace")
        if (vpnFile === "") {
            if (vpnScrub) cmd.push("--scrub-clipboard")
            vpnPending = vpnText()
            vpnImportAct.stdinEnabled = true
        }
        vpnImportAct.command = cmd
        vpnImportAct.running = true
    }
    // Network: `hyprdeb net status --json` (read-only; the quick checks take about a second) when the window opens and on "Re-check".
    property var net: null
    property bool netBusy: false
    function refreshNet() { if (netLoader.running) return; netBusy = true; netLoader.running = true }
    // IPv4 editor: the fields start from the live profile (`net status --json` "profile") until the user touches them. Apply runs
    // `hyprdeb net apply --no-wait --json`; the change then waits for Keep / Revert now (net confirm / net revert). Without an answer the
    // root guard puts the old settings back by itself (also when this window is closed): the window holds no network logic.
    property string netMethod: "dhcp"
    property string netAddr: ""
    property string netGw: ""
    property string netDns: ""
    property bool netEditing: false
    property string netErr: ""
    property var netPending: null          // {deadline: epoch seconds} while a change waits for an answer
    property int netRemaining: 0
    // Field hints come from the live status (nothing is hard-coded): the current address/prefix and gateway, else a neutral pattern
    function netLive() { return net && net.ok && net.uplink ? net.uplink : null }
    function netHintAddr() { var u = netLive(); return u && u.ipv4 && u.ipv4.length ? u.ipv4[0].addr + "/" + u.ipv4[0].prefix : "a.b.c.d/nn" }
    function netHintGw() { var u = netLive(); return u && u.gateway ? u.gateway : "a.b.c.d" }
    function netLoadFields() {
        if (netEditing || !net || !net.ok || !net.profile) return
        netMethod = net.profile.method
        netAddr = net.profile.address || ""
        netGw = net.profile.gateway || ""
        netDns = (net.profile.dns || []).join(", ")
    }
    function netApply() {
        if (netBusy || netPending) return
        netErr = ""
        netBusy = true
        netApplyProc.command = [bin, "net", "apply", "--no-wait", "--json", "--method", netMethod,
                                "--address", netMethod === "static" ? netAddr.trim() : "", "--gateway", netMethod === "static" ? netGw.trim() : "",
                                "--dns", netDns.replace(/\s+/g, "")]
        netApplyProc.running = true
    }
    function netAnswer(verb) {
        if (!netPending) return
        netPending = null
        netCtl.verb = verb
        netCtl.command = [bin, "net", verb]
        netCtl.running = true
    }
    function setStatus(text, isError) { status = text; statusError = isError }
    function setValue(key, value) {
        if (busy) return
        busy = true
        setter.key = key
        setter.value = value
        setter.command = [bin, "set", key, value]
        setter.running = true
    }

    Process {
        id: loader
        command: [win.bin, "show", "--json"]
        stdout: StdioCollector { id: loadOut }
        onExited: (code, status) => {
            try {
                var j = JSON.parse(loadOut.text)
                win.cfg = j
                if (!j.ok) win.setStatus(j.error, true)
            } catch (e) {
                win.setStatus("could not read the output of: " + win.bin + " show --json", true)
            }
        }
    }

    Process {
        id: setter
        property string key: ""
        property string value: ""
        stdout: StdioCollector { id: setOut }
        stderr: StdioCollector { id: setErr }
        onExited: (code, status) => {
            if (code === 0) win.setStatus("Saved: " + key + " = " + value, false)
            else win.setStatus((setErr.text + setOut.text).trim() || ("hyprdeb set failed (exit " + code + ")"), true)
            win.busy = false
            win.reload()
            if (key.indexOf("vpn.") === 0) win.refreshVpn()
        }
    }

    Process {
        id: prnStatus
        command: [win.bin, "print", "status", "--json"]
        stdout: StdioCollector { id: prnStatusOut }
        onExited: (code, status) => {
            try { win.prn = JSON.parse(prnStatusOut.text) } catch (e) { win.prn = { ok: false, checks: [], lines: [], error: "could not read: " + win.bin + " print status --json" } }
            if (win.prnState("CUPS") === "ok" && win.prnState("queue") === "ok") prnJobsLoader.running = true
            else { win.prnJobs = null; win.prnBusy = false; prnGuard.stop() }
        }
    }
    Process {
        id: prnJobsLoader
        command: [win.bin, "print", "jobs", "--json"]
        stdout: StdioCollector { id: prnJobsOut }
        onExited: (code, status) => {
            try { win.prnJobs = JSON.parse(prnJobsOut.text) } catch (e) { win.prnJobs = { ok: false, jobs: [], error: "could not read: " + win.bin + " print jobs --json" } }
            win.prnBusy = false
            prnGuard.stop()
        }
    }
    Process {
        id: prnAct
        stdout: StdioCollector { id: prnActOut }
        stderr: StdioCollector { id: prnActErr }
        onExited: (code, status) => {
            var msg = (prnActOut.text + prnActErr.text).trim().replace(/^hyprdeb: (error: )?/, "")
            win.setStatus(msg || (code === 0 ? "Done." : "hyprdeb print failed (exit " + code + ")"), code !== 0)
            win.prnConfirmTest = false
            win.prnBusy = false
            prnGuard.stop()
            win.refreshPrn()
        }
    }
    Timer {     // a check or action that hangs (CUPS stuck) must not leave the buttons disabled for good
        id: prnGuard
        interval: 15000
        onTriggered: {
            prnStatus.running = false; prnJobsLoader.running = false; prnAct.running = false
            win.prnBusy = false
            win.setStatus("The printer check took too long and was stopped; press Re-check to try again.", true)
        }
    }

    // Live VPN state while the window is open: `hyprdeb vpn watch` prints a line whenever the tunnel changes (D-Bus, no polling). It exits by
    // itself when this window (its reader) is gone.
    Process {
        id: vpnWatch
        command: [win.bin, "vpn", "watch"]
        running: true
        stdout: SplitParser { onRead: data => win.refreshVpn() }
        onExited: vpnWatchRestart.start()
    }
    Timer { id: vpnWatchRestart; interval: 5000; onTriggered: vpnWatch.running = true }

    Process {
        id: nasLoader
        command: [win.bin, "nas", "status", "--json"]
        stdout: StdioCollector { id: nasOut }
        onExited: (code, status) => {
            try { win.nas = JSON.parse(nasOut.text) } catch (e) { win.nas = { ok: false, error: "could not read: " + win.bin + " nas status --json" } }
        }
    }

    Process {
        id: netLoader
        command: [win.bin, "net", "status", "--json"]
        stdout: StdioCollector { id: netOut }
        onExited: (code, status) => {
            try { win.net = JSON.parse(netOut.text) } catch (e) { win.net = { ok: false, error: "could not read: " + win.bin + " net status --json" } }
            win.netBusy = false
            win.netLoadFields()
            if (win.net.ok && win.net.pending && !win.netPending) win.netPending = { deadline: win.net.pending.deadline }
        }
    }

    Process {
        id: netApplyProc
        stdout: StdioCollector { id: netApplyOut }
        stderr: StdioCollector { id: netApplyErr }
        onExited: (code, status) => {
            var d = null
            try { d = JSON.parse(netApplyOut.text) } catch (e) { d = null }
            win.netBusy = false
            if (!d) { win.netErr = (netApplyErr.text || "hyprdeb net apply failed (exit " + code + ")").trim().replace(/^hyprdeb: error: /, ""); return }
            if (d.ok === false) { win.netErr = d.error; return }
            if (d.changed === false) { win.netErr = ""; win.setStatus(d.message || "Already as configured.", false); win.netEditing = false; win.refreshNet(); return }
            win.net = d.status
            win.netPending = { deadline: d.deadline }
            win.netRemaining = Math.max(0, Math.round(d.deadline - Date.now() / 1000))
        }
    }

    Process {
        id: netCtl
        property string verb: ""
        stdout: StdioCollector { id: netCtlOut }
        stderr: StdioCollector { id: netCtlErr }
        onExited: (code, status) => {
            var msg = (netCtlOut.text + netCtlErr.text).trim().replace(/^hyprdeb: error: /, "")
            win.setStatus(msg || (code === 0 ? "Done." : "hyprdeb net " + verb + " failed (exit " + code + ")"), code !== 0)
            win.netEditing = false
            win.refreshNet()
        }
    }

    Timer {
        interval: 1000; repeat: true; running: win.netPending !== null
        onTriggered: {
            win.netRemaining = Math.max(0, Math.round(win.netPending.deadline - Date.now() / 1000))
            if (win.netRemaining <= 0) {
                win.netPending = null
                win.netEditing = false
                win.setStatus("No answer: the previous network settings are coming back.", true)
                netAfterRevert.start()
            }
        }
    }
    Timer { id: netAfterRevert; interval: 8000; onTriggered: win.refreshNet() }

    Process {
        id: vpnLoader
        command: [win.bin, "vpn", "status", "--json"]
        stdout: StdioCollector { id: vpnOut }
        onExited: (code, status) => {
            try { win.vpn = JSON.parse(vpnOut.text) } catch (e) { win.vpn = { error: "could not read: " + win.bin + " vpn status --json" } }
        }
    }

    Process {
        id: vpnAct
        property string verb: ""
        stdout: StdioCollector { id: vpnActOut }
        stderr: StdioCollector { id: vpnActErr }
        onExited: (code, status) => {
            var msg = (vpnActOut.text + vpnActErr.text).trim().replace(/^hyprdeb: /, "")
            win.setStatus(msg || (code === 0 ? "Done." : "hyprdeb vpn " + verb + " failed (exit " + code + ")"), code !== 0)
            win.vpnBusy = false
            if (code === 0) { win.vpnConfirmDelete = false; win.vpnRenaming = false; win.vpnRenameTo = "" }
            win.refreshVpn()
        }
    }

    Process {
        id: vpnImportAct
        stdout: StdioCollector { id: vpnImpOut }
        stderr: StdioCollector { id: vpnImpErr }
        onStarted: {
            if (win.vpnPending !== "") {
                write(win.vpnPending)
                stdinEnabled = false          // closes stdin: the CLI reads to the end of its input
            }
            win.vpnClearPaste()
        }
        onExited: (code, status) => {
            win.vpnClearPaste()
            var lines = (vpnImpOut.text + vpnImpErr.text).trim().split("\n")
            var msg = lines.join("\n").replace(/hyprdeb: /g, "")
            win.setStatus(msg || (code === 0 ? "Imported." : "Import failed (exit " + code + ")"), code !== 0)
            if (code === 0) { win.vpnNewName = ""; win.vpnFile = ""; win.vpnAddOpen = false; win.vpnReplaceMode = false }
            win.vpnBusy = false
            win.refreshVpn()
        }
    }

    Process {
        id: vpnPick
        command: [win.bin, "vpn", "pick-file"]
        stdout: StdioCollector { id: vpnPickOut }
        stderr: StdioCollector { id: vpnPickErr }
        onExited: (code, status) => {
            win.vpnBusy = false
            if (code === 0) { win.vpnFile = vpnPickOut.text.trim(); win.vpnClearPaste(); win.setStatus("Chosen: " + win.vpnFile, false) }
            else if (code === 5) win.setStatus("", false)
            else win.setStatus(vpnPickErr.text.trim().replace(/^hyprdeb: /, "") || "The file chooser failed.", true)
        }
    }
    onVisibleChanged: if (!visible) { vpnClearPaste(); nasClearPassword() }

    Process {
        id: nasAct
        property string verb: ""
        stdout: StdioCollector { id: nasActOut }
        stderr: StdioCollector { id: nasActErr }
        onExited: (code, status) => {
            var msg = (nasActOut.text + nasActErr.text).trim().replace(/^hyprdeb: error: /, "")
            win.setStatus(msg || (code === 0 ? "Done." : "hyprdeb nas " + verb + " failed (exit " + code + ")"), code !== 0)
            win.nasBusy = false
            win.refreshNas()
        }
    }

    // add / edit / test / remove: --json answers {"ok", "message" | "error", "notes"}; a CLI that cannot even start gives plain text
    Process {
        id: nasMgmt
        property string verb: ""
        stdout: StdioCollector { id: nasMgmtOut }
        stderr: StdioCollector { id: nasMgmtErr }
        onStarted: {
            if (stdinEnabled) { write(win.nasPending); stdinEnabled = false }   // one line, then EOF
            win.nasClearPassword()                                             // the field and the pending copy are emptied right away
        }
        onExited: (code, status) => {
            nasGuard.stop()
            win.nasClearPassword()
            var r = null
            try { r = JSON.parse(nasMgmtOut.text.trim().split("\n").pop()) } catch (e) { r = null }
            var ok = r ? r.ok === true : false
            var text = r ? (ok ? r.message : r.error) : (nasMgmtErr.text + nasMgmtOut.text).trim().replace(/^hyprdeb: (error: )?/, "")
            if (!text) text = "hyprdeb nas " + verb + " failed (exit " + code + ")."
            var notes = r && r.notes ? r.notes.join(" ") : ""
            var full = notes ? text + " " + notes : text
            if (r && r.warning) full += " " + r.warning
            if (win.nasFormMode !== "" && verb !== "remove") { win.nasFormMsg = full; win.nasFormErr = !ok }
            win.setStatus(full, !ok)
            if (ok && (verb === "add" || verb === "edit")) win.nasCloseForm()
            if (ok && verb === "remove") win.nasConfirmRemove = ""
            win.nasBusy = false
            win.refreshNas()
        }
    }
    // the CLI stops waiting for the password dialog after 200 s; this only frees the window if the CLI itself hangs
    Timer {
        id: nasGuard
        interval: 230000
        onTriggered: {
            nasMgmt.running = false
            win.nasClearPassword()
            win.nasBusy = false
            win.setStatus("The NAS request took too long and was stopped; nothing was changed unless the status below says so.", true)
        }
    }

    // Hot reload tears the window down while Qt is still using it, and a close/kill right after crashes Quickshell (see docs/gotchas.md, Quickshell).
    // The settings window never needs it: install.sh closes nothing, `hyprdeb gui` always starts a fresh instance.
    Component.onCompleted: {
        Quickshell.watchFiles = false
        var i = pageIndexOf(Quickshell.env("HYPRDEB_PAGE") || "")      // `hyprdeb gui` passes the page to open (explicit, else the remembered one)
        pageIndex = i >= 0 ? i : 0
        reload(); refreshNas(); refreshNet(); refreshVpn(); refreshPrn()
    }
    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }

    // An optional Tabler icon (font "tabler-icons", glyph from `show --json` "icons"; empty when the font is not installed) before the title.
    component Heading: RowLayout {
        id: hrow
        property string text: ""
        property string icon: ""
        spacing: 8
        Text {
            visible: hrow.icon !== ""
            text: hrow.icon; font.family: "tabler-icons"; font.pixelSize: 19; color: win.dim
            topPadding: 6
        }
        Text { text: hrow.text; color: win.fg; font.pixelSize: 17; font.bold: true; topPadding: 6 }
    }

    component Choice: RowLayout {
        id: row
        property string label: ""
        property string key: ""
        property var model: []
        property string current: ""
        property string empty: ""   // shown when `current` is "" (the option has no value of its own)
        spacing: 12
        Text { text: row.label; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
        ComboBox {
            id: box
            Layout.preferredWidth: 180
            model: row.model
            enabled: !win.busy
            function sync() { currentIndex = row.current === "" ? -1 : Math.max(0, row.model.indexOf(row.current)) }
            onModelChanged: sync()
            Connections { target: row; function onCurrentChanged() { box.sync() } }
            // After EVERY reload of `show --json`, also when the values are unchanged (a rejected set): `current` is then the
            // same string, so onCurrentChanged does not fire and the box would keep showing the rejected choice.
            Connections { target: win; function onCfgChanged() { Qt.callLater(box.sync) } }
            onActivated: win.setValue(row.key, currentText)
            contentItem: Text { text: box.currentIndex < 0 ? row.empty : box.displayText; color: "white"; leftPadding: 8; verticalAlignment: Text.AlignVCenter; font.pixelSize: 15 }
            background: Rectangle { color: win.panel; radius: 4 }
            delegate: ItemDelegate {
                width: box.width
                contentItem: Text { text: modelData; color: "white"; font.pixelSize: 15 }
                background: Rectangle { color: highlighted ? "#3d4870" : win.panel }
                highlighted: box.highlightedIndex === index
            }
            popup.background: Rectangle { color: win.panel; radius: 4; border.color: "#3d4870" }
        }
    }

    component ActionButton: Button {
        id: ab
        property string label: ""
        text: label
        enabled: !win.nasBusy && !win.busy
        implicitHeight: 32
        contentItem: Text { text: ab.text; color: ab.enabled ? "white" : "#6f7890"; font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
        background: Rectangle { color: ab.enabled ? (ab.down ? "#3d4870" : win.panel) : "#232a3f"; radius: 4 }
    }

    component NetField: RowLayout {
        id: nf
        property string label: ""
        property string value: ""
        property bool active: true
        property string hint: ""
        signal edited(string text)
        spacing: 12
        Text { text: nf.label; color: nf.active ? win.fg : win.dim; font.pixelSize: 15; Layout.preferredWidth: 150 }
        TextField {
            Layout.fillWidth: true
            text: nf.value
            placeholderText: nf.hint
            enabled: nf.active && !win.netBusy && !win.netPending
            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
            background: Rectangle { color: nf.active ? win.panel : "#232a3f"; radius: 4 }
            onTextEdited: { nf.edited(text); win.netEditing = true }
        }
    }

    component Toggle: RowLayout {
        id: trow
        property string label: ""
        property string key: ""
        property bool current: false
        spacing: 12
        Text { text: trow.label; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
        Switch {
            id: sw
            enabled: !win.busy
            function sync() { checked = trow.current }
            Component.onCompleted: sync()
            Connections { target: trow; function onCurrentChanged() { sw.sync() } }
            // Also after a rejected set: `current` is then unchanged and the switch would keep the rejected position.
            Connections { target: win; function onCfgChanged() { Qt.callLater(sw.sync) } }
            onToggled: win.setValue(trow.key, checked ? "true" : "false")
        }
    }

    // A slider saves ONCE, when released (or after a keyboard step), not on every move; the value is shown next to it.
    component SliderRow: RowLayout {
        id: srow
        property string label: ""
        property string key: ""
        property real current: 0
        property real from: 0
        property real to: 1
        property real step: 0.1
        property int decimals: 1
        property string unit: ""
        spacing: 12
        Text { text: srow.label; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
        Slider {
            id: sl
            Layout.preferredWidth: 180
            from: srow.from; to: srow.to; stepSize: srow.step
            enabled: !win.busy
            function sync() { value = srow.current }
            Component.onCompleted: sync()
            // from/to arrive with the first `show --json`; a value set before that drifts (25 showed as 26), so set it again.
            onFromChanged: Qt.callLater(sync)
            onToChanged: Qt.callLater(sync)
            Connections { target: srow; function onCurrentChanged() { sl.sync() } }
            Connections { target: win; function onCfgChanged() { Qt.callLater(sl.sync) } }
            function commit() {
                var v = value.toFixed(srow.decimals)
                if (Number(v) !== Number(srow.current.toFixed(srow.decimals))) win.setValue(srow.key, v)
            }
            onPressedChanged: if (!pressed) commit()
            onMoved: if (!pressed) commit()   // arrow keys; while dragging, `pressed` is true and nothing is saved
        }
        Text {
            text: sl.value.toFixed(srow.decimals) + srow.unit
            color: win.fg; font.pixelSize: 15
            Layout.preferredWidth: 80
        }
    }


    // ---------------------------------------------------------------- navigation
    // One page per section, shown through a StackLayout: every page stays alive, so switching keeps an unfinished paste, the Network fields
    // and the 60 s wait. The page is chosen at start (HYPRDEB_PAGE), by `hyprdeb gui --page NAME` on an open window (IpcHandler "gui", function
    // "page": a function called "show" would collide with `qs ipc show`) and by the user; the last one is remembered in gui-page.
    // 11 pages: Ctrl+1..9 and Ctrl+0 reach the first ten, the last one (Fonts) the sidebar or Ctrl+PageDown.
    readonly property var pages: [
        { name: "network", label: "Network" }, { name: "vpn", label: "VPN" }, { name: "nas", label: "NAS" }, { name: "printers", label: "Printers" }, { name: "monitors", label: "Monitors" },
        { name: "wallpaper", label: "Wallpaper" }, { name: "idle", label: "Idle" }, { name: "keyboard", label: "Keyboard" },
        { name: "mouse", label: "Mouse" }, { name: "notifications", label: "Notifications" }, { name: "fonts", label: "Fonts" }
    ]
    property int pageIndex: 0
    function pageIndexOf(name) { for (var i = 0; i < pages.length; i++) if (pages[i].name === name) return i; return -1 }
    function gotoIndex(i) {
        if (i < 0 || i >= pages.length || i === pageIndex) return
        pageIndex = i
        pageFile.setText(pages[i].name + "\n")
    }
    function gotoName(name) { gotoIndex(pageIndexOf(name)) }
    FileView {
        id: pageFile
        preload: false          // only written here; the CLI reads it
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/hyprdeb/gui-page"
    }
    IpcHandler {
        target: "gui"
        function page(name: string): void { win.gotoName(name) }
        function current(): string { return win.pages[win.pageIndex].name }
    }
    Process { id: shortcutsOpen; command: [win.bin, "gui", "--page", "shortcuts"] }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.gotoIndex(0) }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.gotoIndex(1) }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.gotoIndex(2) }
    Shortcut { sequence: "Ctrl+4"; onActivated: win.gotoIndex(3) }
    Shortcut { sequence: "Ctrl+5"; onActivated: win.gotoIndex(4) }
    Shortcut { sequence: "Ctrl+6"; onActivated: win.gotoIndex(5) }
    Shortcut { sequence: "Ctrl+7"; onActivated: win.gotoIndex(6) }
    Shortcut { sequence: "Ctrl+8"; onActivated: win.gotoIndex(7) }
    Shortcut { sequence: "Ctrl+9"; onActivated: win.gotoIndex(8) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.gotoIndex(9) }
    Shortcut { sequence: "Ctrl+PgUp"; onActivated: win.gotoIndex(win.pageIndex - 1) }
    Shortcut { sequence: "Ctrl+PgDown"; onActivated: win.gotoIndex(win.pageIndex + 1) }

    // One scrolling page (its own scrollbar, the same look as before). Children go into the column.
    component Page: Flickable {
        id: pg
        default property alias content: pcol.data
        clip: true
        contentWidth: width
        contentHeight: pcol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: pg.contentHeight > pg.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff   // visible: there is more below
            contentItem: Rectangle { implicitWidth: 7; radius: 3; color: "#7d8cbc" }
            background: Rectangle { implicitWidth: 7; radius: 3; color: "#2b3350" }
        }
        ColumnLayout {
            id: pcol
            width: pg.width - 14
            spacing: 8
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ---- sidebar ----
            ColumnLayout {
                Layout.preferredWidth: 170
                Layout.minimumWidth: 170
                Layout.maximumWidth: 170
                Layout.fillHeight: true
                spacing: 6
                ListView {
                    id: nav
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: win.pages
                    currentIndex: win.pageIndex
                    interactive: false
                    spacing: 2
                    focus: true
                    activeFocusOnTab: true
                    Keys.onUpPressed: win.gotoIndex(win.pageIndex - 1)      // Up/Down move between pages only while the sidebar has focus
                    Keys.onDownPressed: win.gotoIndex(win.pageIndex + 1)
                    delegate: Rectangle {
                        width: nav.width
                        height: 40
                        radius: 6
                        color: index === win.pageIndex ? win.panel : (hover.hovered ? "#232a3f" : "transparent")
                        HoverHandler { id: hover }
                        Rectangle { visible: index === win.pageIndex; width: 3; height: parent.height - 12; radius: 1.5; color: "#7c5cff"; anchors.verticalCenter: parent.verticalCenter }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8; spacing: 10
                            Text {
                                visible: win.icon(modelData.name) !== ""
                                text: win.icon(modelData.name)
                                font.family: "tabler-icons"; font.pixelSize: 18
                                color: index === win.pageIndex ? "white" : win.dim
                                Layout.preferredWidth: 22
                            }
                            Text { text: modelData.label; color: index === win.pageIndex ? "white" : win.fg; font.pixelSize: 15; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle { visible: modelData.name === "network" && win.netPending !== null; width: 9; height: 9; radius: 4.5; color: "#ffcf6b" }   // a change waits for Keep / Revert
                        }
                        MouseArea { anchors.fill: parent; onClicked: { win.gotoIndex(index); nav.forceActiveFocus() } }
                    }
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: "#2b3350" }
                Rectangle {     // opens the existing shortcuts window
                    Layout.fillWidth: true
                    height: 40
                    radius: 6
                    color: scHover.hovered ? "#232a3f" : "transparent"
                    HoverHandler { id: scHover }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8; spacing: 10
                        Text {
                            visible: win.icon("shortcuts") !== ""
                            text: win.icon("shortcuts")
                            font.family: "tabler-icons"; font.pixelSize: 18; color: win.dim
                            Layout.preferredWidth: 22
                        }
                        Text { text: "Shortcuts"; color: win.fg; font.pixelSize: 15; Layout.fillWidth: true }
                    }
                    MouseArea { anchors.fill: parent; onClicked: shortcutsOpen.running = true }
                }
            }

            StackLayout {
                currentIndex: win.pageIndex
                Layout.fillWidth: true
                Layout.fillHeight: true
            Page {
                // ---- page: network ----
                Heading { text: "Network"; icon: win.icon("network") }
                Text {
                    visible: win.net && win.net.ok
                    text: win.net && win.net.ok ? win.net.lines.join("\n") : ""
                    color: win.fg; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    visible: win.net && !win.net.ok
                    text: win.net && !win.net.ok ? win.net.error : ""
                    color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    visible: !win.net
                    text: "Checking..."
                    color: win.dim; font.pixelSize: 14; Layout.fillWidth: true
                }
                ActionButton { label: win.netBusy ? "Checking..." : "Re-check"; enabled: !win.netBusy; onClicked: win.refreshNet() }

                Text { text: "IPv4 settings"; color: win.fg; font.pixelSize: 15; Layout.topMargin: 6 }
                RowLayout {
                    spacing: 12
                    Text { text: "Method"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                    ComboBox {
                        id: netBox
                        Layout.preferredWidth: 180
                        model: ["DHCP", "Static"]
                        enabled: !win.netBusy && !win.netPending
                        currentIndex: win.netMethod === "static" ? 1 : 0
                        onActivated: { win.netMethod = currentIndex === 1 ? "static" : "dhcp"; win.netEditing = true }
                        contentItem: Text { text: netBox.displayText; color: "white"; leftPadding: 8; verticalAlignment: Text.AlignVCenter; font.pixelSize: 15 }
                        background: Rectangle { color: win.panel; radius: 4 }
                        delegate: ItemDelegate {
                            width: netBox.width
                            contentItem: Text { text: modelData; color: "white"; font.pixelSize: 15 }
                            background: Rectangle { color: highlighted ? "#3d4870" : win.panel }
                            highlighted: netBox.highlightedIndex === index
                        }
                        popup.background: Rectangle { color: win.panel; radius: 4; border.color: "#3d4870" }
                    }
                }
                NetField { label: "Address"; hint: win.netHintAddr(); value: win.netAddr; active: win.netMethod === "static"; onEdited: (t) => win.netAddr = t }
                NetField { label: "Gateway"; hint: win.netHintGw(); value: win.netGw; active: win.netMethod === "static"; onEdited: (t) => win.netGw = t }
                NetField { label: "DNS servers"; hint: win.netMethod === "static" ? "needed, e.g. " + win.netHintGw() : "empty = from DHCP"; value: win.netDns; onEdited: (t) => win.netDns = t }
                RowLayout {
                    spacing: 10
                    ActionButton { label: win.netBusy && !win.netPending ? "Applying..." : "Apply"; enabled: !win.netBusy && !win.netPending; onClicked: win.netApply() }
                    ActionButton { label: "Reset fields"; enabled: !win.netBusy && !win.netPending && win.netEditing; onClicked: { win.netEditing = false; win.netErr = ""; win.netLoadFields() } }
                }
                Text {
                    visible: win.netErr !== ""
                    text: win.netErr
                    color: "#ff6b6b"; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    text: "Static needs a gateway and at least one DNS server. DHCP with DNS servers filled in uses only those. Applied changes revert by themselves after 60 s unless you press Keep. The kept values are saved in settings.toml ([network])."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }

            }
            Page {
                // ---- page: vpn ----
                Heading { text: "VPN (WireGuard)"; icon: win.icon("vpn") }
                Text {
                    visible: win.vpnOk()
                    text: win.vpnOk() ? win.vpn.lines.join("\n") : ""
                    color: win.fg; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    visible: win.vpn && !win.vpnOk()
                    text: win.vpn && !win.vpnOk() ? win.vpn.error : ""
                    color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Repeater {
                    model: win.vpnOk() ? win.vpn.profiles : []
                    RadioButton {
                        id: rb
                        text: modelData.name + (modelData.active ? "  (on)" : "")
                        checked: modelData.name === win.vpnSelected()
                        enabled: !win.vpnBusy && !win.busy && !win.vpnSelectedActive()
                        onClicked: { win.vpnConfirmDelete = false; win.vpnRenaming = false; if (win.vpn.default !== modelData.name) win.setValue("vpn.default", modelData.name) }
                        contentItem: Text { text: rb.text; leftPadding: rb.indicator.width + 8; color: rb.enabled ? win.fg : win.dim; font.pixelSize: 14; verticalAlignment: Text.AlignVCenter }
                    }
                }
                Text {
                    visible: win.vpnSelectedActive()
                    text: "turn off " + (win.vpn && win.vpn.active ? win.vpn.active.name : "") + " first to choose another profile"
                    color: win.dim; font.pixelSize: 12
                }
                Text {
                    visible: win.vpnOk() && win.vpn.profiles.length > 1 && win.vpnSelected() === ""
                    text: "Choose a profile: it becomes the default for the quick menu too."
                    color: win.dim; font.pixelSize: 12
                }
                RowLayout {
                    visible: win.vpnOk() && win.vpn.profiles.length > 0
                    spacing: 10
                    ActionButton {
                        label: win.vpnSelectedActive() ? "Turn off" : "Turn on"
                        enabled: !win.vpnBusy && !win.busy && win.vpnSelected() !== ""
                        onClicked: win.vpnAction(win.vpnSelectedActive() ? "off" : "on", win.vpnSelected())
                    }
                    ActionButton {
                        label: "Rename..."
                        enabled: !win.vpnBusy && !win.busy && win.vpnSelected() !== ""
                        onClicked: { win.vpnRenaming = !win.vpnRenaming; win.vpnConfirmDelete = false; win.vpnRenameTo = "" }
                    }
                    ActionButton {
                        label: "Replace config..."
                        enabled: !win.vpnBusy && !win.busy && win.vpnSelected() !== ""
                        onClicked: {
                            win.vpnClearPaste(); win.vpnFile = ""; win.vpnConfirmReplace = false; win.vpnConfirmDelete = false; win.vpnRenaming = false
                            win.vpnNewName = win.vpnSelected(); win.vpnReplaceMode = true; win.vpnAddOpen = true
                        }
                    }
                    ActionButton {
                        label: "Delete..."
                        enabled: !win.vpnBusy && !win.busy && win.vpnSelected() !== ""
                        onClicked: { win.vpnConfirmDelete = !win.vpnConfirmDelete; win.vpnRenaming = false }
                    }
                    ActionButton { label: "Refresh"; enabled: !win.vpnBusy; onClicked: win.refreshVpn() }
                }
                RowLayout {
                    visible: win.vpnConfirmDelete
                    spacing: 10
                    Text { text: "Delete hyprdeb-wg-" + win.vpnSelected() + "? (turned off first if on; its key is deleted)"; color: "#ffcf6b"; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    ActionButton { label: "Delete"; enabled: !win.vpnBusy && !win.busy; onClicked: win.vpnRun("remove", [win.bin, "vpn", "remove", win.vpnSelected(), "--yes"], "Deleting...") }
                    ActionButton { label: "Cancel"; onClicked: win.vpnConfirmDelete = false }
                }
                RowLayout {
                    visible: win.vpnRenaming
                    spacing: 10
                    TextField {
                        Layout.fillWidth: true
                        text: win.vpnRenameTo
                        placeholderText: "New name (1-11 characters: a-z 0-9 -)"
                        color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                        background: Rectangle { color: win.panel; radius: 4 }
                        onTextEdited: win.vpnRenameTo = text.trim()
                    }
                    ActionButton {
                        label: "Rename"
                        enabled: !win.vpnBusy && !win.busy && win.vpnNameOk(win.vpnRenameTo)
                        onClicked: win.vpnRun("rename", [win.bin, "vpn", "rename", win.vpnSelected(), win.vpnRenameTo], "Renaming (a tunnel that is on is turned off first)...")
                    }
                    ActionButton { label: "Cancel"; onClicked: win.vpnRenaming = false }
                }
                Toggle {
                    label: "LAN names first"; key: "vpn.keep_lan_dns"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["vpn.keep_lan_dns"] === true : false
                }
                ActionButton {
                    label: win.vpnAddOpen ? "Hide" : "Add a configuration..."
                    enabled: !win.vpnBusy && !win.busy
                    onClicked: {
                        win.vpnAddOpen = !win.vpnAddOpen
                        win.vpnConfirmDelete = false; win.vpnRenaming = false
                        if (win.vpnAddOpen) { win.vpnReplaceMode = false; win.vpnNewName = "" }
                        else { win.vpnClearPaste(); win.vpnFile = ""; win.vpnConfirmReplace = false; win.vpnReplaceMode = false }
                    }
                }
                Text {
                    visible: win.vpnAddOpen && win.vpnReplaceMode
                    text: "Replace the configuration of hyprdeb-wg-" + win.vpnNewName + ": the name stays, a tunnel that is on is turned off. The stored configuration is never shown."
                    color: "#ffcf6b"; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                ColumnLayout {
                    visible: win.vpnAddOpen
                    Layout.fillWidth: true
                    spacing: 8
                    RowLayout {
                        spacing: 12
                        Text { text: "Name"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.fillWidth: true
                            text: win.vpnNewName
                            placeholderText: "1-11 characters: a-z 0-9 -"
                            enabled: !win.vpnBusy && !win.vpnReplaceMode
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                            onTextEdited: { win.vpnNewName = text.trim(); win.vpnConfirmReplace = false }
                        }
                    }
                    ScrollView {
                        visible: win.vpnFile === ""
                        Layout.fillWidth: true; Layout.preferredHeight: 130
                        TextArea {
                            id: vpnPaste
                            placeholderText: "Paste the WireGuard configuration here"
                            wrapMode: TextEdit.NoWrap; selectByMouse: true; persistentSelection: false
                            font.family: "monospace"; font.pixelSize: 12
                            color: "white"; placeholderTextColor: "#6f7890"
                            enabled: !win.vpnBusy
                            readOnly: win.vpnMasked
                            onTextChanged: win.vpnMaskPaste()
                            background: Rectangle { color: win.panel; radius: 4 }
                        }
                    }
                    Text {
                        visible: win.vpnFile === "" && win.vpnMasked
                        text: "Key values are hidden here. The text is sent unchanged; Clear text empties the box."
                        color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    Text {
                        visible: win.vpnFile !== ""
                        text: "File: " + win.vpnFile
                        color: win.fg; font.pixelSize: 13; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                    }
                    CheckBox {
                        visible: win.vpnFile === ""
                        checked: win.vpnScrub
                        onToggled: win.vpnScrub = checked
                        id: scrubBox
                        // the control's own text must be set: with an empty text the Basic style centres the indicator
                        text: "After importing, remove it from clipboard history and clear the clipboard"
                        contentItem: Text { text: scrubBox.text; leftPadding: scrubBox.indicator.width + scrubBox.spacing
                                            color: win.fg; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap }
                    }
                    RowLayout {
                        spacing: 10
                        ActionButton { label: "Clear text"; visible: win.vpnFile === "" && win.vpnMasked; onClicked: win.vpnClearPaste() }
                        ActionButton { label: "Import"; enabled: !win.vpnBusy && !win.busy; onClicked: win.vpnImport(win.vpnReplaceMode) }
                        ActionButton {
                            label: win.vpnFile === "" ? "Choose file..." : "Use pasted text"
                            enabled: !win.vpnBusy && !win.busy
                            onClicked: {
                                if (win.vpnFile !== "") { win.vpnFile = ""; return }
                                win.vpnBusy = true
                                win.setStatus("Choose the .conf file in the dialog...", false)
                                vpnPick.running = true
                            }
                        }
                    }
                    RowLayout {
                        visible: win.vpnConfirmReplace
                        spacing: 10
                        Text { text: "Replace hyprdeb-wg-" + win.vpnNewName + "?"; color: "#ffcf6b"; font.pixelSize: 14 }
                        ActionButton { label: "Replace"; enabled: !win.vpnBusy && !win.busy; onClicked: win.vpnImport(true) }
                        ActionButton { label: "Cancel"; onClicked: win.vpnConfirmReplace = false }
                    }
                }
                Text {
                    text: "Pick a profile to use it: the choice is also what the quick menu turns on. Add: paste a WireGuard configuration (or choose the file) and give it a name: it is imported into NetworkManager, the same as hyprdeb vpn import. Pasted text goes to hyprdeb on stdin only and the box is emptied afterwards; the key lives only in NetworkManager. The tunnel stays off until you turn it on and is never on at boot. \"LAN names first\" asks the LAN resolver before the tunnel's DNS, so names that only your LAN resolver knows keep working, but DNS queries then leave through the LAN."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }

            }
            Page {
                // ---- page: nas ----
                Heading { text: "NAS"; icon: win.icon("nas") }
                Text {
                    visible: win.nas && !win.nas.ok
                    text: win.nas && !win.nas.ok ? win.nas.error : ""
                    color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    visible: win.nas && win.nas.ok && win.nasShares().length === 0
                    text: "No NAS is set up yet. Add one below: its password is kept only in a root-only file and is never shown again."
                    color: win.dim; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Repeater {
                    model: win.nasShares()
                    delegate: ColumnLayout {
                        id: share
                        property var s: modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            text: share.s.name + "   //" + share.s.server + "/" + share.s.share + "  ->  " + share.s.mountpoint
                            color: win.fg; font.pixelSize: 15; font.bold: true; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                        }
                        Text {
                            text: share.s.lines.join("\n")
                            color: share.s.state === "mounted" ? "#7bd88f" : (share.s.state === "waiting" && share.s.reachable && share.s.credentials_ok ? win.fg : "#ffcf6b")
                            font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                        RowLayout {
                            spacing: 10
                            ActionButton { label: "Connect"; enabled: !win.nasBusy && !win.busy && share.s.can_connect; onClicked: win.nasAction("mount", share.s.name) }
                            ActionButton { label: "Open in Thunar"; enabled: !win.nasBusy && !win.busy && share.s.can_open; onClicked: win.nasAction("open", share.s.name) }
                            ActionButton { label: "Disconnect"; enabled: !win.nasBusy && !win.busy && share.s.can_disconnect; onClicked: win.nasAction("unmount", share.s.name) }
                            ActionButton { label: "Edit"; enabled: !win.nasBusy && !win.busy && share.s.manageable; onClicked: win.nasOpenEdit(share.s) }
                            ActionButton { label: "Remove"; enabled: !win.nasBusy && !win.busy && share.s.manageable; onClicked: { win.nasCloseForm(); win.nasConfirmRemove = share.s.name } }
                        }
                        RowLayout {
                            visible: win.nasConfirmRemove === share.s.name
                            spacing: 10
                            Text { text: "Remove NAS " + share.s.name + "? The files on the NAS are not touched."; color: "#ffcf6b"; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            ActionButton { label: "Remove"; enabled: !win.nasBusy && !win.busy; onClicked: win.nasRemove(share.s.name) }
                            ActionButton { label: "Cancel"; onClicked: win.nasConfirmRemove = "" }
                        }
                        Text {
                            visible: !share.s.manageable
                            text: "This share uses a mount point outside /mnt/NAME, so it is managed by hand in settings.toml."
                            color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3d4870"; Layout.topMargin: 4 }
                    }
                }
                ActionButton {
                    label: win.nasFormMode === "add" ? "Hide" : "Add a NAS..."
                    enabled: !win.nasBusy && !win.busy
                    onClicked: { if (win.nasFormMode === "add") win.nasCloseForm(); else win.nasOpenAdd() }
                }
                ColumnLayout {
                    visible: win.nasFormMode !== ""
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: win.nasFormMode === "add" ? "New NAS" : "Edit NAS " + win.nasFormName
                        color: win.fg; font.pixelSize: 15; font.bold: true
                    }
                    Text {
                        visible: win.nasFormMsg !== ""
                        text: win.nasFormMsg
                        color: win.nasFormErr ? "#ff6b6b" : "#7bd88f"
                        font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "Name"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.fillWidth: true
                            text: win.nasFormName
                            enabled: win.nasFormMode === "add" && !win.nasBusy
                            placeholderText: "a-z 0-9 -   (mounted on /mnt/NAME)"
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.nasFormMode === "add" ? win.panel : "#232a3f"; radius: 4 }
                            onTextEdited: win.nasFormName = text.trim()
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "Server"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.fillWidth: true
                            text: win.nasFServer
                            enabled: !win.nasBusy
                            placeholderText: "IPv4 address or host name"
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                            onTextEdited: win.nasFServer = text.trim()
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "Share"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.fillWidth: true
                            text: win.nasFShare
                            enabled: !win.nasBusy
                            placeholderText: "the share's name on the server"
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                            onTextEdited: win.nasFShare = text.trim()
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "User name"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.fillWidth: true
                            text: win.nasFUser
                            enabled: !win.nasBusy
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                            onTextEdited: win.nasFUser = text.trim()
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "Password"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            id: nasPass
                            Layout.fillWidth: true
                            enabled: !win.nasBusy
                            echoMode: TextInput.Password
                            passwordCharacter: "\u2022"
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            placeholderText: win.nasFormMode === "edit" ? "empty = keep the stored password" : "kept only in a root-only file"
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text { text: "Idle disconnect"; color: win.fg; font.pixelSize: 15; Layout.preferredWidth: 150 }
                        TextField {
                            Layout.preferredWidth: 120
                            text: win.nasFIdle
                            enabled: !win.nasBusy
                            placeholderText: "10m"
                            color: "white"; placeholderTextColor: "#6f7890"; font.pixelSize: 14
                            background: Rectangle { color: win.panel; radius: 4 }
                            onTextEdited: win.nasFIdle = text.trim()
                        }
                        Text { text: "like 10m or 1h, or off"; color: win.dim; font.pixelSize: 12 }
                    }
                    RowLayout {
                        spacing: 10
                        ActionButton { label: "Test"; enabled: !win.nasBusy && !win.busy; onClicked: win.nasSubmit("test") }
                        ActionButton { label: "Save"; enabled: !win.nasBusy && !win.busy; onClicked: win.nasSubmit(win.nasFormMode) }
                        ActionButton { label: "Cancel"; enabled: !win.nasBusy; onClicked: win.nasCloseForm() }
                    }
                    Text {
                        text: "Test checks the server, the share and the login without mounting anything or saving. Save, Test and Remove ask for the administrator password: the NAS password goes only to a root-only helper, never to a log, and is never shown again."
                        color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                }
                Text {
                    visible: win.nasFormMode === ""
                    text: "Connect mounts a share now; it also connects by itself the first time you open its folder, and disconnects after the idle time. Nothing is mounted at boot, so a NAS that is off cannot delay the start."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }

            }
            Page {
                // ---- page: printers ----
                Heading { text: "Printers"; icon: win.icon("printers") }
                Repeater {
                    model: win.prn && win.prn.checks ? win.prn.checks : []
                    Text {
                        text: (modelData.state === "ok" ? "OK   " : modelData.state === "fail" ? "FAIL " : modelData.state === "skip" ? "--   " : "..   ") + modelData.label + ": " + modelData.detail
                        textFormat: Text.PlainText
                        color: win.prnColor(modelData.state); font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                    }
                }
                Text {
                    visible: win.prn && win.prn.error
                    text: win.prn && win.prn.error ? win.prn.error : ""
                    textFormat: Text.PlainText
                    color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    visible: !win.prn
                    text: "Checking..."
                    color: win.dim; font.pixelSize: 14
                }
                RowLayout {
                    visible: win.prn !== null
                    spacing: 10
                    ActionButton { label: win.prnBusy ? "Checking..." : "Re-check"; enabled: !win.prnBusy; onClicked: win.refreshPrn() }
                    ActionButton {
                        visible: win.prnReady()
                        label: "Print a test page..."
                        enabled: !win.prnBusy
                        onClicked: win.prnConfirmTest = !win.prnConfirmTest
                    }
                }
                RowLayout {
                    visible: win.prnConfirmTest && win.prnReady()
                    spacing: 10
                    Text { text: "Print a test page? It uses one sheet of paper."; color: "#ffcf6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    ActionButton { label: "Print"; enabled: !win.prnBusy; onClicked: win.prnRun([win.bin, "print", "testpage", "--yes"], "Sending the test page...") }
                    ActionButton { label: "Cancel"; enabled: true; onClicked: win.prnConfirmTest = false }
                }
                Text {
                    visible: win.prnJobs && win.prnJobs.ok
                    text: win.prnJobs && win.prnJobs.ok ? (win.prnJobs.jobs.length === 0 ? "No jobs waiting." : "Waiting jobs:") : ""
                    color: win.fg; font.pixelSize: 14
                }
                Text {
                    visible: win.prnJobs && !win.prnJobs.ok
                    text: win.prnJobs && !win.prnJobs.ok ? win.prnJobs.error : ""
                    textFormat: Text.PlainText
                    color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Repeater {
                    model: win.prnJobs && win.prnJobs.ok ? win.prnJobs.jobs : []
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: "#" + modelData.id; color: win.dim; font.pixelSize: 13; Layout.preferredWidth: 44 }
                        Text {
                            text: modelData.title !== "" ? modelData.title : "(no title)"
                            textFormat: Text.PlainText          // job titles are the sender's text: never rich text
                            color: win.fg; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text { text: modelData.state + ", " + modelData.kib + " KiB, " + win.prnAge(modelData.age_s); color: win.dim; font.pixelSize: 12 }
                        ActionButton { label: "Cancel"; enabled: !win.prnBusy; onClicked: win.prnRun([win.bin, "print", "cancel", String(modelData.id)], "Canceling job " + modelData.id + "...") }
                    }
                }
                Text {
                    text: "The queue name and printer address come from [printing] in settings.toml; change them there and run ./install.sh --printing. Nothing is printed unless you press the test page button."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
            }
            Page {
                // ---- page: monitors ----
                Heading { text: "Monitors"; icon: win.icon("monitors") }
                Repeater {
                    model: win.cfg && win.cfg.ok ? win.cfg.monitors : []
                    Text {
                        text: modelData.match + "  –  " + (modelData.disabled ? "disabled" : modelData.mode + ", " + modelData.position
                              + (modelData.scale === null ? "" : ", scale " + modelData.scale))
                        color: win.fg; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Text {
                    visible: win.cfg && win.cfg.ok && win.cfg.monitors.length === 0
                    text: "No [[monitors]] rules: Hyprland's defaults are used."
                    color: win.dim; font.pixelSize: 13
                }
                Text {
                    text: win.cfg && win.cfg.monitors_hint ? "Read-only here: " + win.cfg.monitors_hint : ""
                    color: win.dim; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
            }
            Page {
                // ---- page: wallpaper ----
                Heading { text: "Wallpaper"; icon: win.icon("wallpaper") }
                ListView {
                    id: wall
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 190)   // sized to its content, at most 190
                    clip: true
                    spacing: 4
                    model: win.cfg && win.cfg.ok ? win.cfg.wallpaper.candidates : []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        width: wall.width - 12
                        height: 48
                        radius: 4
                        color: modelData.current ? "#3d4870" : (hover.hovered ? "#323b5c" : win.panel)
                        HoverHandler { id: hover }
                        TapHandler { enabled: !win.busy; onTapped: win.setValue("wallpaper.path", modelData.path) }
                        Row {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 10
                            Image {
                                width: 64; height: 36
                                source: "file://" + modelData.file
                                sourceSize.width: 128
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (modelData.current ? "● " : "") + modelData.label
                                color: win.fg
                                font.pixelSize: 15
                                font.bold: modelData.current
                                elide: Text.ElideRight
                                width: parent.width - 90
                            }
                        }
                    }
                }
                Text {
                    visible: win.cfg && win.cfg.ok && win.cfg.wallpaper.candidates.length <= 1
                    text: "No images found in ~/Pictures/Wallpapers or ~/Pictures."
                    color: win.dim; font.pixelSize: 13
                }

            }
            Page {
                // ---- page: idle ----
                Heading { text: "Idle"; icon: win.icon("idle") }
                Choice {
                    label: "Lock after"; key: "idle.lock_after"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["idle.lock_after"] : []
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["idle.lock_after"] : ""
                }
                Choice {
                    label: "Screen off after"; key: "idle.screen_off_after"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["idle.screen_off_after"] : []
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["idle.screen_off_after"] : ""
                }

            }
            Page {
                // ---- page: keyboard ----
                Heading { text: "Keyboard"; icon: win.icon("keyboard") }
                Choice {
                    label: "Layout toggle"; key: "keyboard.toggle"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["keyboard.toggle"] : []
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["keyboard.toggle"] : ""
                }
                Text {
                    text: win.cfg && win.cfg.ok ? "Layouts (edit settings.toml to change): " + win.cfg.settings["keyboard.layouts"].join(", ") : ""
                    color: win.dim; font.pixelSize: 13
                }
                SliderRow {
                    label: "Repeat rate"; key: "keyboard.repeat_rate"; from: win.limit("keyboard.repeat_rate", "min"); to: win.limit("keyboard.repeat_rate", "max"); step: win.limit("keyboard.repeat_rate", "step"); decimals: 0; unit: "/s"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["keyboard.repeat_rate"] : 25
                }
                SliderRow {
                    label: "Repeat delay"; key: "keyboard.repeat_delay"; from: win.limit("keyboard.repeat_delay", "min"); to: win.limit("keyboard.repeat_delay", "max"); step: win.limit("keyboard.repeat_delay", "step"); decimals: 0; unit: " ms"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["keyboard.repeat_delay"] : 600
                }
                Toggle {
                    label: "NumLock on at start"; key: "keyboard.numlock"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["keyboard.numlock"] : false
                }

            }
            Page {
                // ---- page: mouse ----
                Heading { text: "Mouse"; icon: win.icon("mouse") }
                SliderRow {
                    label: "Pointer speed"; key: "mouse.speed"; from: win.limit("mouse.speed", "min"); to: win.limit("mouse.speed", "max"); step: win.limit("mouse.speed", "step"); decimals: 2
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["mouse.speed"] : 0
                }
                Choice {
                    label: "Acceleration"; key: "mouse.acceleration"; empty: "default"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["mouse.acceleration"] : []
                    current: win.cfg && win.cfg.ok && win.cfg.settings["mouse.acceleration"] ? win.cfg.settings["mouse.acceleration"] : ""
                }
                Toggle {
                    label: "Natural scrolling"; key: "mouse.natural_scroll"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["mouse.natural_scroll"] : false
                }
                SliderRow {
                    label: "Scroll speed"; key: "mouse.scroll_speed"; from: win.limit("mouse.scroll_speed", "min"); to: win.limit("mouse.scroll_speed", "max"); step: win.limit("mouse.scroll_speed", "step"); decimals: 1; unit: "×"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["mouse.scroll_speed"] : 1
                }
                Toggle {
                    label: "Left-handed"; key: "mouse.left_handed"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["mouse.left_handed"] : false
                }
                Choice {
                    label: "Focus follows"; key: "mouse.focus_follows"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["mouse.focus_follows"] : []
                    current: win.cfg && win.cfg.ok && typeof win.cfg.settings["mouse.focus_follows"] === "string" ? win.cfg.settings["mouse.focus_follows"] : ""
                }
                Text { text: "Focus follows: always = hovering focuses a window; click = only a click does."; color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }

            }
            Page {
                // ---- page: notifications ----
                Heading { text: "Notifications"; icon: win.icon("notifications") }
                Toggle {
                    label: "Do not disturb"; key: "notifications.dnd"
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["notifications.dnd"] === true : false
                }
                Choice {
                    label: "Stay on screen"; key: "notifications.timeout"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["notifications.timeout"] : []
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["notifications.timeout"] : ""
                }
                SliderRow {
                    label: "Opacity"; key: "notifications.opacity"; from: win.limit("notifications.opacity", "min"); to: win.limit("notifications.opacity", "max"); step: win.limit("notifications.opacity", "step"); decimals: 2
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["notifications.opacity"] : 0.9
                }
                Text {
                    text: !(win.cfg && win.cfg.ok) ? "" : (win.cfg.notifications_font_explicit
                          ? "Font: " + win.cfg.settings["notifications.font"] + " (set in settings.toml; used for every character)."
                          : "Font: sans-serif, i.e. Persian in " + win.cfg.settings["fonts.persian"] + " (Fonts section), Latin in the normal font.")
                          + " SUPER+N dismisses all, SUPER+SHIFT+N restores the last, SUPER+ALT+N toggles do not disturb."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }

            }
            Page {
                // ---- page: fonts ----
                Heading { text: "Fonts"; icon: win.icon("fonts") }
                Choice {
                    label: "Persian font"; key: "fonts.persian"
                    model: win.cfg && win.cfg.ok ? win.cfg.choices["fonts.persian"] : []
                    current: win.cfg && win.cfg.ok ? win.cfg.settings["fonts.persian"] : ""
                }
                Text {
                    text: "Used for Persian/Arabic script everywhere (Latin text keeps its font). waybar and mako switch at once; Chrome, Claude Desktop, Kate, Thunar and other open apps need a restart."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }

            }
            }
        }

        // ---- bottom area, shown on every page: warnings, a pending network change (Keep / Revert), the status line ----
        Repeater {
            model: win.cfg && win.cfg.warnings ? win.cfg.warnings : []
            Text { text: "⚠ " + modelData; color: "#ff6b6b"; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
        }

        Rectangle {
            visible: win.netPending !== null
            Layout.fillWidth: true
            implicitHeight: confirmCol.implicitHeight + 24
            color: "#33284a"; radius: 6; border.color: "#7c5cff"
            ColumnLayout {
                id: confirmCol
                anchors.fill: parent; anchors.margins: 12; spacing: 8
                Text {
                    text: "Keep the new network settings? Reverting by itself in " + win.netRemaining + " s."
                    color: win.fg; font.pixelSize: 15; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                Text {
                    text: "Check the network status on the Network page: if a check failed or you lost the connection, press Revert now (or just wait). Closing this window also reverts."
                    color: win.dim; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 10
                    ActionButton { label: "Keep"; enabled: true; onClicked: win.netAnswer("confirm") }
                    ActionButton { label: "Revert now"; enabled: true; onClicked: win.netAnswer("revert") }
                }
            }
        }
        Text {
            text: win.status
            visible: win.status !== ""
            color: win.statusError ? "#ff6b6b" : "#9fd3a8"
            font.pixelSize: 14
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Text { text: "Esc closes this window."; color: win.dim; font.pixelSize: 12 }
    }
}
