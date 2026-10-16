-- Screenshots (grim + slurp, Wayland-native). exec_cmd runs through /bin/sh -c, so pipes work.
-- Print            region -> clipboard (paste with Ctrl+V)
-- SHIFT + Print    region -> annotate in swappy (can save/copy from there)
-- CTRL + Print     whole screen -> ~/Pictures/Screenshots/
hl.bind("Print",          hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]), { description = "Screenshots: Select an area, copy it to the clipboard" })
hl.bind("SHIFT + Print",  hl.dsp.exec_cmd([[grim -g "$(slurp)" - | swappy -f -]]), { description = "Screenshots: Select an area and edit it (swappy)" })
hl.bind("CTRL + Print",   hl.dsp.exec_cmd([[mkdir -p ~/Pictures/Screenshots && grim ~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png && notify-send "Screenshot saved"]]), { description = "Screenshots: Select an area, save it to Pictures/Screenshots" })
