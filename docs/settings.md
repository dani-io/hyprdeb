# settings.toml reference

`~/.config/hyprdeb/settings.toml` is created once from [`config/hyprdeb/settings.toml`](../config/hyprdeb/settings.toml) (every key
is commented out there, with its default and an example) and is never overwritten. Unknown keys and wrong values are errors:
`hyprdeb check` tells you where. Apply a change with `hyprdeb apply`, or use `hyprdeb set SECTION.KEY VALUE`, which edits the
file (comments kept) and applies it.

| Section | Keys | Applied by |
|---|---|---|
| `[[monitors]]` (one block per output) | `match` (`desc:<description>` or an output name such as `DP-1`), `mode`, `position`, `scale`, `disabled` | Hyprland reload |
| `[idle]` | `lock_after`, `screen_off_after` (`"off"` or `90s`, `10m`, `1h`; at least 30 s) | restart of hypridle |
| `[wallpaper]` | `path`, `fit` (`cover`, `contain`, `tile`, `fill`) | restart of hyprpaper |
| `[keyboard]` | `layouts`, `variants`, `toggle` (`caps`, `alt_shift`, `win_space`), `repeat_rate`, `repeat_delay`, `numlock` | Hyprland reload |
| `[mouse]` | `speed`, `acceleration`, `natural_scroll`, `scroll_speed`, `left_handed`, `focus_follows` | Hyprland reload |
| `[notifications]` | `timeout`, `opacity`, `font`, `dnd` | mako reload |
| `[fonts]` | `persian` (an installed family that covers Arabic script; default Vazirmatn) | generated fontconfig file |
| `[network]` | `lan_dns_name`, `internet_check`, `ipv4_method`, `ipv4_address`, `ipv4_gateway`, `dns` | `hyprdeb net apply` (with a 60 s revert) |
| `[vpn]` | `default`, `keep_lan_dns` | `hyprdeb vpn` |
| `[nas.NAME]` | `server`, `share`, `username`, `idle_unmount` (the password is never a setting) | NAS page or `./install.sh --nas` |
| `[printing]` | `printer_name`, `printer_uri`, `driver`, `ppd`, `default` | `./install.sh --printing` ([printing](printing.md)) |

Defaults when a key is absent: lock after 10 minutes, screen off after 15, wallpaper `~/.config/hypr/wallpaper.png` (`cover`),
keyboard **US only**, notifications 5 s at 0.9 opacity. A key that is absent writes nothing, so Hyprland keeps its own default
for it (mouse and keyboard repeat settings, for example).

Layouts must be names from the xkb list (`/usr/share/X11/xkb/rules/evdev.lst`) and the first one must be Latin. With a single
layout the toggle key is ignored and Caps Lock keeps working as Caps Lock.

Commands: `hyprdeb show` (effective values), `hyprdeb get KEY`, `hyprdeb set KEY VALUE...`, `hyprdeb check`, `hyprdeb apply`,
`hyprdeb gui [--page NAME]`, `hyprdeb keys`, `hyprdeb net ...`, `hyprdeb vpn ...`, `hyprdeb nas ...`, `hyprdeb print ...`,
`hyprdeb dnd ...`. Every command has `--help`.
