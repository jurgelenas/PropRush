-- Halo: a clockwise circle round a two-storey tower: a hairpin from the start into its top opening, the orbit
-- through a dive gate and round flags with the tower inside each turn, back down through its bottom opening the
-- other way.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)

local Map = {
  spawn = { x = -10, y = 0, z = 30, heading = 180 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene

local W, H = 3, 2.4
local tower = Course.addFrame(scene, 0, 52, W, H, 0.5, true, 1, 2)
local gates = {}
local function gate(x, z, y0, alongX)
  gates[#gates + 1] = Course.addGate(scene, x, z, W, H, y0, alongX)
end
-- Flag at x, z passed on the side dx, dz points to
local function flag(x, z, dx, dz)
  gates[#gates + 1] = Course.addFlag(scene, x, z, dx, dz)
end

-- Flown south, then a left hairpin round the flag and a climb north into the top opening
gate(-10, 10, 0.5, true)
flag(-3, -3, 0, -1)
gates[#gates + 1] = tower[2]
gate(20, 74, 1.5, false)
-- High, then 6 m lower 18 m on
gate(40, 56, 6, true)
gate(37, 38, 0.5, true)
flag(24, 28, 0, -1)
-- West across the middle, then north up the west side
gate(-14, 40, 1, false)
gate(-32, 46, 1, true)
flag(-14, 72, 0, 1)
gates[#gates + 1] = tower[1]
Map.gates = gates

-- Shed by the start, a mast outside the dive, a water tank beyond the west gate
scene.addBox(-30, 4, 8, 5, 4)
scene.addBox(58, 50, 3, 3, 14)
scene.addBox(-50, 62, 6, 6, 7)

local RIDGE = Ground.newRing({ 2, 1, 1.5, 3, 2.5, 1, 0.5, 1.5, 2, 1, 2.5, 3.5, 2, 1, 1.5, 2.5 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(RIDGE, Ground.horizon(quality))
  Ground.drawPad(-10, 30)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 70 m of the tower, lost at 160 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 2, 38, 70, 160)
end

return Map
