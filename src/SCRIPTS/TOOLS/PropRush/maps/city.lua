-- City: a downtown of six blocks either side of an avenue running north, with a stepped tower, an arch block,
-- twin towers joined by a skybridge over the avenue, a slot between two towers and a spire on a podium, ringed
-- by low blocks and a skyline.

local Ground, Scene, Gap, R, load = ...

local Map = {
  spawn = { x = 0, y = 0, z = -20, heading = 0 },
}

-- Blocks PITCH metres square; the ground grid has the same spacing, so its lines run down the roads
local PITCH = 50
-- Street grid: 4 x 5 blocks from its south-west corner, the downtown the middle 2 x 3
local SX, SZ, COLS, ROWS = -100, -50, 4, 5
local Streets = load("world/streets", R)
local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Stepped tower, setbacks at 18 and 36 m
local stepped = scene.addStructure()
stepped:add(-25, 25, 30, 30, 18, 0)
stepped:add(-25, 25, 22, 22, 18, 18)
stepped:add(-25, 25, 12, 12, 16, 36)

-- Arch block: a 10 m wide passage, 9 m high, through its ground floor from south to north
local arch = scene.addStructure()
arch:add(14, 25, 12, 30, 9, 0)
arch:add(36, 25, 12, 30, 9, 0)
arch:add(25, 25, 34, 30, 21, 9)
gaps[#gaps + 1] = Gap.new("ARCH", 10, 20, 0, 25, 30, 9, 25)

-- Twin towers either side of the avenue, the skybridge between them 40 m up
scene.addBox(-25, 75, 18, 18, 72)
scene.addBox(25, 75, 18, 18, 72)
scene.addBox(0, 75, 32, 4, 3, 40)
gaps[#gaps + 1] = Gap.new("SKYBRIDGE", 10, -16, 28, 75, 16, 40, 75)

-- Two towers with a 4 m slot between them, flown south to north
scene.addBox(-33.5, 125, 13, 26, 44)
scene.addBox(-16.5, 125, 13, 26, 38)
gaps[#gaps + 1] = Gap.new("SLOT", 15, -27, 0, 125, -23, 38, 125)

-- Spire on a podium, the tallest in town
local spire = scene.addStructure()
spire:add(25, 125, 34, 34, 8, 0)
spire:add(25, 125, 14, 14, 82, 8)

-- Low blocks round the downtown: {x, z, width, depth, height}
-- stylua: ignore
local LOW = {
  -75, 25, 30, 30, 14,   -75, 75, 26, 34, 20,   -75, 125, 34, 24, 10,
  75, 25, 34, 26, 16,    75, 75, 30, 30, 9,     75, 125, 26, 34, 24,
  -25, -25, 30, 16, 6,   -25, 175, 30, 30, 18,  25, 175, 34, 20, 12,
}
for i = 1, #LOW, 5 do
  scene.addBox(LOW[i], LOW[i + 1], LOW[i + 2], LOW[i + 3], LOW[i + 4])
end

-- Skyline: towers as {azimuth where it starts, height in degrees} around the compass, each a flat top between
-- two vertical steps
-- stylua: ignore
local BLOCKS = {
  0, 2.4, 6, 5, 9, 3, 18, 7.5, 21, 3.6, 30, 1.8, 44, 4.2, 50, 2.2, 66, 6, 70, 2.6, 85, 1.4, 104, 3.4,
  112, 8.5, 114.5, 4, 126, 2, 147, 5.2, 153, 2.8, 170, 1.6, 196, 3.8, 204, 6.4, 209, 2.4, 226, 4.6,
  240, 1.8, 258, 7, 261, 3.2, 278, 5, 286, 2, 302, 3.6, 318, 9, 320, 4.4, 333, 2.4, 347, 5.6,
}
local elevations, azimuths = {}, {}
for i = 1, #BLOCKS, 2 do
  local n = #azimuths
  azimuths[n + 1], elevations[n + 1] = BLOCKS[i], BLOCKS[i + 1]
  azimuths[n + 2], elevations[n + 2] = BLOCKS[i + 2] or 359.9, BLOCKS[i + 1]
end
local SKYLINE = Ground.newRing(elevations, azimuths)

function Map.draw(quality)
  Ground.drawGrid(quality, PITCH)
  Ground.drawRing(SKYLINE, Ground.horizon(quality))
  Streets.draw(quality, SX, SZ, COLS, ROWS, PITCH)
  Ground.drawPad(0, -20)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 120 m of the downtown centre (its corners are 90 m out), lost at 220 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 75, 120, 220)
end

return Map
