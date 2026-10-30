-- Vibe Town: a small-town square. Shops either side of the main street running north under a sign arch, an alley
-- between two of them, a clock tower, a petrol station, a parking garage, a water tower on legs, a billboard on
-- posts and an overpass across the far end.

local Ground, Scene, Gap = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Shops: two storeys west of the street with a 3 m alley between two of them, lower ones east of it
scene.addBox(-14, 24, 10, 12, 7)
scene.addBox(-14, 39, 10, 12, 7)
scene.addBox(-14, 56, 10, 14, 5)
gaps[#gaps + 1] = Gap.new("ALLEY", 15, -14, 0, 30, -14, 7, 33)
scene.addBox(16, 28, 10, 16, 4)
scene.addBox(16, 50, 10, 12, 6)

-- Sign on the low shop's roof: a 2 m board on two 3 m posts
local SY = 5
local sign = scene.addStructure()
sign:add(-17.5, 56, 0.3, 0.3, 3, SY)
sign:add(-10.5, 56, 0.3, 0.3, 3, SY)
sign:add(-14, 56, 8, 0.3, 2, SY + 3)
gaps[#gaps + 1] = Gap.new("ROOF SIGN", 15, -17.35, SY, 56, -10.65, SY + 3, 56)

-- Sign arch over the street into town
local arch = scene.addStructure()
arch:add(-6, 15, 1, 1, 7, 0)
arch:add(6, 15, 1, 1, 7, 0)
arch:add(0, 15, 13, 1, 1.5, 7)
gaps[#gaps + 1] = Gap.new("ARCH", 10, -5.5, 0, 15, 5.5, 7, 15)

-- Bus shelter by the square
scene.addBox(8, 8, 4, 1.5, 2.5)

-- Clock tower on the square, a spire on top
local clock = scene.addStructure()
clock:add(-10, 8, 3, 3, 18, 0)
clock:add(-10, 8, 1.6, 1.6, 4, 18)

-- Petrol station: a 12 x 8 m canopy 4.5 m up on four posts, the kiosk behind it
local PX, PZ, CAN = 32, 10, 4.5
local canopy = scene.addStructure()
for _, dx in ipairs({ -5, 5 }) do
  canopy:add(PX + dx, PZ - 3, 0.4, 0.4, CAN, 0)
  canopy:add(PX + dx, PZ + 3, 0.4, 0.4, CAN, 0)
end
canopy:add(PX, PZ, 12, 8, 0.6, CAN)
gaps[#gaps + 1] = Gap.new("CANOPY", 10, PX - 4.8, 0, PZ, PX + 4.8, CAN, PZ)
scene.addBox(PX, PZ + 9, 8, 5, 3)

-- Parking garage 16 x 20 m: two open decks and the roof, 3 m apart, on a 3 x 2 grid of columns
local GX, GZ, LEVEL, SLAB = -40, 30, 3, 0.4
local garage = scene.addStructure()
for _, dx in ipairs({ -7.6, 0, 7.6 }) do
  garage:add(GX + dx, GZ - 9.6, 0.8, 0.8, 2 * LEVEL + SLAB, 0)
  garage:add(GX + dx, GZ + 9.6, 0.8, 0.8, 2 * LEVEL + SLAB, 0)
end
garage:add(GX, GZ, 16, 20, SLAB, LEVEL)
garage:add(GX, GZ, 16, 20, SLAB, 2 * LEVEL + SLAB)
gaps[#gaps + 1] = Gap.new("LEVEL 1", 10, GX + 8, 0, GZ - 9.2, GX + 8, LEVEL, GZ + 9.2)
gaps[#gaps + 1] = Gap.new("LEVEL 2", 10, GX + 8, LEVEL + SLAB, GZ - 9.2, GX + 8, 2 * LEVEL + SLAB, GZ + 9.2)

-- Water tower: a 7 m tank 14 m up on four legs
local WX, WZ, LEG = 42, 62, 14
local water = scene.addStructure()
for _, dx in ipairs({ -2.5, 2.5 }) do
  water:add(WX + dx, WZ - 2.5, 0.5, 0.5, LEG, 0)
  water:add(WX + dx, WZ + 2.5, 0.5, 0.5, LEG, 0)
end
water:add(WX, WZ, 7, 7, 5, LEG)
gaps[#gaps + 1] = Gap.new("WATER", 10, WX, 0, WZ - 2.25, WX, LEG, WZ + 2.25)

-- Billboard: a 12 x 4 m board facing south on two 6 m posts
local BX, BZ, POST = -34, 72, 6
local board = scene.addStructure()
board:add(BX - 5, BZ, 0.4, 0.4, POST, 0)
board:add(BX + 5, BZ, 0.4, 0.4, POST, 0)
board:add(BX, BZ, 12, 0.3, 4, POST)
gaps[#gaps + 1] = Gap.new("BILLBOARD", 10, BX - 4.8, 0, BZ, BX + 4.8, POST, BZ)

-- Overpass: a road deck 6 m up running east-west across the street, on two piers and end blocks
local OZ, DECK = 100, 6
local bridge = scene.addStructure()
bridge:add(0, OZ, 64, 8, 1, DECK)
bridge:add(-15, OZ, 1.5, 6, DECK, 0)
bridge:add(15, OZ, 1.5, 6, DECK, 0)
bridge:add(-30, OZ, 4, 8, DECK, 0)
bridge:add(30, OZ, 4, 8, DECK, 0)
gaps[#gaps + 1] = Gap.new("OVERPASS", 10, -14.25, 0, OZ, 14.25, DECK, OZ)

-- Low rooftops round the town
local ROOFS = Ground.newRing({ 1.5, 2, 1, 2.5, 1.5, 1, 2, 3, 1.5, 1, 2, 1.5, 2.5, 1, 1.5, 2 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(ROOFS, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 95 m of the square (the overpass is 100 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 50, 95, 180)
end

return Map
