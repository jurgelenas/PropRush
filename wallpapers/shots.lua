-- Wallpaper stills for trailer/trailer.lua (SHOTS=wallpapers/shots.lua): each a held camera, frame 25 kept, except
-- the car chase. wallpapers/wallpapers.sh renders them 600 wide and crops a 360 x 800 portrait out of each.

local shot, findObject = ...

local function still(name, mode, map, x, y, z, ax, ay, az)
  shot({
    name = name,
    mode = mode,
    map = map,
    voltage = 3.9,
    keys = { { 0, x, y, z }, { 1, x, y + 0.1, z + 0.5 } },
    duration = 1,
    aim = function()
      return ax, ay, az, 1
    end,
    aimPitch = true,
    cam = 0,
    level = 1,
    wobble = 0,
    hud = false,
  })
end

still("city-skybridge", "freestyle", "city", 0, 25, -90, 0, 38, 75)
still("vibetown", "freestyle", "vibetown", 0, 30, -60, 0, 6, 50)
still("yard-crane", "freestyle", "yard", 62, 20, -35, 11, 17, 30)
still("apex", "racing", "apex", 17, 12, 11, 20, 0, 53)
still("flatout", "racing", "flatout", 17, 12, 11, 20, 0, 49.5)

-- Chasing the drift car 17 m behind and 7 m up, looking 18 m past it
local BACK, UP, AHEAD = 17, 7, 18
local function behind(x, z, h)
  return x - BACK * math.sin(h), z - BACK * math.cos(h)
end
shot({
  name = "car-chase",
  mode = "freestyle",
  map = "drift",
  voltage = 3.95,
  record = function(Map, last)
    local car = findObject(Map, 17)
    local h = car[16]
    if last then
      h = h + 2 * math.pi * math.floor((last[3] - h) / (2 * math.pi) + 0.5)
    end
    return { car[12], car[13], h }
  end,
  sigma = 0.08,
  pos = function(t, rec)
    local x, z, h = rec(t)
    local px, pz = behind(x, z, h)
    return px, UP, pz
  end,
  aim = function(t, rec)
    local x, z, h = rec(t)
    local px, pz = behind(x, z, h)
    local k = AHEAD / BACK
    return x + (x - px) * k, 1, z + (z - pz) * k, 1
  end,
  aimPitch = true,
  level = 1,
  cam = 0,
  wobble = 0,
  lead = 1.2,
  duration = 7,
  hud = false,
})
