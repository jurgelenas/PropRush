-- Wind Farm: two turbines turning on open hills, one of them low, a power line on lattice pylons running down to a
-- substation, a met mast and an open hay barn.

local Ground, Scene, Gap, R, load = ...
local Kit = load("world/windfarm", R, Scene)

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Turbines facing south, their rotors 4 m in front of the towers. Each disc scores above and below the hub,
-- through rectangles inside it.
local function turbine(x, z, h, l, phase)
  Kit.addTurbine(scene, x, z, h, l, phase)
  local zr, u, v = z - 4, 0.6 * l, 0.75 * l
  gaps[#gaps + 1] = Gap.new("ROTOR", 20, x - u, h - v, zr, x + u, h - 1.5, zr)
  gaps[#gaps + 1] = Gap.new("ROTOR", 20, x - u, h + 1.5, zr, x + u, h + v, zr)
end
turbine(-30, 55, 24, 10, 0)
turbine(42, 50, 14, 8, math.pi / 3)

-- Power line along x = -65 from the north down to the substation, under the lines between the pylons
local LX = -65
local LINE = { 90, 40, -10 }
for i, z in ipairs(LINE) do
  Kit.addPylon(scene, LX, z)
  gaps[#gaps + 1] = Gap.new("PYLON", 15, LX - 1.3, 0, z, LX + 1.3, 4.5, z)
  local nz = LINE[i + 1]
  if nz then
    Kit.addSpan(scene, LX, z, Kit.HANG, LX, nz, Kit.HANG, true)
    gaps[#gaps + 1] = Gap.new("WIRES", 10, LX, 0, nz + 4, LX, 9, z - 4)
  end
end

-- Substation: two transformers, a control room and the gantry the line comes down to
local GZ, BEAM = -34, 10
local gantry = scene.addStructure()
gantry:add(LX - Kit.ARM, GZ, 0.4, 0.4, BEAM, 0)
gantry:add(LX + Kit.ARM, GZ, 0.4, 0.4, BEAM, 0)
gantry:add(LX, GZ, 2 * Kit.ARM + 0.4, 0.4, 0.5, BEAM)
Kit.addSpan(scene, LX, -10, Kit.HANG, LX, GZ, BEAM, false)
scene.addBox(LX - 4, -40, 3, 4, 3.5)
scene.addBox(LX + 4, -40, 3, 4, 3.5)
scene.addBox(LX + 8, -45, 5, 4, 3)

-- Met mast 30 m tall
scene.addBox(30, 18, 0.3, 0.3, 30)

-- Hay barn: a roof on six posts, open on every side
local BX, BZ, EAVE = -22, 14, 5
local barn = scene.addStructure()
for _, dx in ipairs({ -4, 4 }) do
  for _, dz in ipairs({ -6, 0, 6 }) do
    barn:add(BX + dx, BZ + dz, 0.3, 0.3, EAVE, 0)
  end
end
barn:add(BX, BZ, 9, 13, 0.4, EAVE)
scene.addBox(BX + 2, BZ + 4, 4, 2.4, 2)
gaps[#gaps + 1] = Gap.new("BARN", 10, BX - 3.8, 0, BZ - 2, BX + 3.8, EAVE - 0.1, BZ - 2)

-- Rolling hills, higher than the farm's
local HILLS =
  Ground.newRing({ 4, 6, 5, 3, 4.5, 7, 6, 3.5, 2.5, 4, 5.5, 8, 6.5, 4, 3, 5, 7, 5.5, 3.5, 2.5, 4, 6, 4.5, 3 })

local turn = Kit.turn

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(HILLS, Ground.horizon(quality))
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

-- Video link: clean within 100 m of the middle of the farm (the pylons are 90 m out), lost at 190 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, -10, 30, 100, 190)
end

return Map
