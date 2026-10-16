# Security

## Reporting a problem

Please report vulnerabilities **privately**: use *Report a vulnerability* on the repository's **Security** tab
(<https://github.com/dani-io/hyprdeb/security>). If that is not available to you, open an issue that says only "security
report, please contact me" and give no details; you will be asked for a private channel. Do not post exploits or credentials in
a public issue.

This is a one-person project. Expect an answer within a few days, not hours.

## What runs with more privilege than you

Most of hyprdeb is a user-level CLI and configuration. Three things are different:

1. **`install.sh`** runs `sudo` for the system stages you select. Read `./install.sh --dry-run` first; it prints every
   privileged command. It adds apt sources for Google Chrome and Visual Studio Code only when those stages run.
2. **`hyprdeb-nas`**, a root helper behind `hyprdeb-nas.socket` (installed by `--nas`).
3. **`hyprdeb-net-guard`**, a root service that reverts an unconfirmed network change (installed by `--networkmanager`).

### `hyprdeb-nas`

- The socket `/run/hyprdeb-nas.sock` is `0660 root:sudo`. One helper process per connection, at most 6 at once and 3 per client.
  The peer must be a normal user (uid 1000..59999); root is refused on the socket.
- Input is **one JSON line** of at most 16 KiB, read within 30 s, validated before anything else:
  share name `^[a-z0-9][a-z0-9-]{0,14}$` (the mount point is always `/mnt/NAME`), server (IPv4 or host name), share
  `[A-Za-z0-9_.-]{1,80}`, user `[A-Za-z0-9_.-]{1,64}`, password 1..128 characters without control characters, idle time
  `off` or 30 s..24 h. Unknown fields (a mount point, a uid, a command) are refused.
- **Every request** is authorised with polkit (`org.hyprdeb.nas.manage`, administrator password, `auth_admin_keep`) for the process
  that connected, identified by pid, start time and uid. There is no skip path on the socket.
- The password arrives on stdin only. It is written to `/etc/hyprdeb/nas-NAME.credentials` (root, `0600`, created exclusively and
  renamed into place) or passed on stdin to `smbclient -A /dev/stdin`. It is never in argv, the environment, `settings.toml`, a
  log, a reply or a notification. A **stored** password is only used again for the same share, server and user name; a request
  that names another server or user must carry a new password, so a stored secret can never be sent to a host you did not type it
  for.
- Units are created from fixed templates (`mnt-NAME.mount` / `.automount`, options `vers=3.0`, `nofail`, `_netdev`); only the
  automount is enabled. Removing a share never forces an unmount.
- The service runs without capabilities and with `ProtectSystem=strict` (writable: `/etc/hyprdeb`, `/etc/systemd/system`,
  `/mnt`), `PrivateTmp`, `PrivateDevices`, `ProtectHome`, a system-call filter, `MemoryDenyWriteExecute`, restricted address
  families and a 400 s runtime limit. Left open on purpose: it is root (it writes `/etc` and talks to systemd) and it may open
  TCP connections (the Test button connects to the server you typed).

### `hyprdeb-net-guard`

- Started by `hyprdeb-net-guard.path` when `/run/hyprdeb-net/pending.json` exists. The token is data: at most 4 KiB, a regular file
  (opened with `O_NOFOLLOW`, checked on the open descriptor), owned by root or group `netdev`, not world-writable; a deadline more
  than 310 s away is refused.
- Every value is validated. Only profiles named `hyprdeb-<interface>` are touched, never `hyprdeb-wg-*` (VPN) profiles, and only
  wired (`802-3-ethernet`) ones. `nmcli` gets an argument list, never a shell. A malformed token is removed with a log line.
- Members of `netdev` can already change NetworkManager connections through its own polkit rules; the guard adds a way back, not
  a new way in.

### Other

- WireGuard keys are stored only in the NetworkManager system profile (root-owned); the CLI never prints them and scrubs the
  clipboard history of a pasted configuration.
- hyprdeb never downloads proprietary drivers (Canon, for example). Chrome's and VS Code's apt keys are fetched over HTTPS;
  Microsoft's is checked against its published fingerprints.

## Supported versions

Only the latest commit on `main`.
