-- Flatpak: add its export dirs to XDG_DATA_DIRS for everything Hyprland starts (launcher, waybar, terminals).
-- Debian's zsh does not read /etc/profile.d/flatpak.sh, so the login shell never sets this.
-- An unset/empty value means the spec default /usr/local/share:/usr/share, which must stay in the list
-- (dropping it breaks waybar and empties hyprlauncher). Dirs already present are skipped, so a config
-- reload (which sees the value set here) does not add them twice. Does nothing without flatpak.
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if exists("/usr/bin/flatpak") then
  local dirs = os.getenv("XDG_DATA_DIRS")
  if not dirs or dirs == "" then dirs = "/usr/local/share:/usr/share" end
  -- Prepended in this order so the user installation comes first, as in flatpak.sh.
  for _, d in ipairs({ "/var/lib/flatpak/exports/share", os.getenv("HOME") .. "/.local/share/flatpak/exports/share" }) do
    if not (":" .. dirs .. ":"):find(":" .. d .. ":", 1, true) then dirs = d .. ":" .. dirs end
  end
  hl.env("XDG_DATA_DIRS", dirs)
end
