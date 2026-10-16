-- Notifications (mako): keys and blur. See config/mako/config and `hyprdeb dnd`.
-- SUPER+SHIFT+N goes through `hyprdeb restore`, not `makoctl restore`: mako 1.10.0 crashes restoring a notification that
-- do-not-disturb hid (see docs/gotchas.md, mako).
-- Free in the Debian defaults and the other fragments (checked with `hyprctl binds -j` on 0.55.2).
hl.bind("SUPER + N", hl.dsp.exec_cmd("makoctl dismiss --all"), { description = "Notifications: Dismiss all" })
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb restore"), { description = "Notifications: Bring back the last one" })
hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb dnd toggle"), { description = "Notifications: Do not disturb on or off" })
-- Blur behind the translucent notification background. mako's layer namespace is "notifications" (`hyprctl layers`).
-- ignore_alpha keeps the fully transparent rounded corners out of the blur.
hl.layer_rule({
    name  = "hyprdeb-notifications-blur",
    match = { namespace = "^notifications$" },
    blur  = true,
    ignore_alpha = 0.3,
})
