local gfx = ...

local format, floor = string.format, math.floor

local Hud = {}

-- Strings are rebuilt only when the shown number changes
local batVal, batStr, altVal, altStr, spdVal, spdStr

local function throttleBar(thr)
  local x, y0, y1 = 0, gfx.FH + 2, gfx.H - gfx.FH - 3
  local h = y1 - y0
  gfx.rect(x, y0, 4, h + 1, 0)
  gfx.rect(x + 1, y0, 1, h + 1, 4)
  local fill = floor(h * thr + 0.5)
  if fill > 0 then
    gfx.rect(x + 1, y1 - fill + 1, 2, fill, 4)
  end
  -- Hover point: thrust-to-weight 4.5 hovers at ~22 %
  local hy = y1 - floor(h * 0.22 + 0.5)
  gfx.rect(x, hy, 4, 1, 4)
end

-- goal: top-right text (e.g. "PTS 1460") or nil; message: centred banner or nil
function Hud.draw(q, settings, goal, message)
  local W, H, FH = gfx.W, gfx.H, gfx.FH

  gfx.rect(0, 0, W, FH + 1, 0)
  local bat = floor(q.battery * 100 + 0.5)
  if bat ~= batVal then
    batVal, batStr = bat, format("BAT %d%%", bat)
  end
  gfx.text(1, 1, batStr)
  gfx.text(W / 2, 1, settings.angleMode and "ANGLE" or "ACRO", "c")
  if goal then
    gfx.text(W - 1, 1, goal, "r")
  end

  gfx.rect(0, H - FH - 1, W, FH + 1, 0)
  local alt = floor(q.py + 0.5)
  if alt ~= altVal then
    altVal, altStr = alt, format("ALT %dm", alt)
  end
  gfx.text(1, H - FH, altStr)
  local spd = floor(q:speed() * 3.6 + 0.5)
  if spd ~= spdVal then
    spdVal, spdStr = spd, format("%dkmh", spd)
  end
  gfx.text(W - 1, H - FH, spdStr, "r")

  throttleBar(q.throttle)

  local cx, cy = floor(W / 2), floor(H / 2)
  gfx.rect(cx - 3, cy, 1, 1, 4)
  gfx.rect(cx, cy, 1, 1, 4)
  gfx.rect(cx + 3, cy, 1, 1, 4)

  if message then
    gfx.text(W / 2, cy - 12, message, "c", true, true)
  end
end

return Hud
