local getValue, getFieldInfo = getValue, getFieldInfo

local settings = ...

local DEADBAND = 0.01
local DEFAULT = { roll = "ail", pitch = "ele", yaw = "rud", thr = "thr" }
local SRC, REV = {}, {}
for axis in pairs(DEFAULT) do
  SRC[axis], REV[axis] = axis .. "Src", axis .. "Rev"
end

local Input = {
  sticks = { ail = 0, ele = 0, thr = 0, rud = 0 },
}

local function idOf(name)
  local f = getFieldInfo(name)
  return f and f.id
end
Input.DEFAULT, Input.idOf = DEFAULT, idOf

-- Source ids resolved from the setting names, again only when a setting changes: reading by id skips the
-- firmware's name lookup each frame. A name this radio does not have falls back to the stick.
local names, ids = {}, {}
local function source(axis)
  local name = settings[SRC[axis]]
  if name ~= names[axis] then
    names[axis] = name
    ids[axis] = idOf(name) or idOf(DEFAULT[axis])
  end
  return ids[axis]
end

local function read(axis)
  local v = getValue(source(axis)) / 1024
  if v > 1 then
    v = 1
  elseif v < -1 then
    v = -1
  elseif v > -DEADBAND and v < DEADBAND then
    return 0
  end
  return settings[REV[axis]] and -v or v
end

-- Throttle maps from stick bottom (-1) .. top (1) to 0..1
function Input.read()
  local s = Input.sticks
  s.ail = read("roll")
  s.ele = read("pitch")
  s.rud = read("yaw")
  s.thr = (read("thr") + 1) / 2
  return s
end

return Input
