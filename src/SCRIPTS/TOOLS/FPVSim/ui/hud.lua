local gfx = ...

local format, floor = string.format, math.floor

local Hud = {}

-- Tenths of a volt per cell
local LOW_CELL = 33

-- Strings are rebuilt only when the shown number changes
local batVal, batStr, altVal, altStr, spdVal, spdStr

-- goal: top-right text (e.g. "PTS 1460") or nil; message: centred banner or nil
function Hud.draw(q, settings, goal, message)
  local W, H, FH = gfx.W, gfx.H, gfx.FH

  gfx.rect(0, 0, W, FH + 1, 0)
  local bat = floor(q.voltage * 10 + 0.5)
  if bat ~= batVal then
    batVal, batStr = bat, format("%.1fV", bat / 10)
  end
  -- Blinks below LOW_CELL like a flight controller OSD warning
  if bat >= LOW_CELL or getTime() % 100 < 60 then
    gfx.text(1, 1, batStr)
  end
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

  local cx, cy = floor(W / 2), floor(H / 2)
  gfx.rect(cx - 3, cy, 1, 1, 4)
  gfx.rect(cx, cy, 1, 1, 4)
  gfx.rect(cx + 3, cy, 1, 1, 4)

  if message then
    gfx.text(W / 2, cy - 12, message, "c", true, true)
  end
end

return Hud
