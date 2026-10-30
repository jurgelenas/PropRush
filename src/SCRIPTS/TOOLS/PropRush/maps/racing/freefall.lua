-- Freefall: a climb north and right to a 9 m gate, a split-S down through the top of a cube and back out the face
-- it was approached from into a low gate, a right turn round a flag over the top into switchbacks, a ladder flown
-- top rung first, a chicane south and a right turn round a flag into the start.

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
gate(6, 38, 3.5, true)
-- 8.5 m up, then down through the cube's top, 6.5 m up 14 m on, and back out west, north of the high gate's posts
gate(20, 60, 8.5, false)
local cube = Course.addCube(scene, 34, 66, 4, 2.5)
gates[#gates + 1] = cube.top
gates[#gates + 1] = cube.w
gate(8, 72, 0.5, false)
-- Right round the flag on its west, east over the top, then switchbacks: right round a flag, back west through a
-- gate, left round a flag and east again
flag(-6, 92, -1, 0)
gate(20, 104, 0.5, false)
flag(42, 104, 0, 1)
gate(28, 92, 2, false)
flag(12, 86, 0, 1)
gate(32, 80, 0.5, false)
-- Ladder flown south top rung first, round its east side between rungs
local ladder = Course.addFrame(scene, 52, 68, W, H, 0.5, true, 1, 3)
gates[#gates + 1] = ladder[3]
gates[#gates + 1] = Course.around(ladder[3], 1)
gates[#gates + 1] = ladder[2]
gates[#gates + 1] = Course.around(ladder[2], 1)
gates[#gates + 1] = ladder[1]
-- Chicane 5 m left and right every 16 m, high, low, mid, then west and right round the flag into the start
gate(55, 52, 4.5, true)
gate(50, 36, 0.5, true)
gate(55, 20, 3, true)
gate(32, 2, 1, false)
flag(12, -6, 0, -1)
Map.gates = gates

-- Water tower beside the climb, a shed west of the chicane, a hut west of the start
scene.addBox(26, 46, 3, 3, 14)
scene.addBox(36, 36, 6, 10, 4)
scene.addBox(-8, 40, 5, 7, 3)

local RIDGE = Ground.newRing({ 2, 3.5, 2.5, 1, 1.5, 3, 4, 2, 1, 2.5, 3.5, 1.5, 1, 2, 3, 2.5 })

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

-- Video link: clean within 85 m of the course centre (the hairpin is 70 m out), lost at 170 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 24, 44, 85, 170)
end

return Map
