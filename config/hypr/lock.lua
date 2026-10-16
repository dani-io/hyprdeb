-- Screen lock, idle daemon and wallpaper (configs in ~/.config/hypr/hypr{lock,idle,paper}.conf).
-- SUPER + L locks now. hyprdeb-lock (bin/, installed to ~/.local/bin) asks the compositor whether the session
-- is locked, removes stray hyprlocks that hold no lock, and switches to layout 0 (us) before locking.
hl.bind("SUPER + L", hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb-lock"), { description = "System: Lock the screen" })

-- If hyprlock crashes the session stays locked (red screen). This lets a new hyprlock take over;
-- hyprdeb-lock starts one when the session is locked but no hyprlock of ours runs. From a TTY:
--   hyprctl -i 0 dispatch 'hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb-lock")'
hl.config({ misc = { allow_session_lock_restore = true } })

-- hyprland.start fires once per session (not on reload). No pgrep guard: it is not per-session and
-- would skip the daemons when another Hyprland session already runs them. The packages also enable
-- systemd user units; they only start if graphical-session.target is reached (start-hyprland does not).
hl.on("hyprland.start", function ()
  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprpaper")
end)
