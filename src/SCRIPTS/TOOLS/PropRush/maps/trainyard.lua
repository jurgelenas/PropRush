-- Trainyard: a freight train running back and forth on the main line, past a station platform under a canopy, a
-- footbridge and a signal gantry across the tracks, wagons parked on a siding, an engine shed open at both ends, a
-- coal stage and a water tower.

local Ground, Scene, Gap, R = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Tracks along x: the platform line, the main line, the siding and the shed road. Rails as x0, x1, z per track,
-- GAUGE apart.
local PLATFORM_Z, MAIN_Z, SIDING_Z, SHED_Z = 22, 30, 38, 60
local GAUGE = 1.5
-- stylua: ignore
local TRACKS = { -120, 120, PLATFORM_Z, -120, 120, MAIN_Z, 20, 100, SIDING_Z, -100, -30, SHED_Z }

-- Station: the building, and a platform 1 m up with a canopy over it on two rows of posts
local CAN = 4.5
scene.addBox(-30, 17, 40, 4, 1)
scene.addBox(-40, 10, 14, 4, 4)
local canopy = scene.addStructure()
for _, x in ipairs({ -42, -34, -26, -18 }) do
  canopy:add(x, 15.5, 0.3, 0.3, CAN - 1, 1)
  canopy:add(x, 18.5, 0.3, 0.3, CAN - 1, 1)
end
canopy:add(-30, 17, 30, 4, 0.3, CAN)
gaps[#gaps + 1] = Gap.new("CANOPY", 10, -44, 1, 15.7, -44, CAN - 0.1, 18.3)

-- Footbridge over all the tracks on two stair towers
local FX, DECK = 30, 7
local bridge = scene.addStructure()
bridge:add(FX, 10, 3, 3, DECK + 0.5, 0)
bridge:add(FX, 50, 3, 3, DECK + 0.5, 0)
bridge:add(FX, 30, 2.5, 37, 0.5, DECK)
gaps[#gaps + 1] = Gap.new("FOOTBRIDGE", 10, FX, 0, 12, FX, DECK, 48)

-- Signal gantry, a signal hanging over each line
local SX, BEAM = -60, 7
local gantry = scene.addStructure()
gantry:add(SX, 14, 0.5, 0.5, BEAM, 0)
gantry:add(SX, 46, 0.5, 0.5, BEAM, 0)
for _, z in ipairs({ PLATFORM_Z, MAIN_Z, SIDING_Z }) do
  gantry:add(SX, z, 0.5, 0.6, 1.2, BEAM - 1.2)
end
gantry:add(SX, 30, 0.5, 32.5, 0.6, BEAM)
gaps[#gaps + 1] = Gap.new("GANTRY", 10, SX, 0, 14.3, SX, BEAM - 1.3, 45.7)

-- Wagons parked on the siding with a slot between them, a buffer stop at its end
local WAGON_H = 3.8
scene.addBox(66, SIDING_Z, 12, 3, WAGON_H)
scene.addBox(80.5, SIDING_Z, 12, 3, WAGON_H)
scene.addBox(101, SIDING_Z, 1, 3, 1.2)
gaps[#gaps + 1] = Gap.new("SIDING", 15, 72.1, 0, SIDING_Z, 74.4, WAGON_H, SIDING_Z)

-- Engine shed over the shed road, open at both ends
local HX, ROOF = -60, 6
local shed = scene.addStructure()
shed:add(HX, SHED_Z - 5, 30, 0.4, ROOF, 0)
shed:add(HX, SHED_Z + 5, 30, 0.4, ROOF, 0)
shed:add(HX, SHED_Z, 30, 10.4, 0.6, ROOF)
gaps[#gaps + 1] = Gap.new("SHED", 15, HX, 0, SHED_Z - 4.7, HX, ROOF - 0.1, SHED_Z + 4.7)

-- Coal stage, and the water tower: a tank on four legs
scene.addBox(-25, 68, 8, 4, 4)
local water = scene.addStructure()
for _, dx in ipairs({ -1.5, 1.5 }) do
  water:add(-85 + dx, 43.5, 0.3, 0.3, 6, 0)
  water:add(-85 + dx, 46.5, 0.3, 0.3, 6, 0)
end
water:add(-85, 45, 4, 4, 3, 6)

-- Signal box by the line
scene.addBox(50, 10, 5, 4, 6)

-- Train on the main line: wagons with slots between them and the locomotive on the east end, as offsets from the
-- west end, lengths and heights. Arrays: [1..11] as a box's; [12] the west end's x.
-- stylua: ignore
local CARS = { 0, 12, WAGON_H, 14.5, 12, WAGON_H, 29, 12, WAGON_H, 43.5, 16, 4.2 }
local LENGTH, HALF = 59.5, 1.5
-- Runs between these west end positions at SPEED, waiting PAUSE at each end
local X0, X1, SPEED, PAUSE = -80, 30, 8, 4
local tx, dir, wait = -35, 1, 0

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }
local function car(t, i)
  local x0 = t[12] + CARS[i]
  BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] = x0, 0, MAIN_Z - HALF, x0 + CARS[i + 1], CARS[i + 2], MAIN_Z + HALF
  return BOX
end

local function drawCar(t, i, shade, edge)
  local b = car(t, i)
  if R.sphereVisible((b[1] + b[4]) / 2, b[5] / 2, MAIN_Z, CARS[i + 1] / 2 + 2) then
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
  end
end

-- In a line along x: those west of the camera from the west end, then those east of it from the east end
local function drawTrain(t, fogged)
  local shade, edge = fogged and Scene.FAR_SHADE or Scene.SHADE, fogged and Scene.FAR_EDGE or Scene.EDGE
  local ox = R.cameraPos()
  local n = #CARS
  for i = 1, n, 3 do
    if t[12] + CARS[i] + CARS[i + 1] / 2 < ox then
      drawCar(t, i, shade, edge)
    end
  end
  for i = n - 2, 1, -3 do
    if t[12] + CARS[i] + CARS[i + 1] / 2 >= ox then
      drawCar(t, i, shade, edge)
    end
  end
end

local function trainCollides(t, x, y, z)
  if not Scene.touches(t, x, y, z) then
    return false
  end
  for i = 1, #CARS, 3 do
    local b = car(t, i)
    if Scene.touches(b, x, y, z) then
      return b
    end
  end
  return false
end

local function trainNear(t, x, y, z, d2)
  if Scene.distance2(t, x, y, z) >= d2 then
    return false
  end
  for i = 1, #CARS, 3 do
    if Scene.distance2(car(t, i), x, y, z) < d2 then
      return true
    end
  end
  return false
end

-- stylua: ignore
local train = scene.addObject(setmetatable({ 0, 0, MAIN_Z - HALF, 0, 4.2, MAIN_Z + HALF, 0, 2.1, MAIN_Z,
  math.sqrt(LENGTH * LENGTH + 4.2 * 4.2 + 4 * HALF * HALF) / 2, 0, 0 },
  { __index = { draw = drawTrain, collides = trainCollides, near = trainNear } }))
-- The slot between the first two wagons, moving with them
local slot = Gap.new("WAGONS", 20, 0, 0, MAIN_Z, 1, WAGON_H, MAIN_Z)
gaps[#gaps + 1] = slot

-- Bounds ([1], [4]) and sphere centre ([7]) follow the train
local function place(x)
  train[12], train[1], train[4], train[7] = x, x, x + LENGTH, x + LENGTH / 2
  -- u0, u1
  slot[3], slot[4] = x + 12.1, x + 14.4
end
place(tx)

-- Low sheds and trees round the yard
local SKYLINE = Ground.newRing({ 1, 1.5, 2, 1, 1.5, 2.5, 1, 1, 2, 1.5, 1, 2, 3, 1.5, 1, 1.5 })

local function drawRails()
  for i = 1, #TRACKS, 3 do
    local x0, x1, z = TRACKS[i], TRACKS[i + 1], TRACKS[i + 2]
    R.line(x0, 0, z - GAUGE / 2, x1, 0, z - GAUGE / 2, 4)
    R.line(x0, 0, z + GAUGE / 2, x1, 0, z + GAUGE / 2, 4)
  end
end

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(SKYLINE, Ground.horizon(quality))
  drawRails()
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(dt, _)
  if wait > 0 then
    wait = wait - dt
    return
  end
  tx = tx + dir * SPEED * dt
  if tx > X1 or tx < X0 then
    tx = tx > X1 and X1 or X0
    dir, wait = -dir, PAUSE
  end
  place(tx)
end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 110 m of the yard (the train turns back 90 m out), lost at 200 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 35, 110, 200)
end

return Map
