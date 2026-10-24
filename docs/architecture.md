# Architecture

hyprdeb is a repository that a machine is deployed *from*. The repository is the source of truth; nothing is kept in a
database or a ledger. Every installer stage looks at the real state of the machine and only changes what differs.

## Installer: stages

`install.sh` has a stage registry (`STAGE_TABLE`): `name | function | needs sudo | opt-in flag | purpose`.

- A normal run executes the default stages in table order; opt-in stages (`--nvidia`, `--nas`, `--printing`, ...) run only
  when their flag is given or when named with `--only`.
- `--only a,b` runs those stages in the normal order; `packages` and `user` are groups. `--config-only` is `--only user`.
- Stages that need root say so in `--list-stages`; sudo is only asked for when a selected stage needs it.
- `--dry-run` prints each command (`[dry-run] sudo ...`) instead of running it. Idempotent stages compare file content
  (`deploy_file`, `deploy_root_file`) and report only real changes.
- Files that hyprdeb owns start with `hyprdeb managed` and are overwritten; files that mix your text and ours (such as
  `~/.config/hypr/hyprland.lua`) get a block between `-- >>> hyprdeb managed >>>` and `-- <<< hyprdeb managed <<<`, and
  nothing outside it is touched. A differing file is backed up once (`.bak`) before the first overwrite.

## Settings: one file in, generated files out

```
~/.config/hyprdeb/settings.toml   (yours; created once from config/hyprdeb/settings.toml)
        |  hyprdeb check / apply / set  (bin/hyprdeb, validates everything, unknown keys are errors)
        v
~/.config/hypr/hyprdeb-settings.lua   monitors, keyboard, mouse (hl.config blocks)
~/.config/hypr/hyprdeb-idle.conf      hypridle timeouts
~/.config/hypr/hyprdeb-paper.conf     hyprpaper wallpaper blocks (all monitors, and one per monitor override)
~/.config/hypr/hyprdeb-lock.conf      hyprlock background blocks, sourced by hyprlock.conf
~/.config/mako/hyprdeb-settings       notification timeout, opacity, font
~/.config/fontconfig/conf.d/60-hyprdeb-persian.conf   one Arabic-script family for the whole desktop
```

`hyprdeb apply` writes the files and reloads or restarts only what changed (Hyprland reload, hypridle, hyprpaper, mako).
`hyprdeb set KEY VALUE` and the settings window edit `settings.toml` with `tomlkit`, which keeps your comments.
Defaults live in `bin/hyprdeb`; an absent key writes nothing, so Hyprland keeps its own default for it.

The CLI is one Python file (standard library plus `python3-tomlkit` and `python3-gi`). It is installed to
`~/.local/bin/hyprdeb`; the settings window (`config/hyprdeb/gui/shell.qml`, Quickshell) never writes anything itself: it
runs `hyprdeb ... --json` and shows the result. A password typed in the window goes to the CLI on stdin, never on a
command line.

## Quickshell windows

`hyprdeb gui` starts the settings window; `hyprdeb keys` and `SUPER+/` show the live shortcut list (read from
`hyprctl binds`). The windows are loaded from `~/.local/share/hyprdeb/gui/`. Hot reload is off (see
[gotchas](gotchas.md#quickshell)), so after an update close and reopen the window.

## Root helpers

Two small programs run as root, both with a narrow, validated interface and no shell.

### `hyprdeb-nas` (NAS shares)

Started per request by a socket-activated, sandboxed systemd unit (`hyprdeb-nas.socket`, `hyprdeb-nas@.service`):

1. The client (the CLI, called by the settings window) connects to `/run/hyprdeb-nas.sock` (group `sudo`) and sends **one
   JSON line** of at most 16 KiB, read within 30 s.
2. The helper validates every field with strict patterns (share name, server, share, user name, password, idle time) and
   refuses unknown fields before it does anything else.
3. It asks polkit through `pkcheck` for the action `org.hyprdeb.nas.manage` (`auth_admin_keep`: an administrator password
   dialog, which the desktop's polkit agent shows). The subject is the connecting process: pid and uid come from `SO_PEERCRED`,
   the start time from `/proc/PID/stat` (checked again after the answer), so a recycled pid cannot borrow the approval.
   `pkcheck --detail` is refused to normal users, which is why the helper (root) makes the call.
4. Only then it writes `/etc/hyprdeb/nas-NAME.credentials` (root, 0600, atomic) and the `mnt-NAME.mount` and
   `.automount` units (`/etc/systemd/system`, options `vers=3.0`, `_netdev`, `nofail`), enables the automount, never the mount.
   The mount point is always `/mnt/NAME`; a stored password is only used for the same server and user name.

The unit runs with no capabilities, `ProtectSystem=strict` (writes only `/etc/hyprdeb`, `/etc/systemd/system` and `/mnt`),
private `/tmp` and `/dev`, a system-call filter, restricted address families (Unix, IPv4, IPv6, netlink) and a 400 s runtime
limit. `systemd-analyze security` rates it 1.8 (OK). `install.sh --nas` can also run the helper directly through
`sudo` (real root, stdin is not the socket); that path has no polkit step because sudo already asked, and it is the only one
that takes a `uid` field for the mount owner, which the socket path refuses.

### `hyprdeb-net-guard` (network revert)

`hyprdeb net apply` writes a small token (`/run/hyprdeb-net/pending.json`, writable by members of `netdev`) **before** changing an
address, and `hyprdeb-net-guard.path` starts the guard. If the change is not confirmed within the deadline, the guard (root)
restores the old settings. The token is data: the guard parses and validates every field, accepts only `hyprdeb-<if>` profile
names, calls `nmcli` with an argument list and never a shell, and refuses a token that is a symlink, too large or not owned
by root or `netdev`. It survives a dead terminal, window or session.

## The managed `hyprland.lua` block

Debian ships a default `/usr/share/hypr/hyprland.lua`. When you have no `~/.config/hypr/hyprland.lua` the installer copies that
file, then appends **one block** between the markers `-- >>> hyprdeb managed >>>` and `-- <<< hyprdeb managed <<<`: the
concatenation of `config/hypr/*.lua` (shortcuts, input, lock, menu, autostart, ...). Every run rewrites that block only; an
existing file is backed up with a timestamp before it changes. The generated `hyprdeb-settings.lua` is loaded with `pcall`, so a
broken generated file shows a notification instead of stopping the rest of your configuration.

Put personal changes **above** the markers. Delete the block and nothing of hyprdeb is left in the Hyprland configuration (the
one exception: the Debian default launches Dolphin on `SUPER+E`, and a single line above the block is rewritten to Thunar).
