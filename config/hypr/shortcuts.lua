-- Keyboard shortcuts list (`hyprdeb keys`, window: `hyprdeb gui --page shortcuts`). Read-only: it never changes a bind.
-- SUPER + slash was free in the Debian defaults and the other fragments (checked with `hyprctl binds -j` on 0.55.2). The keysym
-- "slash" fires with the English and the Persian layout alike (tested); "code:61" does too but hyprctl reports it as an empty key,
-- which the list could not show.
hl.bind("SUPER + slash", hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb gui --page shortcuts"), { description = "System: Keyboard shortcuts (this list)" })
