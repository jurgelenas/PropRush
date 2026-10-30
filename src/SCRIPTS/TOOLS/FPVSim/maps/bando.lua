-- Bando: an abandoned mill. A two-storey concrete frame with half its roof fallen in, a chimney to dive, a
-- ruined facade with window gaps and a pipe bridge to fly under, against an industrial skyline.

local World, Scene, Course = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

-- Ground grid spacing: wider than the default, so the buildings stand out from the ground
local GRID = 120

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Mill frame, 30 x 14 m around (MX, MZ): two 4 m storeys with 0.5 m slabs on a 3 x 2 grid of columns. The
-- roof only covers the west half, so the east columns stand bare above the first floor.
local MX, MZ = 0, 50
local STOREY, SLAB, COL = 4, 0.5, 0.8
local mill = scene.addStructure()
for storey = 0, 1 do
  local y0 = storey * (STOREY + SLAB)
  for _, x in ipairs({ -14.6, 0, 14.6 }) do
    mill:add(MX + x, MZ - 6.6, COL, COL, STOREY, y0)
    mill:add(MX + x, MZ + 6.6, COL, COL, STOREY, y0)
  end
end
mill:add(MX, MZ, 30, 14, SLAB, STOREY)
mill:add(MX - 7.5, MZ, 15, 14, SLAB, 2 * STOREY + SLAB)
-- Through either storey across its middle, and through the fallen-in half of the roof
gaps[#gaps + 1] = Course.gap("GROUND FLOOR", 10, MX - 15, 0, MZ, MX + 15, STOREY, MZ)
gaps[#gaps + 1] = Course.gap("UPPER FLOOR", 10, MX - 15, STOREY + SLAB, MZ, MX + 15, 2 * STOREY + SLAB, MZ)
gaps[#gaps + 1] = Course.gap("ROOF HOLE", 5, MX, 2 * STOREY + SLAB, MZ - 7, MX + 15, 2 * STOREY + SLAB, MZ + 7)

-- Ruined facade along x at z = WZ: piers, window sills and a doorway as {width, height} from the west end
-- (height 0 leaves the doorway open), under one band over the openings
local WX, WZ, WALL = -34, 22, 0.6
local OPENING_TOP = 3.6
local BAYS = { 3, 3.6, 4, 1, 2.5, 3.6, 4, 0, 2.5, 3.6, 4, 1, 3, 3.6 }
local wall = scene.addStructure()
local x = WX
for i = 1, #BAYS, 2 do
  local w, h = BAYS[i], BAYS[i + 1]
  if h > 0 then
    wall:add(x + w / 2, WZ, w, WALL, h, 0)
  end
  if h < OPENING_TOP then
    gaps[#gaps + 1] = Course.gap(h > 0 and "WINDOW" or "DOORWAY", h > 0 and 10 or 5, x, h, WZ, x + w, OPENING_TOP, WZ)
  end
  x = x + w
end
wall:add((WX + x) / 2, WZ, x - WX, WALL, 2.4, OPENING_TOP)

-- Pipe bridge from beside the mill to a tower block, its deck 6 m up on two posts
local BRIDGE_Y, BRIDGE_Z = 6, MZ
local bridge = scene.addStructure()
bridge:add(32.25, BRIDGE_Z, 24.5, 2.5, 0.8, BRIDGE_Y)
bridge:add(25, BRIDGE_Z, 1, 1, BRIDGE_Y, 0)
bridge:add(39, BRIDGE_Z, 1, 1, BRIDGE_Y, 0)
gaps[#gaps + 1] = Course.gap("UNDER BRIDGE", 5, 25.5, 0, BRIDGE_Z, 38.5, BRIDGE_Y, BRIDGE_Z)
scene.addBox(50, MZ, 10, 10, 16)

scene.addBox(32, 85, 3, 3, 36)
scene.addBox(-7, 14, 2.5, 6, 2.6)
scene.addBox(10, 20, 6, 2.5, 2.6)

-- Skyline: blocks as {azimuth where it starts, height in degrees} around the compass; the narrow tall ones
-- are chimneys. Each block is a flat top between two vertical steps.
-- stylua: ignore
local BLOCKS = {
  0, 1.2, 10, 2.6, 21, 1.8, 30, 3.4, 37, 2.2, 52, 7, 54, 2.2, 63, 1, 80, 2.8, 96, 4.2, 104, 1.6,
  122, 3, 135, 1.2, 150, 2.4, 166, 6, 168, 2.4, 178, 3.6, 190, 1.4, 210, 2.8, 228, 1.8, 241, 4.6,
  249, 2, 265, 1, 284, 3.2, 300, 8, 301.5, 3.2, 309, 2, 326, 3.8, 340, 1.6,
}
local elevations, azimuths = {}, {}
for i = 1, #BLOCKS, 2 do
  local n = #azimuths
  azimuths[n + 1], elevations[n + 1] = BLOCKS[i], BLOCKS[i + 1]
  azimuths[n + 2], elevations[n + 2] = BLOCKS[i + 2] or 359.9, BLOCKS[i + 1]
end
local SKYLINE = World.newRing(elevations, azimuths)

function Map.draw(quality)
  World.drawGrid(quality, GRID)
  World.drawRing(SKYLINE, World.horizon(quality))
  World.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 150 m of the mill, lost at 400 m
function Map.signalLoss(x, y, z)
  return World.rangeLoss(x, y, z, MX, MZ, 150, 400)
end

return Map
