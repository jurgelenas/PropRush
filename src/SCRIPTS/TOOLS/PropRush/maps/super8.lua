-- Super 8: a figure of eight crossing itself in a cube, flown north through it, right round the north-east loop,
-- west through it, then left round the south-west loop, a mast in the middle of each loop.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)

local Map = {
  spawn = { x = 0, y = 0, z = -20, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene

local W, H = 3, 2.4
-- Crossing: a 4 m cube 1.5 m up, entered through its south face, then later its east face
local cube = Course.addCube(scene, 0, 0, 4, 1.5)
Map.gates = {
  cube.s,
  -- North-east loop, quarter turns of 20 to 25 m: east along the top, then high, south down the side
  Course.addGate(scene, 20, 45, W, H, 1, false),
  Course.addGate(scene, 45, 20, W, H, 4.5, true),
  cube.e,
  -- South-west loop: low, south down the side, then east along the bottom and north into the cube
  Course.addGate(scene, -45, -20, W, H, 0.5, true),
  Course.addGate(scene, -20, -45, W, H, 2, false),
}

-- Masts to turn round
scene.addBox(22, 22, 2, 2, 12)
scene.addBox(-22, -22, 2, 2, 12)

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  Ground.drawPad(0, -20)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 70 m of the cube (the farthest gates are 49 m out), lost at 160 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 0, 70, 160)
end

return Map
