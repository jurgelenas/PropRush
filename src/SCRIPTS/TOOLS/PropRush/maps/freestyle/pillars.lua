local Ground, Scene = ...

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local scene = Scene.new()
Map.scene = scene

for i = 0, 7 do
  local a = i * math.pi / 4
  scene.addBox(math.sin(a) * 30, math.cos(a) * 30 + 60, 2, 2, 8 + (i % 3) * 4)
end
scene.addBox(-25, 110, 16, 10, 14)
scene.addBox(30, 120, 10, 18, 22)

function Map.draw(quality)
  Ground.drawGrid(quality)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 150 m of the pillar ring, lost at 400 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 0, 60, 150, 400)
end

return Map
