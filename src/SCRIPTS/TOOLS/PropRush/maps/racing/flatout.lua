-- Flat Out: a fast road circuit painted on the ground: up the long main straight over a hurdle, a right-left
-- chicane, a long right, a left-right chicane, two quick rights onto the back straight under a bridge and over a
-- hurdle, a left-right-left and a long tightening right onto the straight.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)
local Circuit = load("world/circuit", R)

local Map = {
  spawn = { x = 20, y = 0, z = 5, heading = 0 },
}

local GRID = 60

-- Road laid from the final corner's exit (X0, Z0) heading north, off the ground grid's lines (see world/circuit);
-- start line START along it
local X0, Z0, START = 20, -3, 28
-- stylua: ignore
local LAYOUT = {
  109.01, 0, 6, 65, 2, 0, 6, -65, 10, 0,
  20, 90, 3.52, 0, 8, -50, 2, 0, 8, 50, 6, 0,
  9, 45, 8, 0, 9, 45, 80, 0,
  10, -30, 10, 80, 10, -50, 20, 0,
  40, 90, 22, 90,
}

local scene = Scene.new()
Map.scene = scene

local HALF = Circuit.HALF
local W, H = 3, 2.4
local gates = {}
local function gate(x, z, y0, alongX)
  gates[#gates + 1] = Course.addGate(scene, x, z, W, H, y0, alongX)
end
-- Flag at x, z passed on the side dx, dz points to
local function flag(x, z, dx, dz)
  gates[#gates + 1] = Course.addFlag(scene, x, z, dx, dz)
end

-- Bridge over the back straight at BX, BZ, BD deep: piers off the road edges, its deck BH up; scored through its
-- south face
local BX, BZ, BD, BH = 86.5, 106, 5, 4.5
local bridge = scene.addStructure()
bridge:add(BX - HALF - 0.75, BZ, 1.5, BD, BH, 0)
bridge:add(BX + HALF + 0.75, BZ, 1.5, BD, BH, 0)
bridge:add(BX, BZ, 2 * HALF + 3, BD, 0.8, BH)

gate(X0, Z0 + START, 0.5, true)
gate(X0, 58, 4, true)
-- First chicane in and out, the long right's apex
gate(18, 100, 1, true)
gate(28.7, 121, 1, true)
flag(38.5, 138, -1, 0)
-- Second chicane in and out, the first quick right's apex, the second's exit
gate(50.5, 147.7, 1, false)
gate(68.5, 155, 1, false)
flag(73.1, 149.2, 0, 1)
gate(BX, 133, 1, true)
local face = Gap.new("GATE", 0, BX - HALF, 0, BZ - BD / 2, BX + HALF, BH, BZ - BD / 2)
-- Marker: centre and top (see Course opening), not part of a piece
face[9], face[10], face[11], face[12], face[13] = BX, BH / 2, BZ - BD / 2, BH, false
gates[#gates + 1] = face
gate(BX, 80, 4, true)
-- Left-right-left apex and exit
flag(83.5, 49.5, 1, 0)
gate(82, 27, 1, true)
-- The long right's apexes: halfway round and the tighter end
flag(67.1, -10.1, 0, -1)
flag(30.3, -14.7, 0, -1)
Map.gates = gates

-- Grandstand along the straight, pits across from it
scene.addBox(7, 40, 4, 40, 5)
scene.addBox(31, 30, 5, 24, 3.5)

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  Circuit.draw(quality, LAYOUT, X0, Z0, 0, START)
  Ground.drawPad(X0, 5)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 100 m of the circuit's centre, lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 52, 66, 100, 180)
end

return Map
