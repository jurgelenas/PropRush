-- Razor: a tight course of flicks: north up a three-gate chicane, a right hairpin round a flag, down through a
-- stack's bottom and back up through its top, out and back through a side-by-side pair, and home round a flag.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)

local Map = {
  spawn = { x = 0, y = 0, z = -2, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene

local W, H = 3, 2.4
local gates = {}
local function gate(x, z, y0, alongX)
  gates[#gates + 1] = Course.addGate(scene, x, z, W, H, y0, alongX)
end
-- Flag at x, z passed on the side dx, dz points to
local function flag(x, z, dx, dz)
  gates[#gates + 1] = Course.addFlag(scene, x, z, dx, dz)
end

gate(0, 8, 0.5, true)
-- Chicane: 10 m left and right every 16 m
gate(-5, 24, 0.5, true)
gate(5, 40, 1.5, true)
gate(-5, 56, 0.5, true)
flag(6, 72, 0, 1)
-- Stack: bottom flown south, a right hairpin round the flag below it, then the top north
local stack = Course.addFrame(scene, 16, 40, W, H, 0.5, true, 1, 2)
gates[#gates + 1] = stack[1]
flag(16, 25, 1, 0)
gates[#gates + 1] = stack[2]
-- Pair: the west opening north, a right hairpin round the flag, the east one back south
local pair = Course.addFrame(scene, 29, 56, W, H, 0.5, true, 2, 1)
gates[#gates + 1] = pair[1]
flag(29, 68, 0, 1)
gates[#gates + 1] = pair[2]
gate(30, 22, 1.5, true)
-- Right round the flag past the pad into the start
flag(16, -4, 0, -1)
Map.gates = gates

-- Sheds west of the chicane, a mast east of the pair
scene.addBox(-16, 32, 8, 5, 4)
scene.addBox(-15, 44, 4, 4, 3)
scene.addBox(42, 46, 2, 2, 12)

local RIDGE = Ground.newRing({ 2, 3.5, 1, 2.5, 4, 2, 1.5, 3, 5, 2.5, 1, 2, 3.5, 1.5, 2.5, 4 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(RIDGE, Ground.horizon(quality))
  Ground.drawPad(0, -2)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 60 m of the course centre (the farthest flags are 40 m out), lost at 150 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 14, 32, 60, 150)
end

return Map
