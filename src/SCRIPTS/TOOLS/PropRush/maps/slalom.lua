-- Slalom: three lines of flags woven left and right, flown north, south and north again: right at the top of the
-- first, left at the bottom of the second, then left back west over the top and a left hairpin into the start.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)

local Map = {
  spawn = { x = 0, y = 0, z = -12, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene

local W, H = 3, 2.4
local gates = {}
local function gate(x, z, y0, alongX)
  gates[#gates + 1] = Course.addGate(scene, x, z, W, H, y0, alongX)
end
-- Flags along x = x0 at each z, passed on the side dx alternating from the first
local function slalom(x0, dx, z0, z1, step)
  for z = z0, z1, step do
    gates[#gates + 1] = Course.addFlag(scene, x0, z, dx, 0)
    dx = -dx
  end
end

gate(0, 12, 0.5, true)
-- Flown north out of the last hairpin, though the gate before lies north of it
Course.dir(gates[1], 1)
slalom(0, 1, 35, 75, 20)
gate(12, 92, 1, false)
gate(32, 76, 4, true)
slalom(30, 1, 60, 30, -15)
gate(45, 12, 0.5, false)
slalom(60, 1, 40, 60, 20)
-- High, then back west over the top and south down the first line's far side
gate(60, 92, 5, true)
gate(-25, 70, 1, true)
Map.gates = gates

scene.addBox(15, 52, 3, 3, 14)
scene.addBox(45, 50, 3, 3, 14)
scene.addBox(-40, 40, 10, 6, 5)
scene.addBox(90, 60, 8, 8, 7)

-- Low ridges: a flatter horizon than the hills
local RIDGE = Ground.newRing({ 1, 2, 1.5, 2.5, 1, 0.5, 1.5, 3, 2, 1, 1.5, 2, 1, 0.5, 2, 2.5 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(RIDGE, Ground.horizon(quality))
  Ground.drawPad(0, -12)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 90 m of the course centre (the far corners are 80 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 20, 50, 90, 180)
end

return Map
