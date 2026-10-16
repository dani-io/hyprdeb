-- Managed by hyprdeb: this block is rewritten on every install.sh run.
-- Put personal changes ABOVE the "hyprdeb managed" markers, not inside them.
-- Syntax verified on Hyprland 0.55.2 (Debian trixie-backports).
hl.on("hyprland.start", function ()
  hl.exec_cmd("waybar")
  hl.exec_cmd("mako")
  -- mako forgets its modes when it restarts: put do-not-disturb back to what settings.toml says (waits for mako).
  hl.exec_cmd("$HOME/.local/bin/hyprdeb dnd sync")
  -- Clipboard history (text and images). wl-paste sets CLIPBOARD_STATE=sensitive for copies marked with
  -- x-kde-passwordManagerHint, and cliphist 0.5.0 does not store those. Keep at most 200 entries.
  hl.exec_cmd("wl-paste --watch cliphist -max-items 200 store")
  -- Polkit agent (password dialogs for pkexec, flatpak system installs). Debian only ships a systemd user unit
  -- tied to graphical-session.target, which start-hyprland never reaches. Not on PATH, hence the full path.
  hl.exec_cmd("/usr/libexec/hyprpolkitagent")
  -- Bluetooth tray applet. Its XDG autostart entry is ignored by Hyprland, and its systemd user unit is only
  -- D-Bus activated (no WantedBy), so this is the one place it starts.
  hl.exec_cmd("blueman-applet")
end)
