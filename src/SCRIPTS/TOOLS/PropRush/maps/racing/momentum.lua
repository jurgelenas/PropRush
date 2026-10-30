-- Momentum: a fast snake north up the east side over a hurdle, out through a twin gate, a left U-turn round a flag
-- and back through its other side, then a wider snake south down the west over a high and a low hurdle into the
-- start.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)

local Map = {
  spawn = { x = 0, y = 0, z = -10, heading = 0 },
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

gate(0, 10, 0.5, true)
flag(18, 36, 1, 0)
gate(6, 62, 4, true)
flag(22, 88, 1, 0)
-- Out north through the east side, back south through the west
local twin = Course.addFrame(scene, 12, 114, W, H, 1, true, 2, 1)
gates[#gates + 1] = twin[2]
flag(12, 134, 0, 1)
gates[#gates + 1] = twin[1]
flag(-10, 96, -1, 0)
gate(-30, 72, 6, true)
flag(-14, 48, 1, 0)
gate(-34, 24, 2.5, true)
flag(-20, -10, 0, -1)
Map.gates = gates

-- Barn east of the first snake, a mast between the snakes, a shed beyond the U-turn
scene.addBox(42, 60, 10, 8, 6)
scene.addBox(-6, 30, 2, 2, 12)
scene.addBox(-24, 128, 6, 5, 4)

-- Low ridges: a flatter horizon than the hills
local RIDGE = Ground.newRing({ 1, 1.5, 2.5, 1, 0.5, 1.5, 2, 1, 2, 3, 1.5, 0.5, 1, 2, 1.5, 1 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(RIDGE, Ground.horizon(quality))
  Ground.drawPad(0, -10)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 90 m of the course centre (the U-turn flag is 74 m out), lost at 175 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, -4, 62, 90, 175)
end

return Map
