#!/usr/bin/env bash
# hyprdeb installer: Hyprland desktop on Debian 13 (trixie), reproducible from this repo.
# Re-runnable: every stage checks current state before changing anything.
#
#   ./install.sh                  full install (system stages need sudo)
#   ./install.sh --dry-run        print what would run, change nothing
#   ./install.sh --nvidia         also install the NVIDIA proprietary driver
#   ./install.sh --no-chrome      skip Google Chrome (proprietary, Google apt repo)
#   ./install.sh --vscode         also install Visual Studio Code (proprietary, Microsoft apt repo)
#   ./install.sh --cowork         also set up the prerequisites of Claude Desktop's Cowork VM (QEMU, kvm group, vhost_vsock)
#   ./install.sh --greeter        also set up the greetd login screen (tuigreet); opt-in, takes effect at the next boot; read docs/recovery.md first
#   ./install.sh --nas            also set up the NAS shares from [nas.NAME] in settings.toml (CIFS, systemd automount, root helper; asks for new passwords)
#   ./install.sh --printing       also set up printing: CUPS and the queue from [printing] in settings.toml (driverless IPP, a PPD you have, or Canon's own driver .deb installed first: see docs/printing.md)
#   ./install.sh --flatpak        also install Flatpak with the Flathub remote and the apps in packages/flatpak-apps.list (system-wide)
#   ./install.sh --networkmanager  also move the wired uplink from ifupdown/dhcpcd to NetworkManager (opt-in; rollback timer armed, read docs/recovery.md first)
#   ./install.sh --networkmanager-rollback  undo it: ifupdown/dhcpcd again, NetworkManager disabled
#   ./install.sh --nm-timer MIN   minutes before the automatic rollback fires unless confirmed (default 10, 0 = none)
#   ./install.sh --virtualcam     also set up the OBS Virtual Camera (v4l2loopback via DKMS)
#   ./install.sh --config-only    only (re)deploy user config into $HOME, no sudo (same as --only user)
#   ./install.sh --timezone Europe/Berlin
#   ./install.sh --only a,b       run only these stages (in the normal order); naming an opt-in stage selects it for this run
#   ./install.sh --list-stages    the stage names, groups (packages, user), sudo need and opt-in flag
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODENAME="trixie"
DRY=0; NVIDIA=0; CONFIG_ONLY=0; CHROME=1; NO_CHROME_GIVEN=0; ONLY=""; LIST_STAGES=0; VSCODE=0; COWORK=0; NAS=0; PRINTING=0; GREETER=0; FLATPAK=0; VIRTUALCAM=0; NETWORKMANAGER=0; NM_ROLLBACK=0; NM_TIMER=10; TZ_WANT=""
BASE_LUA="${HYPRDEB_BASE_LUA:-/usr/share/hypr/hyprland.lua}"   # Debian-shipped default
CONF_DIR="${HOME}/.config/hypr"
BEGIN="-- >>> hyprdeb managed >>>"
END="-- <<< hyprdeb managed <<<"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --nvidia) NVIDIA=1 ;;
    --no-chrome) CHROME=0; NO_CHROME_GIVEN=1 ;;
    --vscode) VSCODE=1 ;;
    --cowork) COWORK=1 ;;
    --nas) NAS=1 ;;
    --printing) PRINTING=1 ;;
    --greeter) GREETER=1 ;;
    --flatpak) FLATPAK=1 ;;
    --virtualcam) VIRTUALCAM=1 ;;
    --networkmanager) NETWORKMANAGER=1 ;;
    --networkmanager-rollback) NM_ROLLBACK=1 ;;
    --nm-timer) shift; NM_TIMER="${1:-}"; [[ "$NM_TIMER" =~ ^[0-9]+$ ]] && [ "$NM_TIMER" -le 120 ] || die "--nm-timer needs a number of minutes from 0 to 120" ;;
    --config-only) CONFIG_ONLY=1 ;;
    --only) shift; [ -n "${1:-}" ] || die "--only needs a list of stage names (see --list-stages)"; ONLY="${ONLY:+$ONLY,}$1" ;;
    --list-stages) LIST_STAGES=1 ;;
    --timezone) shift; TZ_WANT="${1:-}"; [ -n "$TZ_WANT" ] || die "--timezone needs a value" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# Run a command, or just print it in dry-run mode.
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi
sys() { run $SUDO "$@"; }   # system-level command

# Read a package list: strip comments and blank lines.
pkgs() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$REPO/packages/$1.list"; }

preflight() {
  log "Preflight"
  [ -r /etc/os-release ] || die "no /etc/os-release"
  . /etc/os-release
  [ "${ID:-}" = "debian" ] && [ "${VERSION_CODENAME:-}" = "$CODENAME" ] \
    || die "this needs Debian 13 (trixie); found ${PRETTY_NAME:-unknown}"
  if [ -n "$SUDO" ] && [ "$DRY" = 0 ]; then
    sudo -n true 2>/dev/null || sudo -v || die "sudo is required (is $USER in the sudo group?)"
  fi
}

stage_sources() {
  log "APT sources: contrib/non-free components and trixie-backports"
  local list=/etc/apt/sources.list
  # Legacy one-line format
  # The pattern is anchored to end-of-line, so lines that already have contrib are untouched.
  if [ -f "$list" ] && grep -qE '^deb .* main( non-free-firmware)?$' "$list"; then
    sys sed -i -E '/^deb .*(deb|security)\.debian\.org/ s/ main( non-free-firmware)?$/ main contrib non-free non-free-firmware/' "$list"
  fi
  # deb822 format
  if [ -f /etc/apt/sources.list.d/debian.sources ] && ! grep -q 'contrib' /etc/apt/sources.list.d/debian.sources; then
    sys sed -i -E 's/^Components: .*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
  fi
  # Backports: skip if any file already declares it (avoids "configured multiple times")
  if ! grep -rqs "${CODENAME}-backports" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    if [ "$DRY" = 1 ]; then
      echo "  [dry-run] write /etc/apt/sources.list.d/hyprdeb-backports.sources"
    else
      $SUDO tee /etc/apt/sources.list.d/hyprdeb-backports.sources >/dev/null <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    fi
  fi
  sys apt-get update
}

# The four package lists are four stages (same commands as the old single stage_packages).
stage_base() {
  log "Packages: base"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs base)
}

stage_desktop() {
  # No implicit apt update or sources here: a run of this stage alone must not half-work without the backports source.
  if ! stage_selected sources && ! grep -rqs "${CODENAME}-backports" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
    die "${CODENAME}-backports is not configured: run ./install.sh --only sources,desktop once"
  fi
  log "Packages: desktop (backports preferred where newer)"
  # shellcheck disable=SC2046
  sys apt-get install -y -t "${CODENAME}-backports" $(pkgs desktop)
}

stage_shell() {
  log "Packages: shell tools"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs shell)
}

stage_apps() {
  log "Packages: apps"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs apps)
}

stage_chrome() {
  [ "$CHROME" = 1 ] || return 0
  log "Google Chrome (official apt repo, amd64)"
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then warn "Chrome is amd64 only; skipping"; return 0; fi
  local key=/usr/share/keyrings/google-chrome.gpg src=/etc/apt/sources.list.d/google-chrome.sources
  if [ ! -f "$key" ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] fetch Google signing key -> $key"
    else curl -fsS --max-time 30 https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | $SUDO tee "$key" >/dev/null \
      || { warn "could not fetch the Google key (network?); skipping Chrome"; $SUDO rm -f "$key"; return 0; }; fi
  fi
  if [ ! -f "$src" ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] write $src"
    else $SUDO tee "$src" >/dev/null <<EOF
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: $key
EOF
    fi
  fi
  # Stop the package from adding its own duplicate google-chrome.list on install.
  if [ ! -f /etc/default/google-chrome ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] write /etc/default/google-chrome"
    else echo 'repo_add_once="true"' | $SUDO tee /etc/default/google-chrome >/dev/null; fi
  fi
  sys apt-get update
  sys apt-get install -y google-chrome-stable
}

# Root-owned managed file: same rules as deploy_file (marker, one backup of an unmanaged file), via sudo.
# Returns 0 if the file was (or in dry-run would be) written, 1 if already identical.
# A 4th argument "rootread" is for files an ordinary user cannot even stat (a root-only directory, e.g. NetworkManager's profiles):
# every look at the existing file then goes through sudo (in a dry-run only `sudo -n`, so it never prompts; unreadable = "would write").
deploy_root_file() {
  local src="$1" dst="$2" mode="${3:-644}" rd=""
  if [ "${4:-}" = rootread ]; then
    if [ "$DRY" = 1 ]; then rd="sudo -n"; elif [ -n "$SUDO" ]; then rd="$SUDO"; fi
    [ "$(id -u)" -ne 0 ] || rd=""
  fi
  if $rd test -f "$dst" 2>/dev/null && $rd cmp -s "$src" "$dst" 2>/dev/null; then return 1; fi
  if [ "$DRY" = 1 ]; then echo "  [dry-run] deploy $(basename "$src") -> $dst"; return 0; fi
  if $rd test -f "$dst" && ! $rd grep -q 'hyprdeb managed' "$dst"; then
    $SUDO cp "$dst" "$dst.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  $SUDO install -D -m "$mode" "$src" "$dst"
  log "$dst updated"
}

stage_nvidia() {
  [ "$NVIDIA" = 1 ] || return 0
  log "NVIDIA proprietary driver"
  if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    die "Secure Boot is enabled; the DKMS module would not load. Disable it or enroll a MOK first."
  fi
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs nvidia)
  local initramfs=0 f
  if [ ! -f /etc/modprobe.d/nvidia-drm.conf ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] write /etc/modprobe.d/nvidia-drm.conf"
    else echo 'options nvidia-drm modeset=1 fbdev=1' | $SUDO tee /etc/modprobe.d/nvidia-drm.conf >/dev/null; fi
    initramfs=1
  fi
  if deploy_root_file "$REPO/config/modprobe/nvidia-power.conf" /etc/modprobe.d/nvidia-power.conf; then initramfs=1; fi
  # VRAM save/restore around sleep (from nvidia-suspend-common); only effective with PreserveVideoMemoryAllocations=1.
  for f in nvidia-suspend nvidia-resume nvidia-hibernate; do
    if [ "$(systemctl is-enabled "$f.service" 2>/dev/null)" != enabled ]; then sys systemctl enable "$f.service"; fi
  done
  if [ "$initramfs" = 1 ]; then
    sys update-initramfs -u
    warn "NVIDIA module options changed: reboot for them to take effect."
  fi
}

stage_vscode() {
  [ "$VSCODE" = 1 ] || return 0
  log "Visual Studio Code (official Microsoft apt repo, amd64)"
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then warn "VS Code repo is set up for amd64 only; skipping"; return 0; fi
  local key=/usr/share/keyrings/microsoft.gpg src=/etc/apt/sources.list.d/vscode.sources changed=0
  if [ ! -f "$key" ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] fetch Microsoft signing key -> $key"
    else curl -fsS --max-time 30 https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | $SUDO tee "$key" >/dev/null \
      || { warn "could not fetch the Microsoft key (network?); skipping VS Code"; $SUDO rm -f "$key"; return 0; }; fi
    changed=1
  fi
  # Fingerprints published at https://packages.microsoft.com/keys/README: microsoft.asc (signs the code repo, checked
  # 2026-10-09) and microsoft-2025.asc (the key for newly created repos). Anything else: refuse.
  if [ -f "$key" ]; then
    local fp bad=0
    for fp in $(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1=="fpr"{print $10}'); do
      case "$fp" in
        BC528686B50D79E339D3721CEB3E94ADBE1229CF|AA86F75E427A19DD33346403EE4D7792F748182B) ;;
        *) bad=1 ;;
      esac
    done
    if [ "$bad" = 1 ] || [ -z "${fp:-}" ]; then
      warn "$key does not hold Microsoft's published key fingerprint; skipping VS Code (remove the file to refetch)"
      return 0
    fi
  fi
  if [ ! -f "$src" ]; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] write $src"
    else $SUDO tee "$src" >/dev/null <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64
Signed-By: $key
EOF
    fi
    changed=1
  fi
  # Stop the package from adding its own vscode.list (a duplicate of the deb822 file above): set before installing.
  if ! debconf-show code 2>/dev/null | grep -q 'code/add-microsoft-repo: false'; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] debconf-set-selections: code code/add-microsoft-repo boolean false"
    else echo 'code code/add-microsoft-repo boolean false' | $SUDO debconf-set-selections; fi
  fi
  if [ "$changed" = 1 ]; then sys apt-get update; fi
  sys apt-get install -y code
}

# Claude Desktop's Cowork VM on Linux (code.claude.com/docs/en/desktop-linux): QEMU + OVMF + virtiofsd, access to /dev/kvm
# (group kvm) and the vhost_vsock module. claude-desktop itself is not installed here.
stage_cowork() {
  [ "$COWORK" = 1 ] || return 0
  log "Cowork prerequisites (QEMU, kvm group, vhost_vsock)"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs cowork)
  if [ ! -e /dev/kvm ]; then
    warn "/dev/kvm does not exist (no hardware virtualisation, or no nested KVM in a VM): Cowork cannot run on this machine"
  fi
  if getent group kvm >/dev/null && ! getent group kvm | cut -d: -f4 | tr ',' '\n' | grep -qx "$USER"; then
    sys usermod -aG kvm "$USER"
    warn "$USER $([ "$DRY" = 1 ] && echo "would be added" || echo "was added") to group kvm: it applies after a full re-login (start-hyprland from the same TTY keeps the old groups)"
  fi
  deploy_root_file "$REPO/config/modules-load/vhost_vsock.conf" /etc/modules-load.d/vhost_vsock.conf || true
  if [ "$DRY" = 1 ]; then
    if [ -d /sys/module/vhost_vsock ]; then echo "  [dry-run] vhost_vsock already loaded"; else echo "  [dry-run] modprobe vhost_vsock"; fi
  elif [ ! -d /sys/module/vhost_vsock ]; then
    sys modprobe vhost_vsock || warn "could not load vhost_vsock (see: dmesg)"
  fi
}

# greetd + tuigreet as the login screen. Opt-in and reversible: `sudo systemctl disable greetd` + reboot = tty1 login as before.
# The package postinst only ENABLES greetd (it does not start it under systemd), so nothing changes until the next boot; this stage
# then writes our config in the same run (a run that died in between would leave the packaged default: a bare login prompt on tty7,
# while tty1..tty6 getty keep working). Never starts greetd here: that would switch the screen to the greeter and end this desktop.
stage_greeter() {
  [ "$GREETER" = 1 ] || return 0
  log "Login screen (greetd + tuigreet)"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs greeter)
  deploy_root_file "$REPO/bin/hyprdeb-session" /usr/local/bin/hyprdeb-session 755 || true
  deploy_root_file "$REPO/config/greetd/pam-greetd" /etc/pam.d/greetd || true
  deploy_root_file "$REPO/config/greetd/config.toml" /etc/greetd/config.toml || true
  # Console messages (level ERR) would be printed over the greeter on its text VT; lower the console level (journal/dmesg keep everything).
  # systemd-sysctl applies it early in boot, long before greetd; applied now too, so the running console is quiet as well.
  if deploy_root_file "$REPO/config/sysctl/70-hyprdeb-console.conf" /etc/sysctl.d/70-hyprdeb-console.conf; then
    [ "$DRY" = 1 ] || sys /usr/sbin/sysctl -q -p /etc/sysctl.d/70-hyprdeb-console.conf
  fi
  if [ "$DRY" = 0 ]; then
    command -v tuigreet >/dev/null 2>&1 || die "tuigreet is not installed: greetd was left as it is (not enabling anything)"
    [ -x /usr/local/bin/hyprdeb-session ] || die "/usr/local/bin/hyprdeb-session is missing"
    python3 -c 'import sys,tomllib; tomllib.load(open("/etc/greetd/config.toml","rb"))' || die "/etc/greetd/config.toml is not valid TOML"
    systemctl is-enabled --quiet greetd.service 2>/dev/null || sys systemctl enable greetd.service
  else
    echo "  [dry-run] enable greetd.service (never started here)"
  fi
  # getty@tty1..tty6 stay as they are: Ctrl+Alt+F3 is the recovery console.
  cat <<'EOT'

  The login screen takes effect at the NEXT BOOT (greetd was not started now).
  Recovery, if the greeter or the session does not come up:
    1. Ctrl+Alt+F3, log in as your user, then:  sudo systemctl disable greetd && sudo reboot
       (tty1 then shows the normal login again; start-hyprland as before)
    2. No keyboard response on the VT: ssh in from another machine and run the same two commands.
  Do not run start-hyprland on tty1 while a greetd session is up (that would start a second session).
  The session log is ~/.local/state/hyprdeb/session.log (read it from tty3 or over ssh).
EOT
}

# Move the wired uplink from ifupdown + dhcpcd to NetworkManager. Read docs/recovery.md first.
# The DHCP client-id NM sends is the one dhcpcd sends now: ff + the last 4 bytes of the MAC (IAID) + dhcpcd's DUID. It is derived here, at run
# time, and never stored in the repo. Without a dhcpcd DUID the fallback is "duid", never "mac" (the router has a different lease for 01:<MAC>).
# The risky part runs as its own systemd unit (survives a dropped ssh session) with an automatic rollback timer armed first.
NM_PROFILE_DIR=/etc/NetworkManager/system-connections
NM_MARK='# hyprdeb managed (NetworkManager)'

nm_uplink() { # interface of the default route with the lowest metric
  ip route show default | awk '{m=0; d=""; for(i=1;i<=NF;i++){if($i=="metric")m=$(i+1); if($i=="dev")d=$(i+1)} if(d!="") print m, d}' | sort -n | awk 'NR==1{print $2}'
}

nm_client_id() { # iface -> prints the value for ipv4.dhcp-client-id; notes go to stderr
  local iface="$1" mac raw norm
  mac="$(cat "/sys/class/net/$iface/address")"
  if [ -n "$SUDO" ]; then raw="$(sudo -n cat /var/lib/dhcpcd/duid 2>/dev/null || true)"; else raw="$(cat /var/lib/dhcpcd/duid 2>/dev/null || true)"; fi
  if [ -z "$raw" ] && [ -n "$SUDO" ] && [ "$DRY" = 0 ]; then raw="$($SUDO cat /var/lib/dhcpcd/duid 2>/dev/null || true)"; fi
  norm="$(tr 'A-F' 'a-f' <<<"$raw" | tr -d '[:space:]')"
  if [[ "$norm" =~ ^[0-9a-f]{12,}$ ]] && (( ${#norm} % 2 == 0 )); then norm="$(sed 's/../&:/g; s/:$//' <<<"$norm")"; fi
  if [[ "$norm" =~ ^([0-9a-f]{2}:){5,}[0-9a-f]{2}$ ]]; then
    echo "ff:$(awk -F: '{print $3":"$4":"$5":"$6}' <<<"$mac"):$norm"
  elif [ "$DRY" = 1 ] && [ -z "$raw" ]; then
    echo "(derived at run time: dhcpcd's DUID is root-only; run 'sudo -v' and repeat the dry-run to see the value)" >&2
    echo "ff:<last 4 MAC bytes>:<dhcpcd DUID>"
  else
    warn "no usable dhcpcd DUID in /var/lib/dhcpcd/duid: using client-id 'duid' (NetworkManager's own DUID); the router will see a NEW client-id" >&2
    echo "duid"
  fi
}

# After a rollback unit has ended: dhcpcd must still be there (it once died together with the transient unit that started it).
nm_check_dhcpcd() { # iface
  local n a1 a2
  sleep 10
  n="$(pgrep -x dhcpcd | wc -l)"
  a1="$(ip -4 -o addr show dev "$1" scope global | sed -n 's/.*valid_lft \([0-9a-z]*\).*/\1/p' | head -1)"
  if [ "$n" -gt 0 ]; then log "dhcpcd is still running after the rollback unit ended ($n processes, lease valid_lft ${a1:-?})"; return 0; fi
  warn "dhcpcd is NOT running after the rollback (lease valid_lft ${a1:-?}): run  sudo systemctl restart networking.service"
  return 1
}

stage_networkmanager() {
  [ "$NETWORKMANAGER" = 1 ] || return 0
  [ "$NM_ROLLBACK" = 0 ] || die "--networkmanager and --networkmanager-rollback contradict each other"
  log "NetworkManager for the wired uplink (replaces ifupdown + dhcpcd there)"
  command -v python3 >/dev/null 2>&1 || die "--networkmanager needs python3"
  local iface cid uuid tmp migrated=0 prof changed=0 ready=1
  iface="$(nm_uplink)"
  [ -n "$iface" ] || die "no default route: cannot tell which interface is the uplink (is the network up?)"
  [ ! -d "/sys/class/net/$iface/wireless" ] || die "the uplink $iface is Wi-Fi: only a wired uplink is supported (Wi-Fi is not touched)"
  grep -q "^$NM_MARK" /etc/network/interfaces 2>/dev/null && migrated=1
  if [ "$migrated" = 0 ] && ! grep -Eq "^[[:space:]]*iface[[:space:]]+$iface[[:space:]]+inet[[:space:]]+dhcp" /etc/network/interfaces; then
    die "/etc/network/interfaces has no 'iface $iface inet dhcp': only a DHCP uplink managed by ifupdown can be moved"
  fi
  log "uplink: $iface ($(cat "/sys/class/net/$iface/address")), currently $([ "$migrated" = 1 ] && echo "already moved" || echo "ifupdown + dhcpcd")"
  local nm_was_active=0
  systemctl is-active --quiet NetworkManager.service 2>/dev/null && nm_was_active=1
  # shellcheck disable=SC2046
  sys apt-get install -y --no-install-recommends $(pkgs networkmanager)
  # Debian's postinst starts NetworkManager at once. Until the switch it manages no wired device, but it would scan Wi-Fi and
  # (rc-manager auto) could rewrite /etc/resolv.conf: keep it stopped and disabled; the switch enables it.
  if [ "$migrated" = 0 ] && [ "$nm_was_active" = 0 ]; then
    if [ "$DRY" = 1 ]; then
      echo "  [dry-run] stop and disable NetworkManager right after the install (the switch enables it); check /etc/resolv.conf is still dhcpcd's"
    else
      $SUDO systemctl disable --now NetworkManager.service NetworkManager-wait-online.service >/dev/null 2>&1 || true
      if ! grep -q '^# Generated by dhcpcd' /etc/resolv.conf || ! grep -q '^nameserver ' /etc/resolv.conf; then
        die "/etc/resolv.conf is no longer dhcpcd's (or has no nameserver) after the NetworkManager install: nothing was switched. Fix: sudo systemctl restart networking.service, then run this again"
      fi
      log "NetworkManager stopped until the switch; /etc/resolv.conf is still dhcpcd's ($(awk '$1=="nameserver"{print $2}' /etc/resolv.conf | paste -sd' '))"
    fi
  fi
  cid="$(nm_client_id "$iface")"
  log "DHCP client-id NM will send (same as dhcpcd now): $cid"
  uuid="$(python3 -c 'import sys,uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, "hyprdeb-nm-" + sys.argv[1]))' "$iface")"
  tmp="$(mktemp -d)"
  cat > "$tmp/hyprdeb-$iface.nmconnection" <<EOF
# hyprdeb managed: wired uplink $iface, DHCP. Written by ./install.sh --networkmanager.
# dhcp-client-id is deliberately the one dhcpcd sent before (the router's leases are tied to it): see docs/recovery.md.
[connection]
id=hyprdeb-$iface
uuid=$uuid
type=ethernet
interface-name=$iface
autoconnect=true

[ethernet]

[ipv4]
method=auto
dhcp-client-id=$cid

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF
  prof="$NM_PROFILE_DIR/hyprdeb-$iface.nmconnection"
  # An existing hyprdeb-<if> profile is the user's (settings.toml [network] + `hyprdeb net apply` change it, and NetworkManager
  # rewrites the file in its own format): never rewrite it from the template. Only a missing dhcp-client-id is put back.
  if nmcli -g NAME connection show 2>/dev/null | grep -qx "hyprdeb-$iface"; then
    local have
    have="$(nmcli -g ipv4.dhcp-client-id connection show "hyprdeb-$iface" 2>/dev/null)"
    have="${have//\\/}"   # nmcli -g escapes ':' as '\:'
    if [ -z "$have" ] || [ "$have" = "--" ]; then
      if [ "$DRY" = 1 ]; then echo "  [dry-run] re-assert ipv4.dhcp-client-id=$cid on hyprdeb-$iface (it was missing)"
      else sys nmcli connection modify "hyprdeb-$iface" ipv4.dhcp-client-id "$cid"; changed=1; fi
    elif [ "$have" != "$cid" ] && [[ "$cid" =~ ^(ff:[0-9a-f]{2}(:[0-9a-f]{2})+|duid)$ ]]; then
      warn "hyprdeb-$iface sends client-id $have, dhcpcd used $cid before: left as it is (see docs/recovery.md before changing it)"
    fi
    log "profile hyprdeb-$iface exists: left as it is"
  else
    deploy_root_file "$tmp/hyprdeb-$iface.nmconnection" "$prof" 600 rootread && changed=1
  fi
  rm -rf "$tmp"
  deploy_root_file "$REPO/bin/hyprdeb-nm" /usr/local/sbin/hyprdeb-nm 755 || true
  # The root guard of `hyprdeb net apply`: reverts an unconfirmed change, even when the GUI, the terminal or the session is gone.
  local guard_changed=0
  deploy_root_file "$REPO/bin/hyprdeb-net-guard" /usr/local/sbin/hyprdeb-net-guard 755 && guard_changed=1
  deploy_root_file "$REPO/config/systemd/hyprdeb-net-guard.service" /etc/systemd/system/hyprdeb-net-guard.service && guard_changed=1
  deploy_root_file "$REPO/config/systemd/hyprdeb-net-guard.path" /etc/systemd/system/hyprdeb-net-guard.path && guard_changed=1
  deploy_root_file "$REPO/config/systemd/hyprdeb-net.tmpfiles.conf" /etc/tmpfiles.d/hyprdeb-net.conf && guard_changed=1
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] create /run/hyprdeb-net (systemd-tmpfiles), daemon-reload, enable and start hyprdeb-net-guard.path"
  else
    [ "$guard_changed" = 0 ] || { sys systemd-tmpfiles --create /etc/tmpfiles.d/hyprdeb-net.conf; sys systemctl daemon-reload; }
    [ -d /run/hyprdeb-net ] || sys systemd-tmpfiles --create /etc/tmpfiles.d/hyprdeb-net.conf
    systemctl is-enabled --quiet hyprdeb-net-guard.path 2>/dev/null || sys systemctl enable hyprdeb-net-guard.path
    systemctl is-active --quiet hyprdeb-net-guard.path 2>/dev/null || sys systemctl start hyprdeb-net-guard.path
  fi
  if [ "$migrated" = 1 ]; then
    if [ "$changed" = 1 ] && [ "$DRY" = 0 ]; then
      sys nmcli connection reload
      sys nmcli connection up "hyprdeb-$iface" || warn "could not re-activate hyprdeb-$iface"
    fi
    log "$iface is already managed by NetworkManager"
    return 0
  fi
  if [ "$DRY" = 1 ]; then
    cat <<EOT
  [dry-run] would switch $iface (as the systemd unit hyprdeb-nm-switch, detached from this terminal):
    0. arm a rollback timer: in $NM_TIMER min the old setup comes back unless you confirm$([ "$NM_TIMER" = 0 ] && echo " (--nm-timer 0: NO timer)")
    1. back up /etc/network/interfaces to /etc/network/interfaces.hyprdeb-pre-nm, ifdown $iface (the address is gone for a few seconds)
    2. comment out the auto/allow-hotplug/iface stanza of $iface in /etc/network/interfaces (lo stays)
    3. enable and restart NetworkManager (+ NetworkManager-wait-online)
    4. nmcli connection up hyprdeb-$iface
    5. check: the same IPv4 address as before, a gateway that answers ping, and /etc/resolv.conf (now NetworkManager's) still lists the DHCP DNS server;
       if not, roll back at once (a dynamic lease that comes back with another address after the DHCP RELEASE of ifdown also rolls back)
  [dry-run] then ask "keep it?" (stops the timer); no answer or "no" = roll back. Wi-Fi is not configured.
EOT
    return 0
  fi
  [ "$NM_TIMER" -gt 0 ] || [ -t 0 ] || die "--nm-timer 0 without a terminal would leave no way back: refusing"
  cat <<EOT

  Switching $iface to NetworkManager. The network drops for a few seconds. If anything goes wrong:
    - the checks run automatically and roll back by themselves,
    - the rollback timer ($NM_TIMER min) restores ifupdown even if you lose this session,
    - by hand: sudo hyprdeb-nm rollback   (or ./install.sh --only networkmanager-rollback)
  Log of the switch: journalctl -u hyprdeb-nm-switch
EOT
  if ! $SUDO systemd-run --quiet --unit=hyprdeb-nm-switch --collect --wait --pipe /usr/local/sbin/hyprdeb-nm switch "$iface" "$NM_TIMER"; then
    nm_check_dhcpcd "$iface" || true
    die "the switch failed and was rolled back (see journalctl -u hyprdeb-nm-switch); the old setup is active again"
  fi
  if [ "$NM_TIMER" -gt 0 ]; then
    if [ -t 0 ]; then
      local ans=""
      read -r -t 180 -p "Everything works from here? Keep NetworkManager? [y/N] (no answer in 3 min = roll back): " ans || true
      echo
      case "$ans" in
        y|Y|yes) sys systemctl stop hyprdeb-nm-rollback.timer; log "kept: NetworkManager manages $iface, the rollback timer is stopped" ;;
        *) log "rolling back"
           if $SUDO systemd-run --quiet --unit=hyprdeb-nm-rollback-now --collect --wait --pipe /usr/local/sbin/hyprdeb-nm rollback; then nm_check_dhcpcd "$iface" || true
           else warn "rollback reported a problem: check the network, journalctl -u hyprdeb-nm-rollback-now"; fi ;;
      esac
    else
      warn "no terminal to ask: the rollback timer is still armed ($NM_TIMER min). To keep NetworkManager: sudo systemctl stop hyprdeb-nm-rollback.timer"
    fi
  fi
}

stage_networkmanager_rollback() {
  [ "$NM_ROLLBACK" = 1 ] || return 0
  [ "$NETWORKMANAGER" = 0 ] || die "--networkmanager and --networkmanager-rollback contradict each other"
  log "Rolling the wired uplink back to ifupdown + dhcpcd"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] hyprdeb-nm rollback: restore /etc/network/interfaces from /etc/network/interfaces.hyprdeb-pre-nm, disable NetworkManager,"
    echo "  [dry-run] remove the hyprdeb profile, restart networking.service (it starts dhcpcd), check address, resolv.conf and that dhcpcd belongs to networking.service"
    return 0
  fi
  [ -x /usr/local/sbin/hyprdeb-nm ] || die "/usr/local/sbin/hyprdeb-nm is not installed: nothing was moved by this installer"
  deploy_root_file "$REPO/bin/hyprdeb-nm" /usr/local/sbin/hyprdeb-nm 755 || true   # the rollback runs the current script, not an older installed copy
  local iface
  iface="$(nm_uplink)"
  $SUDO systemd-run --quiet --unit=hyprdeb-nm-rollback-now --collect --wait --pipe /usr/local/sbin/hyprdeb-nm rollback \
    || die "the rollback reported a problem: check the network, journalctl -u hyprdeb-nm-rollback-now"
  nm_check_dhcpcd "$iface" || die "dhcpcd did not survive the end of the rollback unit"
}

# NAS shares: each [nas.NAME] in settings.toml (or the older flat [nas] = the share "nax") as a systemd mount + automount on /mnt/NAME,
# made by the root helper /usr/local/sbin/hyprdeb-nas. The helper is the only thing that writes /etc/hyprdeb/nas-NAME.credentials
# (root 0600) and the units; here it is deployed with its socket (hyprdeb-nas.socket, group sudo) and the polkit action that the
# settings window's NAS page uses (Add / Edit / Test / Remove ask for the administrator password through it). Then `hyprdeb nas
# install` hands every share of settings.toml to the helper through sudo: a share that is already there is only re-checked (an older
# single share is moved to the new password file without asking for it again); a new one asks its password silently, once, and the helper
# gets it on stdin: never on a command line, in a log, in the repo or in settings.toml. Only the automount is enabled and started,
# never the mount: nothing is mounted at boot, an unreachable NAS cannot delay or fail boot or login, and the first access
# (`ls /mnt/NAME`) mounts it (fails after TimeoutSec if the NAS is away). No fstab line.
stage_nas() {
  [ "$NAS" = 1 ] || return 0
  log "NAS (CIFS, systemd automount, root helper)"
  command -v python3 >/dev/null 2>&1 || die "--nas needs python3 (it reads the shares from settings.toml)"
  if ! stage_selected settings && [ ! -f "$HOME/.config/hyprdeb/settings.toml" ]; then
    die "$HOME/.config/hyprdeb/settings.toml does not exist: run ./install.sh --only settings first"
  fi
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs nas)
  local changed=0 sock_changed=0 hb="python3 -I -B $REPO/bin/hyprdeb"
  # The helper's service may only write /etc/hyprdeb (ReadWritePaths): the directory has to exist before its first request.
  if [ "$DRY" = 1 ]; then [ -d /etc/hyprdeb ] || echo "  [dry-run] create /etc/hyprdeb (root, 0755)"
  else sys install -d -m 0755 -o root -g root /etc/hyprdeb; fi
  deploy_root_file "$REPO/bin/hyprdeb-nas" /usr/local/sbin/hyprdeb-nas 755 && changed=1
  deploy_root_file "$REPO/config/systemd/hyprdeb-nas@.service" /etc/systemd/system/hyprdeb-nas@.service && changed=1
  deploy_root_file "$REPO/config/systemd/hyprdeb-nas.socket" /etc/systemd/system/hyprdeb-nas.socket && { changed=1; sock_changed=1; }
  deploy_root_file "$REPO/config/polkit/org.hyprdeb.nas.policy" /usr/share/polkit-1/actions/org.hyprdeb.nas.policy || true
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] daemon-reload, enable and start hyprdeb-nas.socket"
    $hb nas install --dry-run || true
    return 0
  fi
  [ "$changed" = 0 ] || sys systemctl daemon-reload
  systemctl is-enabled --quiet hyprdeb-nas.socket 2>/dev/null || sys systemctl enable hyprdeb-nas.socket
  if ! systemctl is-active --quiet hyprdeb-nas.socket; then sys systemctl start hyprdeb-nas.socket
  elif [ "$sock_changed" = 1 ]; then sys systemctl restart hyprdeb-nas.socket; fi
  $hb nas install || warn "some NAS shares were not set up (see above); run ./install.sh --nas again after fixing them"
  # The one test per share: a single ls triggers the automount. Bounded by the mount unit's TimeoutSec.
  local n mp
  for n in $($hb nas list 2>/dev/null | awk '/ -> /{print $1}'); do
    mp="/mnt/$n"
    if timeout 40 ls "$mp" >/dev/null 2>&1; then log "ls $mp: the share mounted and answers"
    else warn "ls $mp failed (NAS unreachable, wrong credentials or share name): the NAS page has a Test button; journalctl -u mnt-$n.mount"; fi
  done
}

# Printing: CUPS with the queue from [printing] in settings.toml. Three ways to give the queue a driver:
#   driver = "everywhere"      driverless IPP (lpadmin -m everywhere) for an ipp:// or ipps:// printer: nothing else to install;
#   ppd = "/path/to/file.ppd"  any vendor's PPD that is already on this machine;
#   driver = "canon-lbp6030"   Canon's own PPD for the LBP6030w, a raw-port printer without IPP (socket://ip:9100). Canon's driver is
#                              proprietary: it is never in the repo and never downloaded here; the user installs the .deb
#                              (cnrdrvcups-ufr2lt-uk) first, and this stage stops BEFORE installing anything when it or its PPD is missing.
# With neither key set the address decides: ipp/ipps = everywhere, socket:// = canon-lbp6030.
# No avahi, no cups-browsed (printers are never discovered or shared on their own).
CANON_PKG=cnrdrvcups-ufr2lt-uk
CANON_PPD=/usr/share/cups/model/CNRCUPSLBP6030ZNK.ppd
CANON_FILTER=/usr/lib/cups/filter/rastertosfp
stage_printing() {
  [ "$PRINTING" = 1 ] || return 0
  log "Printing (CUPS, queue from [printing])"
  command -v python3 >/dev/null 2>&1 || die "--printing needs python3 (it reads [printing] from settings.toml)"
  if ! stage_selected settings && [ ! -f "$HOME/.config/hyprdeb/settings.toml" ]; then
    die "$HOME/.config/hyprdeb/settings.toml does not exist: run ./install.sh --only settings first, then add [printing] to it"
  fi
  local out rc=0 name uri dflt driver ppd
  out="$(python3 -I -B "$REPO/bin/hyprdeb" print config)" || rc=$?
  [ "$rc" = 0 ] || die "[printing] in ~/.config/hyprdeb/settings.toml is not set or not valid (printer_name and printer_uri, see the comments in settings.toml); see above. Nothing was installed."
  name="$(sed -n 's/^name=//p' <<<"$out")"; uri="$(sed -n 's/^uri=//p' <<<"$out")"; dflt="$(sed -n 's/^default=//p' <<<"$out")"
  driver="$(sed -n 's/^driver=//p' <<<"$out")"; ppd="$(sed -n 's/^ppd=//p' <<<"$out")"
  # The driver first: a failed run changes nothing.
  case "$driver" in
    canon-lbp6030)
      ppd="$CANON_PPD"
      if ! { dpkg-query -W -f='${Status}' "$CANON_PKG" 2>/dev/null | grep -q '^install ok installed$' && [ -f "$CANON_PPD" ]; }; then
        die "Canon's driver is not installed: $CANON_PKG and $CANON_PPD are needed. Install the .deb you downloaded from Canon yourself (sudo dpkg -i cnrdrvcups-ufr2lt-uk_*.deb); this script never downloads or ships it. Nothing was installed."
      fi ;;
    ppd)
      [ -f "$ppd" ] || die "[printing] ppd = \"$ppd\" does not exist on this machine: install the driver that ships it, or fix the path. Nothing was installed." ;;
  esac
  # shellcheck disable=SC2046
  sys apt-get install -y --no-install-recommends $(pkgs printing)
  if [ "$driver" = canon-lbp6030 ]; then
    if [ "$DRY" = 1 ]; then
      echo "  [dry-run] would check that ldd $CANON_FILTER shows no 'not found' line"
    else
      local missing
      missing="$(ldd "$CANON_FILTER" 2>&1 | grep 'not found' || true)"
      [ -z "$missing" ] || die "Canon's filter has unresolved libraries (nothing is configured yet): $missing"
    fi
  fi
  systemctl is-enabled --quiet cups.service 2>/dev/null && systemctl is-active --quiet cups.service 2>/dev/null || sys systemctl enable --now cups.service
  # lpadmin group: manage printers without sudo. A new group membership applies at the next login.
  local me; me="$(id -un)"
  if [ "$DRY" = 1 ] && ! getent group lpadmin >/dev/null; then
    echo "  [dry-run] would add $me to the lpadmin group (applies after the next login)"
  elif ! getent group lpadmin | awk -F: '{print $4}' | tr ',' '\n' | grep -qx "$me"; then
    sys usermod -aG lpadmin "$me"
    [ "$DRY" = 1 ] || warn "$me was added to the lpadmin group: it takes effect after the next login (until then use sudo for lpadmin)"
  fi
  # The queue: created, or updated when the address or driver differs. Not shared on the network.
  local nick="" cur_uri="" ppd_nick=""
  [ -n "$ppd" ] && nick="$(grep -m1 '^\*NickName:' "$ppd" || true)"
  if [ "$DRY" = 0 ] || command -v lpstat >/dev/null 2>&1; then
    cur_uri="$(lpstat -v "$name" 2>/dev/null | sed -n 's/.*device for [^:]*: //p' || true)"
    [ -f "/etc/cups/ppd/$name.ppd" ] && ppd_nick="$($SUDO grep -m1 '^\*NickName:' "/etc/cups/ppd/$name.ppd" 2>/dev/null || true)"
  fi
  local same=0
  if [ "$cur_uri" = "$uri" ]; then
    if [ "$driver" = everywhere ]; then [ -n "$ppd_nick" ] && same=1   # the queue exists with its generated PPD; a changed address is the other branch
    else [ -n "$nick" ] && [ "$ppd_nick" = "$nick" ] && same=1; fi
  fi
  if [ "$same" = 1 ]; then
    log "queue $name already points at the printer: left alone"
  elif [ "$driver" = everywhere ]; then
    sys lpadmin -p "$name" -E -v "$uri" -m everywhere -o printer-is-shared=false
  else
    sys lpadmin -p "$name" -E -v "$uri" -P "$ppd" -o printer-is-shared=false
  fi
  if [ "$dflt" = 1 ]; then
    if [ "$(lpstat -d 2>/dev/null | sed -n 's/.*destination: //p')" != "$name" ]; then sys lpadmin -d "$name"; fi
  fi
  if [ "$DRY" = 0 ]; then
    python3 -I -B "$REPO/bin/hyprdeb" print status || warn "hyprdeb print status reports a problem (a printer that is off or asleep is only a warning: jobs wait in the queue)"
  fi
}

# Flatpak + Flathub as a system remote (/var/lib/flatpak): one installation for all users, updated by
# one `flatpak update`. XDG_DATA_DIRS for the Hyprland session is handled by config/hypr/flatpak.lua.
stage_flatpak() {
  [ "$FLATPAK" = 1 ] || return 0
  log "Flatpak + Flathub (system remote)"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs flatpak)
  if ! { command -v flatpak >/dev/null 2>&1 && flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; }; then
    sys flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
  # Apps from packages/flatpak-apps.list, system-wide from Flathub. Only installs what is missing and never
  # removes an app that is not listed.
  local app
  while read -r app; do
    if command -v flatpak >/dev/null 2>&1 && flatpak info --system "$app" >/dev/null 2>&1; then
      echo "  $app already installed"
    else
      sys flatpak install --system --noninteractive -y flathub "$app"
    fi
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$REPO/packages/flatpak-apps.list")
}

# logind: allow delay inhibitors (hypridle before sleep) up to 10 s. Never restarts systemd-logind:
# that can end the running graphical session. The new value applies from the next boot.
# OBS Virtual Camera: v4l2loopback (DKMS) with managed module options, loaded at boot and right now.
# OBS would otherwise try "pkexec modprobe", and pkexec is deliberately not installed.
stage_virtualcam() {
  [ "$VIRTUALCAM" = 1 ] || return 0
  log "OBS Virtual Camera (v4l2loopback)"
  # shellcheck disable=SC2046
  sys apt-get install -y $(pkgs virtualcam)
  local changed=0
  if deploy_root_file "$REPO/config/modprobe/v4l2loopback.conf" /etc/modprobe.d/v4l2loopback.conf; then changed=1; fi
  deploy_root_file "$REPO/config/modules-load/v4l2loopback.conf" /etc/modules-load.d/v4l2loopback.conf || true
  if [ "$DRY" = 1 ]; then echo "  [dry-run] check DKMS build for $(uname -r) and load v4l2loopback"; return 0; fi
  # Full path: /usr/sbin is not on a normal user's PATH on Debian (a bare "modinfo" failed and skipped the load).
  if ! /usr/sbin/modinfo -k "$(uname -r)" v4l2loopback >/dev/null 2>&1; then
    warn "v4l2loopback is not built for the running kernel $(uname -r) (see: sudo dkms status v4l2loopback)"; return 0
  fi
  if [ ! -d /sys/module/v4l2loopback ]; then
    sys modprobe v4l2loopback && log "v4l2loopback loaded: $(cat /sys/devices/virtual/video4linux/video10/name 2>/dev/null)"
  elif [ "$changed" = 1 ]; then
    # Reloading would break a running virtual camera; the new options apply at the next boot.
    warn "v4l2loopback is already loaded; new options apply after a reboot (or: sudo modprobe -r v4l2loopback && sudo modprobe v4l2loopback)"
  fi
}

stage_logind() {
  log "logind drop-in"
  if deploy_root_file "$REPO/config/systemd/logind-hyprdeb.conf" /etc/systemd/logind.conf.d/hyprdeb.conf; then
    warn "logind setting changed: it takes effect after a reboot (systemd-logind is deliberately not restarted)."
  fi
}

stage_timezone() {
  [ -n "$TZ_WANT" ] || return 0
  log "Timezone -> $TZ_WANT"
  sys timedatectl set-timezone "$TZ_WANT"
}

# Rewrite the managed block in hyprland.lua; everything outside the markers is left alone.
stage_config() {
  log "User config -> $CONF_DIR"
  local frags=("$REPO"/config/hypr/*.lua)
  [ -r "${frags[0]}" ] || die "no config/hypr/*.lua fragments"
  run mkdir -p "$CONF_DIR"
  local target="$CONF_DIR/hyprland.lua" fresh=0

  if [ ! -f "$target" ]; then
    if [ -r "$BASE_LUA" ]; then
      run cp "$BASE_LUA" "$target"; fresh=1
    elif [ "$DRY" = 1 ]; then
      warn "dry-run: $BASE_LUA does not exist yet (hyprland not installed); the real run copies it after the package stage"
    else
      die "no $BASE_LUA: the hyprland package is not installed; run ./install.sh --only sources,desktop first (or set HYPRDEB_BASE_LUA)"
    fi
  fi
  # The Debian default launches Dolphin on SUPER+E; we ship Thunar. This one line outside the
  # managed block is rewritten on purpose (a later duplicate bind would fire both programs).
  if [ "$DRY" = 0 ] && [ -f "$target" ] && grep -qE '^local fileManager[[:space:]]*=[[:space:]]*"dolphin"' "$target"; then
    sed -i -E 's/^(local fileManager[[:space:]]*=[[:space:]]*)"dolphin"/\1"thunar"/' "$target"
    log "fileManager: dolphin -> thunar"
  fi
  # The old stub hyprland.conf makes Hyprland warn about an autogenerated config.
  if [ -f "$CONF_DIR/hyprland.conf" ]; then
    run mv "$CONF_DIR/hyprland.conf" "$CONF_DIR/hyprland.conf.disabled"
  fi

  if [ "$DRY" = 1 ]; then echo "  [dry-run] refresh managed block in $target"; return 0; fi

  # Timestamped backup, kept only when an existing file would actually change
  # (a file we just copied from the Debian default needs no backup).
  local tmp; tmp="$(mktemp)"
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$target" > "$tmp"
  # Trim trailing blank lines so repeated runs do not grow the file.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
  { cat "$tmp"; printf '\n%s\n' "$BEGIN"; cat "${frags[@]}"; printf '%s\n' "$END"; } > "$tmp.new"
  if ! cmp -s "$tmp.new" "$target"; then
    local keep=0
    # No backup needed for a fresh copy or a file still identical to the Debian default.
    if [ "$fresh" = 0 ] && ! { [ -r "$BASE_LUA" ] && cmp -s "$target" "$BASE_LUA"; }; then keep=1; fi
    if [ "$keep" = 1 ]; then cp "$target" "$target.bak.$(date +%Y%m%d-%H%M%S)"; fi
    cp "$tmp.new" "$target"
    log "hyprland.lua updated$([ "$keep" = 1 ] && echo ' (backup kept)')"
  else
    log "hyprland.lua already up to date"
  fi
  rm -f "$tmp" "$tmp.new"
}

# Copy one managed file. Files carry a "hyprdeb managed" marker; an existing file without
# the marker (the user's own) is backed up once before being replaced.
# Returns 0 if the file was (or in dry-run would be) written, 1 if already identical.
deploy_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then return 1; fi
  if [ "$DRY" = 1 ]; then echo "  [dry-run] deploy $(basename "$src") -> $dst"; return 0; fi
  if [ -f "$dst" ] && ! grep -q 'hyprdeb managed' "$dst"; then
    cp "$dst" "$dst.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  cp "$src" "$dst"
  log "$dst updated"
}

# Restart a running program so it re-reads its config. Only possible from inside Hyprland
# (the new process must be a child of the compositor session); otherwise just warn.
restart_app() {
  local name="$1"
  [ "$DRY" = 0 ] && pgrep -x "$name" >/dev/null 2>&1 || return 0
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
    pkill -x "$name" || true
    sleep 0.5
    hyprctl dispatch "hl.dsp.exec_cmd(\"$name\")" >/dev/null
    log "$name restarted"
  else
    warn "$name config changed; restart it from inside Hyprland (pkill $name; hyprctl dispatch 'hl.dsp.exec_cmd(\"$name\")')"
  fi
}

# Tabler Icons (outline, MIT) for waybar, the quick menu and the settings window: the TTF is vendored in assets/fonts/tabler-icons and
# copied to ~/.local/share/fonts/hyprdeb/ only when it differs; fc-cache runs only then. (Apps name the family explicitly: Material
# Icons shares some of the private-use codepoints.)
stage_icons() {
  local src="$REPO/assets/fonts/tabler-icons/tabler-icons.ttf" dst="$HOME/.local/share/fonts/hyprdeb/tabler-icons.ttf"
  [ -f "$src" ] || return 0
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then return 0; fi
  if [ "$DRY" = 1 ]; then echo "  [dry-run] copy tabler-icons.ttf -> $dst and run fc-cache"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log "$dst updated"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$(dirname "$dst")" || warn "fc-cache failed"; else warn "fc-cache not found: the icon font is picked up at the next fontconfig scan"; fi
}

stage_waybar() {
  local src="$REPO/config/waybar" dst="$HOME/.config/waybar" f changed=0
  [ -d "$src" ] || return 0
  run mkdir -p "$dst"
  for f in config.jsonc style.css; do
    [ -f "$src/$f" ] || continue
    if deploy_file "$src/$f" "$dst/$f"; then changed=1; fi
  done
  # SIGUSR2 reload does not reliably re-read the CSS, so restart waybar completely.
  if [ "$changed" = 1 ]; then restart_app waybar; fi
}

# hyprlock / hypridle / hyprpaper configs and the default wallpaper.
# hyprlock reads its config on every lock; hypridle and hyprpaper must be restarted.
stage_lock() {
  log "Lock, idle, wallpaper -> $CONF_DIR"
  local src="$REPO/config/hypr" f
  run mkdir -p "$CONF_DIR"
  deploy_file "$src/hyprlock.conf" "$CONF_DIR/hyprlock.conf" || true
  for f in hypridle hyprpaper; do
    if deploy_file "$src/$f.conf" "$CONF_DIR/$f.conf"; then restart_app "$f"; fi
  done
  run mkdir -p "$HOME/.local/bin"
  deploy_file "$REPO/bin/hyprdeb-lock" "$HOME/.local/bin/hyprdeb-lock" || true
  if [ "$DRY" = 0 ] && [ ! -x "$HOME/.local/bin/hyprdeb-lock" ]; then chmod 755 "$HOME/.local/bin/hyprdeb-lock"; fi
  # The wallpaper is the user's to replace: only created when missing, never overwritten.
  if [ ! -e "$CONF_DIR/wallpaper.png" ]; then
    run cp "$REPO/assets/wallpaper.png" "$CONF_DIR/wallpaper.png"
    [ "$DRY" = 1 ] || log "default wallpaper -> $CONF_DIR/wallpaper.png"
    restart_app hyprpaper
  fi
}

# XDG user folders (Pictures, Downloads, ...): created once with English names (LC_ALL=C.UTF-8), whatever the
# locale. Skipped when ~/.config/user-dirs.dirs exists, so the user's choices are never changed; no --force, so
# existing folders are never moved or renamed. swappy and others fall back to $HOME without this file.
stage_xdg_dirs() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  [ -f "$conf" ] && return 0
  command -v xdg-user-dirs-update >/dev/null 2>&1 || { warn "xdg-user-dirs-update not installed; skipping XDG user folders"; return 0; }
  log "XDG user folders -> $conf"
  run env LC_ALL=C.UTF-8 xdg-user-dirs-update
}

# swappy (SHIFT+Print): save next to the CTRL+Print screenshots and close after save/copy.
stage_swappy() {
  [ -f "$REPO/config/swappy/config" ] || return 0
  log "swappy -> $HOME/.config/swappy"
  run mkdir -p "$HOME/.config/swappy"
  [ -d "$HOME/Pictures/Screenshots" ] || run mkdir -p "$HOME/Pictures/Screenshots"
  deploy_file "$REPO/config/swappy/config" "$HOME/.config/swappy/config" || true
}

# Default apps: the image viewer (org.gnome.Loupe) for the image types it declares and the document viewer (org.gnome.Papers) for
# PDF. The MIME types are read from the exported .desktop files, so only what the apps really declare is set. image/tiff (Papers
# declares it too) and the SVG types are left to the system lookup. Only the [Default Applications] section of
# ~/.config/mimeapps.list gets new lines; an existing default for a type is never changed (it is reported), every other line is kept,
# and the file is copied once to mimeapps.list.bak before the first change. Thunar and Chrome read the same file.
stage_defaultapps() {
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list" d app dfile out
  command -v python3 >/dev/null 2>&1 || { warn "python3 not found: default apps skipped"; return 0; }
  local -a files=()
  for app in org.gnome.Loupe org.gnome.Papers; do
    dfile=""
    for d in /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications" /usr/share/applications; do
      [ -f "$d/$app.desktop" ] && { dfile="$d/$app.desktop"; break; }
    done
    if [ -z "$dfile" ]; then log "default apps: $app is not installed (./install.sh --flatpak): skipped"; return 0; fi
    files+=("$dfile")
  done
  out="$(DRY="$DRY" python3 -I -B - "$conf" "${files[@]}" <<'PY'
import os, re, shutil, sys
conf, loupe, papers = sys.argv[1:4]
def types(path):
    for line in open(path, encoding="utf-8"):
        if line.startswith("MimeType="):
            return [t for t in line[9:].strip().split(";") if t]
    return []
want = {}
for t in types(loupe):
    if t.startswith("image/") and t not in ("image/tiff", "image/svg+xml", "image/svg+xml-compressed"):
        want[t] = "org.gnome.Loupe.desktop"
for t in types(papers):
    if re.fullmatch(r"application/(x-(ext-|bz|gz|xz)?)?pdf", t):
        want[t] = "org.gnome.Papers.desktop"
lines = open(conf, encoding="utf-8").read().split("\n") if os.path.exists(conf) else []
sec = None
head = "[Default Applications]"
have = {}
end = None   # index after the last line of the [Default Applications] section
for i, l in enumerate(lines):
    st = l.strip()
    if st.startswith("[") and st.endswith("]"):
        sec = st
        if sec == head: end = i + 1
        continue
    if sec == head:
        if st: end = i + 1
        if "=" in st and not st.startswith("#"):
            k, v = st.split("=", 1); have[k.strip()] = v.strip()
add, other = [], []
for t, a in sorted(want.items()):
    cur = have.get(t)
    if cur is None: add.append(f"{t}={a}")
    elif cur.split(";")[0] != a: other.append(f"{t} -> {cur}")
for o in other: print("keep: " + o)
if not add:
    print("ok: nothing to add"); sys.exit(0)
if end is None:
    if lines and lines[-1] != "": lines.append("")
    lines += [head]; end = len(lines)
lines[end:end] = add
if os.environ.get("DRY") == "1":
    print("would add %d default(s) to %s: %s" % (len(add), conf, ", ".join(x.split("=")[0] for x in add))); sys.exit(0)
os.makedirs(os.path.dirname(conf), exist_ok=True)
if os.path.exists(conf) and not os.path.exists(conf + ".bak"): shutil.copy2(conf, conf + ".bak")
text = "\n".join(lines)
if not text.endswith("\n"): text += "\n"
tmp = conf + ".hyprdeb-new"
open(tmp, "w", encoding="utf-8").write(text); os.replace(tmp, conf)
print("added %d default(s) to %s" % (len(add), conf))
PY
)" || { warn "default apps: could not update $conf"; return 0; }
  log "default apps: $(sed -e '/^keep: /d' <<<"$out")"
  grep '^keep: ' <<<"$out" | sed 's/^keep: /  left as it is (your choice): /' || true
}

# kitty: managed defaults in ~/.config/kitty/hyprdeb.conf. The user's kitty.conf is never rewritten; it only gets
# one "include hyprdeb.conf" line at the top (backed up once before that), so the user's own lines override ours.
stage_kitty() {
  local src="$REPO/config/kitty" dst="$HOME/.config/kitty" conf changed=0
  [ -d "$src" ] || return 0
  log "kitty -> $dst"
  conf="$dst/kitty.conf"
  run mkdir -p "$dst"
  if deploy_file "$src/hyprdeb.conf" "$dst/hyprdeb.conf"; then changed=1; fi
  if ! grep -qxE '[[:space:]]*include[[:space:]]+hyprdeb\.conf[[:space:]]*' "$conf" 2>/dev/null; then
    if [ "$DRY" = 1 ]; then echo "  [dry-run] add 'include hyprdeb.conf' at the top of $conf"
    else
      local tmp; tmp="$(mktemp)"
      if [ -f "$conf" ]; then cp "$conf" "$conf.bak.$(date +%Y%m%d-%H%M%S)"; fi
      { printf '%s\n' "# hyprdeb: defaults from hyprdeb.conf; lines below this one override them." "include hyprdeb.conf"
        [ -f "$conf" ] && cat "$conf"; } > "$tmp"
      cat "$tmp" > "$conf"; rm -f "$tmp"
      log "$conf: include line added at the top"
    fi
    changed=1
  fi
  # kitty re-reads its config on SIGUSR1 (all running instances of this user).
  if [ "$changed" = 1 ] && [ "$DRY" = 0 ] && pgrep -x -u "$(id -u)" kitty >/dev/null; then
    pkill -USR1 -x -u "$(id -u)" kitty && log "kitty config reloaded (SIGUSR1)"
  fi
}

# User settings (monitor layout so far): ~/.local/bin/hyprdeb turns ~/.config/hyprdeb/settings.toml into the
# generated ~/.config/hypr/hyprdeb-settings.lua. settings.toml is the user's: copied from the example only when
# missing, never overwritten. Runs after stage_config so the managed block already loads the generated file.
# An invalid settings.toml only warns here: the last good generated file stays in place (hyprdeb fails closed).
stage_settings() {
  log "Settings -> $HOME/.config/hyprdeb"
  local bin="$HOME/.local/bin/hyprdeb" cfg="$HOME/.config/hyprdeb/settings.toml"
  run mkdir -p "$HOME/.local/bin" "$HOME/.config/hyprdeb"
  deploy_file "$REPO/bin/hyprdeb" "$bin" || true
  if [ "$DRY" = 0 ] && [ ! -x "$bin" ]; then chmod 755 "$bin"; fi
  if [ ! -e "$cfg" ]; then
    run cp "$REPO/config/hyprdeb/settings.toml" "$cfg"
    [ "$DRY" = 1 ] || log "example settings -> $cfg"
  fi
  # The settings window (hyprdeb gui, Quickshell): a managed file, always the repo's.
  run mkdir -p "$HOME/.local/share/hyprdeb/gui"
  deploy_file "$REPO/config/hyprdeb/gui/shell.qml" "$HOME/.local/share/hyprdeb/gui/shell.qml" || true
  deploy_file "$REPO/config/hyprdeb/gui/keys.qml" "$HOME/.local/share/hyprdeb/gui/keys.qml" || true
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not installed; skipping hyprdeb apply"
  # In a dry run the script is not deployed yet, so run the repo copy (same code).
  elif [ "$DRY" = 1 ]; then python3 "$REPO/bin/hyprdeb" apply --dry-run || warn "hyprdeb apply --dry-run failed (see above)"
  else "$bin" apply || warn "hyprdeb apply failed: fix $cfg (check: hyprdeb check); the last generated files are kept"; fi
  # hypridle gets its listeners from this generated file. If apply could not make it (no python3, invalid settings.toml),
  # still create it with the default listeners, so the idle lock never silently disappears.
  # Same for the wallpaper block that hyprpaper.conf sources.
  local f
  for f in idle paper; do
    if [ ! -e "$CONF_DIR/hyprdeb-$f.conf" ]; then
      run cp "$REPO/config/hyprdeb/hyprdeb-$f.default.conf" "$CONF_DIR/hyprdeb-$f.conf"
      [ "$DRY" = 1 ] || warn "$CONF_DIR/hyprdeb-$f.conf was missing and apply did not create it: wrote the defaults"
    fi
  done
}

# mako: the static config (from the repo; the include inside it is generated by `hyprdeb apply`). mako refuses to load a
# config whose include is missing, so create the include with the defaults when apply could not (python3 missing, invalid
# settings.toml). A changed config is reloaded with makoctl, never by killing mako.
stage_mako() {
  log "Notifications -> $HOME/.config/mako"
  local dst="$HOME/.config/mako" inc="$HOME/.config/mako/hyprdeb-settings"
  run mkdir -p "$dst"
  if [ ! -e "$inc" ]; then
    run cp "$REPO/config/hyprdeb/hyprdeb-mako.default" "$inc"
    [ "$DRY" = 1 ] || warn "$inc was missing and apply did not create it: wrote the defaults"
  fi
  if deploy_file "$REPO/config/mako/config" "$dst/config" && [ "$DRY" = 0 ] && pgrep -x mako >/dev/null 2>&1; then
    if makoctl reload; then log "mako reloaded"; else warn "makoctl reload failed (check ~/.config/mako/config)"; fi
  fi
}

# Stage registry, in the order a full run uses. name|function|needs sudo|opt-in flag|purpose
STAGE_TABLE='sources|stage_sources|yes||APT: contrib/non-free components, trixie-backports, apt update
base|stage_base|yes||packages/base.list
desktop|stage_desktop|yes||packages/desktop.list (from backports); needs sources
shell|stage_shell|yes||packages/shell.list
apps|stage_apps|yes||packages/apps.list
nvidia|stage_nvidia|yes|--nvidia|NVIDIA proprietary driver
chrome|stage_chrome|yes|(default on, --no-chrome)|Google Chrome (official apt repo)
vscode|stage_vscode|yes|--vscode|Visual Studio Code (Microsoft apt repo)
cowork|stage_cowork|yes|--cowork|QEMU, kvm group, vhost_vsock for Claude Desktop Cowork
flatpak|stage_flatpak|yes|--flatpak|Flatpak, Flathub remote, apps in packages/flatpak-apps.list
virtualcam|stage_virtualcam|yes|--virtualcam|OBS Virtual Camera (v4l2loopback via DKMS)
logind|stage_logind|yes||logind drop-in
timezone|stage_timezone|yes|--timezone VALUE|set the timezone
config|stage_config|no||hyprland.lua managed block; needs the hyprland package
settings|stage_settings|no||hyprdeb CLI, settings.toml, settings window, shortcuts window
notifications|stage_mako|no||mako config and settings
icons|stage_icons|no||Tabler icon font
waybar|stage_waybar|no||waybar config
lock|stage_lock|no||hyprlock, hypridle, hyprpaper, wallpaper
kitty|stage_kitty|no||kitty config
xdg-dirs|stage_xdg_dirs|no||XDG user folders
swappy|stage_swappy|no||swappy config
defaultapps|stage_defaultapps|no||image and PDF viewers (Loupe, Papers) as the default apps in ~/.config/mimeapps.list
networkmanager|stage_networkmanager|yes|--networkmanager|wired uplink from ifupdown/dhcpcd to NetworkManager (read docs/recovery.md first)
networkmanager-rollback|stage_networkmanager_rollback|yes|--networkmanager-rollback|undo the switch: ifupdown/dhcpcd again, NetworkManager disabled
nas|stage_nas|yes|--nas|NAS shares from [nas.NAME] in settings.toml + the root helper behind the NAS page (asks for new passwords)
printing|stage_printing|yes|--printing|CUPS and the printer queue from [printing] in settings.toml (driverless IPP, a PPD of yours, or the Canon LBP6030 driver)
greeter|stage_greeter|yes|--greeter|greetd + tuigreet login screen (read docs/recovery.md first)'
STAGE_GROUPS='packages=base,desktop,shell,apps
user=config,settings,notifications,icons,waybar,lock,kitty,xdg-dirs,swappy,defaultapps'

stage_field() { # name field-number -> the registry field (1 name, 2 function, 3 sudo, 4 opt-in flag, 5 purpose)
  awk -F'|' -v n="$1" -v f="$2" '$1==n {print $f}' <<<"$STAGE_TABLE"
}

list_stages() {
  printf '%-24s %-5s %-26s %s\n' STAGE SUDO OPT-IN PURPOSE
  local n sd fl pu
  while IFS='|' read -r n _ sd fl pu; do printf '%-24s %-5s %-26s %s\n' "$n" "$sd" "${fl:--}" "$pu"; done <<<"$STAGE_TABLE"
  echo
  echo "Groups (for --only): $(sed -e 's/=/ = /' -e 's/,/, /g' <<<"$STAGE_GROUPS" | paste -sd';' | sed 's/;/;  /g')"
  echo "--config-only is the same as --only user. Opt-in stages run only when their flag is given, or when named in --only."
}

# Selected stages as a space-padded list (" name name "), set by select_stages.
SELECTED=" "
stage_selected() { [[ "$SELECTED" == *" $1 "* ]]; }

select_stages() {
  local all n item g members flag
  all="$(awk -F'|' '{print $1}' <<<"$STAGE_TABLE")"
  if [ "$CONFIG_ONLY" = 1 ] && [ -n "$ONLY" ]; then die "--config-only and --only cannot be combined (--config-only is --only user)"; fi
  [ "$CONFIG_ONLY" = 1 ] && ONLY="user"
  if [ -z "$ONLY" ]; then SELECTED=" $(echo $all) "; return 0; fi
  local want="" bad=""
  for item in ${ONLY//,/ }; do
    if grep -qx "$item" <<<"$all"; then want="$want $item"
    elif members="$(awk -F= -v g="$item" '$1==g {print $2}' <<<"$STAGE_GROUPS")" && [ -n "$members" ]; then want="$want ${members//,/ }"
    else bad="$bad $item"; fi
  done
  if [ -n "$bad" ]; then
    echo "ERROR: unknown stage name(s):$bad" >&2
    echo "valid stages: $(echo $all)" >&2
    echo "valid groups: $(awk -F= '{print $1}' <<<"$STAGE_GROUPS" | paste -sd' ')" >&2
    exit 1
  fi
  # In the normal order, once each; naming an opt-in stage selects it for this run.
  for n in $all; do
    [[ " $want " == *" $n "* ]] || continue
    SELECTED="$SELECTED$n "
    case "$n" in
      chrome) [ "$NO_CHROME_GIVEN" = 0 ] || die "--only chrome contradicts --no-chrome"; CHROME=1 ;;
      nvidia) NVIDIA=1 ;; vscode) VSCODE=1 ;; cowork) COWORK=1 ;; flatpak) FLATPAK=1 ;; virtualcam) VIRTUALCAM=1 ;;
      nas) NAS=1 ;; printing) PRINTING=1 ;; greeter) GREETER=1 ;; networkmanager) NETWORKMANAGER=1 ;; networkmanager-rollback) NM_ROLLBACK=1 ;;
      timezone) [ -n "$TZ_WANT" ] || die "--only timezone needs --timezone VALUE" ;;
    esac
  done
  [ "$NETWORKMANAGER" = 0 ] || [ "$NM_ROLLBACK" = 0 ] || die "--networkmanager and --networkmanager-rollback contradict each other"
  # Flags of stages that are not selected would silently do nothing: say so.
  for flag in "nvidia:$NVIDIA" "vscode:$VSCODE" "cowork:$COWORK" "flatpak:$FLATPAK" "virtualcam:$VIRTUALCAM" "nas:$NAS" "printing:$PRINTING" "greeter:$GREETER" "networkmanager:$NETWORKMANAGER" "networkmanager-rollback:$NM_ROLLBACK"; do
    if [ "${flag#*:}" = 1 ] && ! stage_selected "${flag%%:*}"; then warn "--${flag%%:*} has no effect: the stage is not selected by --only"; fi
  done
  if [ -n "$TZ_WANT" ] && ! stage_selected timezone; then warn "--timezone has no effect: the stage is not selected by --only"; fi
}

needs_root() { # any selected stage with sudo=yes
  local n
  for n in $SELECTED; do [ "$(stage_field "$n" 3)" = yes ] && return 0; done
  return 1
}

main() {
  if [ "$LIST_STAGES" = 1 ]; then list_stages; exit 0; fi
  select_stages
  # Preflight (OS check, sudo prompt) only when a selected stage needs root; user-config-only runs never prompt.
  if needs_root; then preflight; fi
  local n
  for n in $SELECTED; do "$(stage_field "$n" 2)"; done
  # A root stage can rely on a newer hyprdeb CLI than the installed one (the user stage deploys it): say so instead of leaving a stale CLI.
  if needs_root && ! stage_selected settings && [ -f "$HOME/.local/bin/hyprdeb" ] && ! cmp -s "$REPO/bin/hyprdeb" "$HOME/.local/bin/hyprdeb"; then
    warn "the installed hyprdeb CLI ($HOME/.local/bin/hyprdeb) is older than the repo: run ./install.sh --config-only"
  fi
  if [ -n "$ONLY" ] && [ "$CONFIG_ONLY" = 0 ]; then
    log "Done: $(echo $SELECTED)"
    return 0
  fi
  if systemctl is-enabled --quiet greetd.service 2>/dev/null; then
    log "Done. The login screen (greetd) starts the desktop at boot; do not run start-hyprland by hand while it is up."
  else
    log "Done. Start the desktop from a TTY with: start-hyprland"
  fi
}
main
