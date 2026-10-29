local Kit, R = ...

local Map = {
  name = "PILLARS",
  mode = "freestyle",
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local scene = Kit.newScene()
Map.scene = scene

for i = 0, 7 do
  local a = i * math.pi / 4
  scene.addBox(math.sin(a) * 30, math.cos(a) * 30 + 60, 2, 2, 8 + (i % 3) * 4)
end
scene.addBox(-25, 110, 16, 10, 14)
scene.addBox(30, 120, 10, 18, 22)

-- Launch pad: a square with a cross, centred on the spawn point
local PAD = 1.5

local function drawPad()
  R.line(-PAD, 0, -PAD, PAD, 0, -PAD, 4)
  R.line(PAD, 0, -PAD, PAD, 0, PAD, 4)
  R.line(PAD, 0, PAD, -PAD, 0, PAD, 4)
  R.line(-PAD, 0, PAD, -PAD, 0, -PAD, 4)
  R.line(-PAD, 0, -PAD, PAD, 0, PAD, 4)
  R.line(PAD, 0, -PAD, -PAD, 0, PAD, 4)
end

function Map.draw(quality)
  Kit.drawGrid(quality)
  Kit.drawRing(Kit.HILLS, Kit.horizon(quality))
  drawPad()
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 150 m of the pillar ring, lost at 400 m
function Map.signalLoss(x, y, z)
  return Kit.rangeLoss(x, y, z, 0, 60, 150, 400)
end

return Map
