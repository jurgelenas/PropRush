local getValue = getValue

local DEADBAND = 0.01

local Input = {
  sticks = { ail = 0, ele = 0, thr = 0, rud = 0 },
}

local function axis(name)
  local v = getValue(name) / 1024
  if v > 1 then
    return 1
  elseif v < -1 then
    return -1
  elseif v > -DEADBAND and v < DEADBAND then
    return 0
  end
  return v
end

-- Throttle maps from stick bottom (-1) .. top (1) to 0..1
function Input.read()
  local s = Input.sticks
  s.ail = axis("ail")
  s.ele = axis("ele")
  s.rud = axis("rud")
  s.thr = (axis("thr") + 1) / 2
  return s
end

return Input
