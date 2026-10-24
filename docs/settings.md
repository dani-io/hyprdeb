# settings.toml reference

`~/.config/hyprdeb/settings.toml` is created once from [`config/hyprdeb/settings.toml`](../config/hyprdeb/settings.toml) (every key
is commented out there, with its default and an example) and is never overwritten. Unknown keys and wrong values are errors:
`hyprdeb check` tells you where. Apply a change with `hyprdeb apply`, or use `hyprdeb set SECTION.KEY VALUE`, which edits the
file (comments kept) and applies it.

| Section | Keys | Applied by |
|---|---|---|
| `[[monitors]]` (one block per output) | `match` (`desc:<description>` or an output name such as `DP-1`), `mode`, `position`, `scale`, `disabled` | Hyprland reload |
| `[idle]` | `lock_after`, `screen_off_after` (`"off"` or `90s`, `10m`, `1h`; at least 30 s) | restart of hypridle |
| `[wallpaper]` | `path` (an image, or a folder for a slideshow), `fit` (`cover`, `contain`, `tile`, `fill`), `interval` (slideshow, `10s` to `24h`, default `30m`), `order` (`random`), `lock` (`same`, `default` or an image; default `same`), `lock_blur` (0 to 4, default 2) | restart of hyprpaper (the lock screen reads its file at each lock) |
| `[[wallpaper.monitor]]` (one block per monitor) | `match` (as in `[[monitors]]`), `path`, `fit`, `interval`; whatever is left out comes from `[wallpaper]` | restart of hyprpaper |
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

Wallpaper: formats are png, jpg, jpeg, webp, jxl and bmp, in any letter case (hyprpaper cannot load gif or tiff; a slideshow folder
that contains one gets a warning). A folder is a slideshow of the images directly inside it, in random order; subfolders are not read.
The Wallpaper page of the settings window sets all of this: a monitor selector (the connected monitors by description, plus saved
overrides of monitors that are not connected), a thumbnail grid, the fit (Fill screen = `cover`, Fit, centered = `contain`, Tile,
Stretch = `fill`), the slideshow with its interval, and "Choose file..." / "Choose folder..." (the desktop file chooser). The lock
screen follows the wallpaper by default (blur 2); a slideshow uses its first image by name so the lock screen is the same at every lock.
Per-monitor overrides can be edited by hand or with `hyprdeb wallpaper monitor set MATCH [--path P] [--fit F] [--interval I]` and
`hyprdeb wallpaper monitor clear MATCH`.

Commands: `hyprdeb show` (effective values), `hyprdeb get KEY`, `hyprdeb set KEY VALUE...`, `hyprdeb check`, `hyprdeb apply`,
`hyprdeb gui [--page NAME]`, `hyprdeb keys`, `hyprdeb net ...`, `hyprdeb vpn ...`, `hyprdeb nas ...`, `hyprdeb print ...`,
`hyprdeb dnd ...`. Every command has `--help`.
