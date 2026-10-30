-- Tech: a tight course up a ladder rung by rung, a split-S through a cube, a weave through a triple gate and a pole.

local Ground, Scene, Course = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene

local start = Course.addGate(scene, 0, 22, 3, 2.4, 0.5, true)
-- Rungs 3 x 2, bottom first, all flown north, going round the east side between them
local ladder = Course.addFrame(scene, 0, 45, 3, 2, 0.5, true, 1, 3)
-- Dived into heading north and left through the south face, heading back
local cube = Course.addCube(scene, 8, 70, 4, 2)
-- Openings side by side along z, south first: woven from the north one, east, west, east
local triple = Course.addFrame(scene, 30, 50, 3, 2.4, 0.5, false, 3, 1)
Map.gates = {
  start,
  ladder[1],
  Course.around(ladder[1], 1),
  ladder[2],
  Course.around(ladder[2], 1),
  ladder[3],
  cube.top,
  cube.s,
  triple[3],
  triple[2],
  triple[1],
  Course.addFlag(scene, 55, 28, 1, 0),
  -- High, flown west, then a turn north into the start
  Course.addGate(scene, 22, 4, 3, 2.4, 3, false),
}

scene.addBox(-30, 70, 6, 6, 10)
scene.addBox(75, 60, 10, 8, 6)

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 70 m of the course centre, lost at 160 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 20, 50, 70, 160)
end

return Map
