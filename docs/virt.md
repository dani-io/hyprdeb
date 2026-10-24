# Local virtual machines (`--virt`)

`./install.sh --virt` sets up light test virtual machines with **libvirt** and **virt-manager**, using the system daemon
(`qemu:///system`) and libvirt's default **NAT** network. No bridge to your LAN is created (a bridge would change your uplink;
see [recovery](recovery.md#networkmanager)).

## What it does

| Step | Detail |
|---|---|
| Packages (`packages/virt.list`, `--no-install-recommends`) | `libvirt-daemon-system`, `libvirt-clients`, `virt-manager`, `dnsmasq-base` (DHCP/DNS for the NAT network), `swtpm` + `swtpm-tools` (emulated TPM, e.g. Windows 11), `gir1.2-spiceclientgtk-3.0` (virt-manager's console) and QEMU itself (`qemu-system-x86`, `qemu-utils`, `ovmf`, `qemu-system-modules-spice`). About 60 packages, ~14 MB to download. |
| Daemon | `libvirtd.service` and its sockets are enabled by the packages; the stage makes sure the service runs. `libvirt-guests.service` (enabled by the package) only acts on running guests. |
| Group | You are added to `libvirt` (the daemon's socket is `root:libvirt 0770`). **It applies after a full log out and in**; until then use `sudo virsh -c qemu:///system ...` or `sudo virt-install ...`. virt-manager cannot connect without the group. |
| Guests at host shutdown | `/etc/default/libvirt-guests` gets one managed block: `ON_BOOT=ignore`, `ON_SHUTDOWN=shutdown`, `SHUTDOWN_TIMEOUT=30`. Debian's default suspends running guests (managed save) when the host shuts down, which slows the shutdown and writes a RAM-sized file per guest; test VMs are shut down instead, and a guest that has not stopped after 30 s is powered off. The packaged file is kept once as `libvirt-guests.bak`. |
| Network `default` | `virbr0`, 192.168.122.0/24, DHCP .2–.254, NAT. The stage makes sure it exists, is **active** and **autostart** (`virsh net-start` / `net-autostart` if needed). |
| `~/.config/libvirt/libvirt.conf` | written once if missing: `uri_default = "qemu:///system"`, so plain `virsh` talks to the system daemon. virt-manager already uses it. Never overwritten. |

Running it again changes nothing. `./install.sh --only virt --dry-run` shows the commands first.

## What libvirt does to the host

- While the `default` network runs, libvirt turns on **`net.ipv4.ip_forward`** and adds its **own firewall rules** for `virbr0`
  (nftables or iptables, whichever libvirt picks). The machine becomes a router for the guests; the rules limit that to
  `virbr0`.
- Guest traffic leaves through the host's **default route**. When a VPN tunnel is on (`hyprdeb vpn on`), guests go **through the
  VPN** too; with a full-tunnel profile there is no way for a guest to reach the internet outside it.
- `192.168.122.0/24` must not overlap a network you use. hyprdeb's network checks pick the uplink by the default route, so
  `virbr0` is ignored by `hyprdeb net status` and `net apply`.
- NetworkManager lists `virbr0` as an external device; it does not manage it.

## A first test VM

A tiny guest with no operating system boots to the UEFI shell and proves that KVM, OVMF, the network and the console work:

```bash
sudo virt-install --connect qemu:///system --name hyprdeb-test --memory 512 --vcpus 1 \
     --disk size=1,format=qcow2 --import --boot uefi --osinfo detect=off,require=off \
     --graphics spice --network network=default --noautoconsole
virsh -c qemu:///system list --all          # (sudo until the libvirt group applies)
virt-manager                                # open it from the menu or a terminal, double-click the guest for its console
# a guest with no operating system ignores `shutdown`, so power it off:
sudo virsh -c qemu:///system destroy hyprdeb-test
sudo virsh -c qemu:///system undefine hyprdeb-test --nvram --remove-all-storage
```

For a real guest, create it in virt-manager (*File ▸ New Virtual Machine*) from an ISO; Windows 11 needs UEFI with Secure Boot
firmware and a TPM 2.0 (both are options in the wizard's last step when `ovmf` and `swtpm` are installed).

## Under Hyprland

virt-manager is a GTK3 program and runs natively on Wayland. Its main window and the console open tiled and usable, so **no window
rule is needed**. Clicking into a guest's console **grabs the keyboard**: the `SUPER` combinations then go to the guest, not to
Hyprland (checked with a SeaBIOS guest), and *Ctrl+Alt* releases the grab so Hyprland's shortcuts work again.

## Undo

```bash
sudo virsh -c qemu:///system net-destroy default && sudo virsh -c qemu:///system net-autostart default --disable
sudo apt purge virt-manager 'libvirt-*' swtpm swtpm-tools dnsmasq-base      # keeps QEMU
sudo cp /etc/default/libvirt-guests.bak /etc/default/libvirt-guests          # if you want Debian's guest handling back
```

`net.ipv4.ip_forward` goes back to 0 at the next boot. Your guests' disks stay in `/var/lib/libvirt/images/` until you remove
them.
