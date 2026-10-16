# Recovery: how to go back

Everything below is about the opt-in stages that change how the machine starts or how it reaches the network. Keep a second
way in (another console with `Ctrl+Alt+F3`, or SSH from another computer) before you try any of them.

## Login screen (greetd)

`./install.sh --greeter` installs greetd with the tuigreet text greeter on VT 7 and enables it. **Nothing starts now; it takes
effect at the next boot.** The session command is `/usr/local/bin/hyprdeb-session`, which starts the same Hyprland session as
typing `start-hyprland` in a login shell (it uses an interactive login shell so your `PATH` additions from `.zshrc` still apply)
and logs to `~/.local/state/hyprdeb/session.log`.

If the greeter or the session does not come up:

1. Press `Ctrl+Alt+F3`, log in as your user and run `sudo systemctl disable greetd && sudo reboot`. The text console login and
   `start-hyprland` work as before.
2. If the console does not react, SSH in from another computer and run the same two commands.
3. Read `~/.local/state/hyprdeb/session.log` (from tty3 or over SSH) to see why the session failed.

The `getty@tty1..tty6` units are left alone, so the recovery consoles always exist. Do not run `start-hyprland` on tty1 while a
greetd session is up: that starts a second session. The stage also lowers the kernel console log level
(`/etc/sysctl.d/70-hyprdeb-console.conf`) so that console messages do not print over the greeter; the journal keeps everything.

To remove it for good: `sudo systemctl disable greetd`. The packaged `/etc/greetd/config.toml` was backed up once next to the
new one (`config.toml.bak.TIMESTAMP`).

## NetworkManager

`./install.sh --networkmanager` moves the **wired** uplink from ifupdown + dhcpcd to NetworkManager. It refuses a Wi-Fi uplink
and a connection that is not plain DHCP in `/etc/network/interfaces`.

- **Same address.** The DHCP client identifier NetworkManager sends is the one dhcpcd sends now (`ff` + the last four MAC bytes
  + dhcpcd's DUID), worked out at run time and never stored in the repository. Routers that tie a lease to the client id keep
  giving the same address. Without a dhcpcd DUID the fallback is `duid`, never the MAC. If your router has a *static lease by MAC*,
  look at its lease list after the switch to confirm the address did not change.
- **Rollback timer first.** Before anything changes, a timer is armed (`--nm-timer MIN`, default 10 minutes). The risky part runs as
  its own systemd unit (`hyprdeb-nm-switch`), so a dropped SSH session does not stop it. After the switch, the stage checks the same
  IPv4 address, a gateway that answers ping and the DHCP DNS server in `/etc/resolv.conf`. Any failed check rolls back by itself.
- **Confirm.** In a terminal you are asked `Keep NetworkManager? [y/N]`; no answer in three minutes is a rollback. Without a
  terminal the timer stays armed: `sudo systemctl stop hyprdeb-nm-rollback.timer` keeps NetworkManager.
- **By hand.** `./install.sh --networkmanager-rollback` (or `sudo hyprdeb-nm rollback`) restores `/etc/network/interfaces` from
  `/etc/network/interfaces.hyprdeb-pre-nm`, disables NetworkManager and brings the interface up with ifupdown again. The log of
  a switch is `journalctl -u hyprdeb-nm-switch`.
- **Cost.** Boot is a little slower with NetworkManager (about 0.9 s on the author's machine).

After the switch, an existing `hyprdeb-<if>` NetworkManager profile belongs to you: the installer does not rewrite it. `hyprdeb net
apply` changes IPv4 settings through it and arms an automatic revert first (60 s to confirm; see
[architecture](architecture.md#hyprdeb-net-guard-network-revert)).

## NAS shares

Nothing is mounted at boot and nothing is in `/etc/fstab`. To undo a share, remove it on the NAS page (or `hyprdeb nas remove
NAME`): it stops the mount, removes the two systemd units, the password file `/etc/hyprdeb/nas-NAME.credentials` and an empty
`/mnt/NAME`. A share that is in use is refused, never forced. To remove the helper itself:

```bash
sudo systemctl disable --now hyprdeb-nas.socket
sudo rm /etc/systemd/system/hyprdeb-nas.socket /etc/systemd/system/hyprdeb-nas@.service \
        /usr/local/sbin/hyprdeb-nas /usr/share/polkit-1/actions/org.hyprdeb.nas.policy
sudo systemctl daemon-reload
```

## Printing, NVIDIA, logind

- **Printing:** `lpadmin -x QUEUE` removes the queue; `sudo systemctl disable --now cups` stops CUPS. The packages stay.
- **NVIDIA:** `/etc/modprobe.d/nvidia-drm.conf` and `/etc/modprobe.d/nvidia-power.conf` hold the options; remove them and run
  `sudo update-initramfs -u` to go back, then `sudo apt purge 'nvidia-*'` if you want the driver gone.
- **logind:** `/etc/systemd/logind.conf.d/hyprdeb.conf` only raises `InhibitDelayMaxSec`; delete it and reboot.

## Configuration backups

`hyprland.lua` gets a timestamped copy (`hyprland.lua.bak.DATE`) before its managed block changes. Other managed files are
overwritten by design (they say `hyprdeb managed` on top). Your `settings.toml` is created once and never overwritten; a change
made through hyprdeb keeps a single `settings.toml.bak` of the first state.
