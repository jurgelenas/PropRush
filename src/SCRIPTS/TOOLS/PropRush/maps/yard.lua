-- Yard: a building site. A half-built concrete frame with a slot left in its upper floor, a tower crane to dive from with its load hanging off the jib, and stacked shipping containers.

local Ground, Scene, Gap = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 120

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Frame 24 x 12 m round (FX, FZ): two 3.5 m storeys with 0.4 m slabs on a 3 x 2 grid of columns, the third storey
-- only its corner columns. The upper slab stops short of the east bay, leaving a 3 m slot across it.
local FX, FZ = 0, 45
local STOREY, SLAB, COL = 3.5, 0.4, 0.8
local FLOOR2 = STOREY + SLAB
local TOP = 2 * STOREY + SLAB
local frame = scene.addStructure()
for storey = 0, 1 do
  for _, x in ipairs({ -11.6, 0, 11.6 }) do
    frame:add(FX + x, FZ - 5.6, COL, COL, STOREY, storey * FLOOR2)
    frame:add(FX + x, FZ + 5.6, COL, COL, STOREY, storey * FLOOR2)
  end
end
for _, x in ipairs({ -11.6, 11.6 }) do
  frame:add(FX + x, FZ - 5.6, COL, COL, STOREY, TOP + SLAB)
  frame:add(FX + x, FZ + 5.6, COL, COL, STOREY, TOP + SLAB)
end
frame:add(FX, FZ, 24, 12, SLAB, STOREY)
frame:add(FX - 4.5, FZ, 15, 12, SLAB, TOP)
frame:add(FX + 9, FZ, 6, 12, SLAB, TOP)
gaps[#gaps + 1] = Gap.new("FLOOR 1", 10, FX - 12, 0, FZ, FX + 12, STOREY, FZ)
gaps[#gaps + 1] = Gap.new("FLOOR 2", 10, FX - 12, FLOOR2, FZ, FX + 12, TOP, FZ)
gaps[#gaps + 1] = Gap.new("FLOOR SLOT", 15, FX + 3, TOP + SLAB, FZ - 6, FX + 6, TOP + SLAB, FZ + 6)

-- Tower crane south-east of the frame: a 32 m mast, the jib reaching west along the frame's front with a
-- counterweight on its short end, and a peak over the mast
local CX, CZ, CH = 24, 30, 32
local crane = scene.addStructure()
crane:add(CX, CZ, 2, 2, CH, 0)
crane:add(CX - 13, CZ, 46, 1.2, 1.4, CH)
crane:add(CX + 7, CZ, 4, 2, 1.6, CH + 1.4)
crane:add(CX, CZ, 1, 1, 4, CH + 1.4)
-- Load of beams hanging 12 m up on the hook, 12 m off the mast: the gap between the cable and the mast
local HX, HY = CX - 12, 12
local hook = scene.addStructure()
hook:add(HX, CZ, 1, 3, 0.8, HY)
hook:add(HX, CZ, 0.08, 0.08, CH - HY - 0.8, HY + 0.8)
gaps[#gaps + 1] = Gap.new("CRANE", 10, HX + 0.5, 0, CZ, CX - 1, CH, CZ)

-- Containers 2.4 x 2.6 m, 6 m long running north, stacked east of the frame: a stack of three beside one of two,
-- a 2 m slot between them, and further north a 12 m one across two more, an opening under it
local CONT = 2.6
scene.addBox(40, 50, 2.4, 6, 3 * CONT)
scene.addBox(44.4, 50, 2.4, 6, 2 * CONT)
gaps[#gaps + 1] = Gap.new("BOX SLOT", 15, 41.2, 0, 50, 43.2, 2 * CONT, 50)
local portal = scene.addStructure()
portal:add(40, 64, 2.4, 6, CONT, 0)
portal:add(48, 64, 2.4, 6, CONT, 0)
portal:add(44, 64, 12, 2.4, CONT, CONT)
gaps[#gaps + 1] = Gap.new("PORTAL", 10, 41.2, 0, 64, 46.8, CONT, 64)
scene.addBox(-30, 58, 6, 2.4, CONT)

-- Skyline: blocks as {azimuth where it starts, height in degrees} around the compass; the narrow tall ones are
-- cranes on other sites. Each block is a flat top between two vertical steps.
-- stylua: ignore
local BLOCKS = {
  0, 2, 12, 3.2, 20, 1.4, 33, 6.5, 34, 2.4, 48, 4, 58, 1.8, 75, 3, 90, 5.4, 97, 2, 118, 1.2, 131, 7.5,
  132.5, 3.4, 145, 2.2, 161, 4.4, 172, 1.6, 189, 2.8, 205, 5, 214, 2, 232, 1.4, 247, 3.6, 262, 6.8, 263.5, 2.6,
  280, 1.2, 296, 4.2, 311, 2.4, 327, 3.2, 344, 1.6,
}
local elevations, azimuths = {}, {}
for i = 1, #BLOCKS, 2 do
  local n = #azimuths
  azimuths[n + 1], elevations[n + 1] = BLOCKS[i], BLOCKS[i + 1]
  azimuths[n + 2], elevations[n + 2] = BLOCKS[i + 2] or 359.9, BLOCKS[i + 1]
end
local SKYLINE = Ground.newRing(elevations, azimuths)

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(SKYLINE, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 90 m of the site (the containers are 45 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 20, 45, 90, 180)
end

return Map
