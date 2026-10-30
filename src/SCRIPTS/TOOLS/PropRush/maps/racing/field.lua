-- Field: a fast, open course snaking left and right round a barn and silo: north, a right then a left round two
-- flags into a high gate that dives into a low one, a left hairpin over the top, an S-bend back west and a left
-- hairpin round a flag into the start.

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
gate(4, 42.5, 1, true)
-- Right round the first flag, left round the second, both on the outside
flag(17, 59.5, -1, 0)
gate(42.5, 66.5, 1.5, false)
flag(64, 75, 0, -1)
-- High, then 7 m lower 19.5 m on
gate(72, 98, 7, true)
gate(72, 117.5, 0.5, true)
-- Left hairpin round the flag, then right and left again
flag(59.5, 136, 0, 1)
gate(38, 119, 2, true)
gate(13, 98, 1.5, false)
gate(-25.5, 72, 1, true)
-- Mid height, then the left hairpin round the flag north into the start
gate(-25.5, 25.5, 3, true)
flag(-13, -6, 0, -1)
Map.gates = gates

-- Barn between the straights out and back, a silo inside the top hairpin, hay bales by the second gate
scene.addBox(-12, 49.5, 12, 8, 7)
scene.addBox(52.5, 112, 4, 4, 15)
scene.addBox(12, 37.5, 1.6, 1.2, 1.2)
scene.addBox(12, 40.5, 1.6, 1.2, 1.2)
scene.addBox(12, 39, 1.6, 1.2, 1.2, 1.2)

-- Low ridges: a flatter horizon than the hills
local RIDGE = Ground.newRing({ 1.5, 1, 2, 1.5, 0.5, 1, 2.5, 2, 1, 1.5, 0.5, 1, 2, 3, 1.5, 1 })

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

-- Video link: clean within 95 m of the course centre (the top flag is 85 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 25.5, 64, 95, 180)
end

return Map
