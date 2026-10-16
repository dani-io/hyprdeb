-- Move the active window to the monitor on its left / right. Hyprland picks the target by direction, so no
-- output names are needed. Pressing the key when there is no monitor on that side does nothing: the dispatch
-- itself would fail with "Invalid monitor" (a yellow Lua runtime-error notification, or a configerrors line).
local function move_window_to(dir)
  local win = hl.get_active_window()
  local cur = win and win.monitor
  if not cur then return end
  local found = false
  for _, m in ipairs(hl.get_monitors()) do
    if m.id ~= cur.id then
      -- logical (scaled) geometry, the same space as the monitor positions
      local cur_w, m_w = cur.width / cur.scale, m.width / m.scale
      if dir == "r" and m.x >= cur.x + cur_w then found = true end
      if dir == "l" and m.x + m_w <= cur.x then found = true end
    end
  end
  if found then hl.dispatch(hl.dsp.window.move({ monitor = dir })) end
end

hl.bind("SUPER + SHIFT + left",  function() move_window_to("l") end, { description = "Windows: Move the window to the monitor on the left" })
hl.bind("SUPER + SHIFT + right", function() move_window_to("r") end, { description = "Windows: Move the window to the monitor on the right" })
