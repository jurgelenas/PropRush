-- Old Mill: a tower mill with a gallery, its sails turning slowly over flat land, a canal with a lift bridge, and a
-- farmhouse with a hay barrack.

local Ground, Scene, Gap, R, load = ...
local Kit = load("world/mills", R, Scene)

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Tower mill facing south, its sails resting as an X. The sails score above and below the hub, through rectangles
-- inside their disc; the gallery along under its south side.
local TX, TZ = 0, 45
Kit.addTowerMill(scene, TX, TZ, math.pi / 4)
local zs, hub, u, v = TZ - Kit.TOWER_FACE, Kit.TOWER_HUB, 0.6 * Kit.TOWER_SAIL, 0.75 * Kit.TOWER_SAIL
gaps[#gaps + 1] = Gap.new("SAILS", 20, TX - u, hub - v, zs, TX + u, hub - 1.5, zs)
gaps[#gaps + 1] = Gap.new("SAILS", 20, TX - u, hub + 1.5, zs, TX + u, hub + v, zs)
gaps[#gaps + 1] = Gap.new("GALLERY", 15, TX + 3, 0, TZ - Kit.POST + 0.3, TX + 3, Kit.GALLERY - 0.15, TZ - 4.15)

-- Canal along x, its banks as lines
local CANAL_Z, BANK = 74, 4
-- Lift bridge across it: a deck along z, the portal on the south bank carrying the balance beams that lift it, a
-- counterweight on their back ends and chains down to the deck's far end from their front ends
local BX, DECK, PZ, TOP = -15, 2, 69, 9.5
local bridge = scene.addStructure()
for _, dx in ipairs({ -2.4, 2.4 }) do
  bridge:add(BX + dx, PZ, 0.4, 0.4, DECK, 0)
  bridge:add(BX + dx, PZ, 0.4, 0.4, TOP - DECK, DECK)
  bridge:add(BX + dx, 71.25, 0.3, 17.5, 0.4, TOP + 0.5)
end
bridge:add(BX, 74, 4, 14, 0.4, DECK)
bridge:add(BX, PZ, 5.3, 0.5, 0.5, TOP)
bridge:add(BX, 63.25, 4.5, 1.5, 0.6, TOP + 0.5)
-- stylua: ignore
local CHAINS = { BX - 2.4, TOP + 0.5, 80, BX - 1.8, DECK + 0.4, 80.8, BX + 2.4, TOP + 0.5, 80, BX + 1.8, DECK + 0.4, 80.8 }
gaps[#gaps + 1] = Gap.new("BRIDGE", 10, BX, 0.1, CANAL_Z - BANK + 0.3, BX, DECK - 0.1, CANAL_Z + BANK - 0.3)
gaps[#gaps + 1] = Gap.new("PORTAL", 10, BX - 2.1, DECK + 0.5, PZ, BX + 2.1, TOP - 0.1, PZ)

-- Farmhouse 12 x 8 m, low walls under a tall roof stepping in to the ridge, its chimney on the east end
local house = scene.addStructure()
house:add(35, 18, 12, 8, 3.5, 0)
house:add(35, 18, 12.6, 5, 2.5, 3.5)
house:add(35, 18, 11.6, 2, 2, 6)
scene.addBox(41.9, 18, 1, 1, 9)

-- Hay barrack: a roof on four tall poles over a stack of hay, flown through between them
local HX, HZ, ROOF = 16, 26, 4.8
local barrack = scene.addStructure()
for _, dx in ipairs({ -2.2, 2.2 }) do
  for _, dz in ipairs({ -2.2, 2.2 }) do
    barrack:add(HX + dx, HZ + dz, 0.24, 0.24, ROOF, 0)
    barrack:add(HX + dx, HZ + dz, 0.24, 0.24, 1.8, ROOF + 0.4)
  end
end
barrack:add(HX, HZ, 3.6, 3.6, 2.2, 0)
barrack:add(HX, HZ, 5, 5, 0.4, ROOF)
barrack:add(HX, HZ, 2.6, 2.6, 0.6, ROOF + 0.4)
gaps[#gaps + 1] = Gap.new("BARRACK", 10, HX - 2, 2.3, HZ, HX + 2, ROOF - 0.1, HZ)

-- Flat land, low tree lines and farms on the horizon
local SKYLINE = Ground.newRing({ 1, 1.5, 1, 0.5, 1, 2, 1.5, 1, 0.5, 1, 1.5, 1, 2.5, 1, 0.5, 1 })

local turn, line = Kit.turn, R.line

local function drawCanal()
  line(-150, 0, CANAL_Z - BANK, 150, 0, CANAL_Z - BANK, 4)
  line(-150, 0, CANAL_Z + BANK, 150, 0, CANAL_Z + BANK, 4)
  for i = 1, #CHAINS, 6 do
    line(CHAINS[i], CHAINS[i + 1], CHAINS[i + 2], CHAINS[i + 3], CHAINS[i + 4], CHAINS[i + 5], 4)
  end
end

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(SKYLINE, Ground.horizon(quality))
  drawCanal()
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(dt, _)
  turn(dt)
end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 100 m of the middle, lost at 190 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 5, 45, 100, 190)
end

return Map
