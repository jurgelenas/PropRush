-- Gates: a six-gate loop round a tower on open fields, low and high gates and a hard turn back to the start.

local World, Scene, Course = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

-- Ground grid spacing: wider than the default, so the gates stand out from the ground
local GRID = 60

local scene = Scene.new()
Map.scene = scene

-- Openings 3 x 2.4 m: as {x, z, bottom height, frame along x (flown north or south)} in course order
local W, H = 3, 2.4
-- stylua: ignore
local COURSE = {
  0, 12, 0.5, true,
  8, 55, 2, true,
  35, 80, 1, false,
  60, 50, 5, true,
  55, 10, 0.5, true,
  25, -15, 1.5, false,
}
local gates = {}
for i = 1, #COURSE, 4 do
  gates[#gates + 1] = Course.addGate(scene, COURSE[i], COURSE[i + 1], W, H, COURSE[i + 2], COURSE[i + 3])
end
Map.gates = gates

scene.addBox(32, 40, 6, 6, 20)
scene.addBox(75, 90, 12, 10, 8)
scene.addBox(-20, 70, 8, 14, 6)

function Map.draw(quality)
  World.drawGrid(quality, GRID)
  World.drawRing(World.HILLS, World.horizon(quality))
  World.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 150 m of the tower, lost at 400 m
function Map.signalLoss(x, y, z)
  return World.rangeLoss(x, y, z, 32, 40, 150, 400)
end

return Map
