-- Farm: a lane up through tall pines to a barn-roofed farmhouse with a porch, a wing and an open shed, past a fenced
-- paddock with jumps to fly under, in a clearing among hills.

local Ground, Scene, Gap, R, load = ...
local Farm = load("world/farm", R, Scene)
local Fence = load("world/fence", R, Scene)

local Map = {
  spawn = { x = 2, y = 0, z = -50, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- stylua: ignore
local LANE = Farm.newLane({ 0, -58, 3, -40, 1, -22, -3, -5, -1, 12, 3, 28, 4, 40 }, 1.8)

-- Farmhouse 11 x 8 m facing south, walls 5 m, the barn roof's steep lower slopes up to 8 m and the ridge at 9.8
-- stylua: ignore
local house = Farm.addBuilding(scene, 4, 52, 11, 8, 5, { -4.3, 5, -3.1, 8, 0, 9.8, 3.1, 8, 4.3, 5 }, true, false)
Farm.addDormer(house, 1.5, 48.9, 1.6, 1.8, 2, 5.8, -1)
Farm.addDormer(house, 6.5, 48.9, 1.6, 1.8, 2, 5.8, -1)
scene.addBox(10.2, 52, 1.4, 1.4, 11.5)
-- Wing on the west end, lower, with a pitched roof
Farm.addBuilding(scene, -4.5, 53, 6, 6, 3, { -3.2, 3, 0, 5.2, 3.2, 3 }, true, false)
scene.addBox(-4.5, 49.4, 6, 0.8, 1)
-- Porch along the front: a roof on four posts, flown along under it
local porch = scene.addStructure()
for _, x in ipairs({ -1.3, 2.2, 5.8, 9.3 }) do
  porch:add(x, 45.8, 0.2, 0.2, 2.8, 0)
end
porch:add(4, 46.8, 11, 2.4, 0.25, 2.8)
gaps[#gaps + 1] = Gap.new("PORCH", 15, 4, 0, 45.9, 4, 2.75, 47.9)

-- Long shed east of the yard, open at both ends
Farm.addBuilding(scene, 22, 50, 5, 16, 2.6, { -2.8, 2.6, 0, 4.2, 2.8, 2.6 }, false, true)
gaps[#gaps + 1] = Gap.new("SHED", 10, 19.9, 0, 50, 24.1, 2.5, 50)

-- Paddock east of the lane, its fence following the lane's edge up to the yard
-- stylua: ignore
Fence.add(scene, { 9, -58, 9, -40, 7, -22, 3, -5, 5, 12, 9, 28, 14, 38, 60, 38, 60, -58, 9, -58 })

-- Jumps in the paddock: a rail on two posts, flown under
local RAIL = 1.2
local function jump(x, z, alongX)
  local j = scene.addStructure()
  local u, v = alongX and 1.6 or 0, alongX and 0 or 1.6
  j:add(x - u, z - v, 0.15, 0.15, RAIL, 0)
  j:add(x + u, z + v, 0.15, 0.15, RAIL, 0)
  j:add(x, z, alongX and 3.35 or 0.12, alongX and 0.12 or 3.35, 0.12, RAIL)
  gaps[#gaps + 1] = Gap.new("JUMP", 5, x - u, 0, z - v, x + u, RAIL, z + v)
end
jump(30, 15, true)
jump(42, -25, false)

-- Trees as x, z, canopy base, top, canopy radius, tiers: tall pines along the lane and in the woods, broad trees
-- by the spawn
-- stylua: ignore
Farm.addGrove(scene, {
  -7, -46, 2.5, 10, 3.5, 2,
  -11, -37, 2, 9, 3, 2,
  -4, -50, 7, 15, 1.8, 2,
  -4, -27, 7, 15, 1.8, 2,
  -6, -16, 8, 16, 1.8, 2,
})
-- stylua: ignore
Farm.addGrove(scene, {
  -8, -4, 7, 15, 1.8, 2,
  2, 0, 8, 15, 1.6, 2,
  -7, 8, 7, 14, 1.8, 2,
  -4, 20, 8, 16, 1.8, 2,
  -2, 32, 7, 15, 1.8, 2,
})
-- stylua: ignore
Farm.addGrove(scene, {
  -18, -52, 8, 16, 2, 2,
  -26, -44, 7, 15, 1.8, 2,
  -16, -32, 8, 17, 2, 2,
  -15, -6, 7, 15, 1.8, 2,
})
-- stylua: ignore
Farm.addGrove(scene, {
  -20, 6, 7, 15, 1.8, 2,
  -16, 20, 8, 17, 2, 2,
  -24, 44, 8, 16, 2, 2,
  -16, 58, 7, 15, 1.8, 2,
})
-- stylua: ignore
Farm.addGrove(scene, {
  -6, 66, 8, 16, 2, 2,
  4, 72, 7, 15, 1.8, 2,
  14, 66, 8, 17, 2, 2,
  32, 64, 8, 16, 2, 2,
})

-- The only kit function the map keeps: the builders are let go once the farm is built
local drawLane = Farm.drawLane

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  drawLane(LANE, quality)
  Ground.drawPad(2, -50)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 90 m of the middle of the farm (the house is 55 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 15, 0, 90, 180)
end

return Map
