-- Harbor: a ship moored along the quay under a container crane, sheds and containers on the quay, a pier on piles,
-- a tug, and a breakwater across the north with a lighthouse on its end and a gap for the harbour mouth.

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

-- Ship 50 x 10 m running north, bridge and funnel aft, a mast forward
local ship = scene.addStructure()
ship:add(0, 45, 10, 50, 5, 0)
ship:add(0, 63, 10, 8, 7, 5)
ship:add(0, 63, 2.5, 2.5, 4, 12)
ship:add(0, 28, 0.4, 0.4, 8, 5)

-- Container crane: four 14 m legs straddling the quay, the boom 16 m up reaching west over the ship
local CX, CZ, LEG = 19, 40, 14
local crane = scene.addStructure()
for _, dx in ipairs({ -5, 5 }) do
  crane:add(CX + dx, CZ - 6, 0.8, 0.8, LEG, 0)
  crane:add(CX + dx, CZ + 6, 0.8, 0.8, LEG, 0)
  crane:add(CX + dx, CZ, 0.8, 12.8, 1, LEG)
end
crane:add(CX - 6, CZ, 38, 2, 1.5, LEG + 1)
gaps[#gaps + 1] = Gap.new("CRANE", 10, CX, 0, CZ - 5.6, CX, LEG, CZ + 5.6)

-- Containers stacked by the crane
scene.addBox(32, 36, 2.4, 6, 5.2)
scene.addBox(32, 44, 2.4, 6, 2.6)

-- Sheds on the quay with a 3 m slot between them
scene.addBox(20, 12, 12, 10, 7)
scene.addBox(35, 12, 12, 10, 7)
gaps[#gaps + 1] = Gap.new("SHEDS", 15, 27.5, 0, 12, 27.5, 7, 12)

-- Pier on piles 10 m apart, its deck 2.5 m up
local PX, PY = -22, 2.5
local pier = scene.addStructure()
pier:add(PX, 25, 5, 50, 0.5, PY)
for z = 0, 50, 10 do
  pier:add(PX - 2.2, z, 0.4, 0.4, PY, 0)
  pier:add(PX + 2.2, z, 0.4, 0.4, PY, 0)
end
gaps[#gaps + 1] = Gap.new("PIER", 15, PX, 0, 10.2, PX, PY, 19.8)

-- Tug off the pier
local tug = scene.addStructure()
tug:add(-34, 40, 3.5, 9, 1.5, 0)
tug:add(-34, 41, 2.5, 3, 2, 1.5)

-- Breakwater with a 6 m harbour mouth, the lighthouse on its west end
local BZ, WALL = 90, 2
scene.addBox(-36, BZ, 44, 4, WALL)
scene.addBox(14, BZ, 44, 4, WALL)
gaps[#gaps + 1] = Gap.new("MOUTH", 10, -14, 0, BZ, -8, WALL, BZ)
local light = scene.addStructure()
light:add(-60, BZ, 4, 4, 14, 0)
light:add(-60, BZ, 2.4, 2.4, 3, 14)
light:add(-60, BZ, 3.2, 3.2, 0.5, 17)

-- Far shore round the harbour
local SHORE = Ground.newRing({ 2, 1.5, 1, 1.5, 2.5, 2, 1, 1, 1.5, 3, 2.5, 1.5, 1, 2, 1.5, 2.5 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(SHORE, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 95 m of the quay (the lighthouse is 90 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 45, 95, 180)
end

return Map
