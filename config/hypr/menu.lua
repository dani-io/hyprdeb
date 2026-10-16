-- Quick menu (fuzzel): power, Bluetooth, audio and a few settings. See `hyprdeb menu`.
-- SUPER + Escape was free in the Debian defaults and in the other fragments (checked with `hyprctl binds -j`);
-- SUPER + Space is deliberately avoided because keyboard.toggle = "win_space" would collide with it.
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/hyprdeb menu"), { description = "System: Quick menu (power, Bluetooth, audio, settings)" })
