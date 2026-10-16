-- Clipboard history picker (cliphist + fuzzel). The Debian default binds SUPER+V to toggle floating; that bind is
-- outside the managed block, so it is removed here with hl.unbind and floating moves to SUPER+F.
--   SUPER + V          pick an entry from the history (text or image) and copy it again
--   SUPER + SHIFT + V  wipe the whole history
--   SUPER + F          toggle floating (was SUPER + V)
-- Esc in fuzzel copies nothing (the empty selection is not decoded).
hl.unbind("SUPER + V")
hl.bind("SUPER + V", hl.dsp.exec_cmd([[sel="$(cliphist list | fuzzel --dmenu --prompt 'clipboard> ')" && [ -n "$sel" ] && printf '%s' "$sel" | cliphist decode | wl-copy]]), { description = "Clipboard: Pick from the history and copy it" })
hl.bind("SUPER + SHIFT + V", hl.dsp.exec_cmd([[cliphist wipe && notify-send "Clipboard history cleared"]]), { description = "Clipboard: Clear the history" })
hl.bind("SUPER + F", hl.dsp.window.float({ action = "toggle" }), { description = "Windows: Toggle floating" })
