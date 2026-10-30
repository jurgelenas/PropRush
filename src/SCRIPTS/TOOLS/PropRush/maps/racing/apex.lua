-- Apex: a road circuit painted on the ground: start up the long main straight, a right hairpin, a fast left
-- sweeper, a left-right chicane, a right onto the esses, a right into the tunnel on the back straight and a tight
-- right onto the straight.

local Ground, Scene, Gap, R, load = ...
local Course = load("world/course", R, Scene, Gap)
local Circuit = load("world/circuit", R)

local Map = {
  spawn = { x = 20, y = 0, z = 5, heading = 0 },
}

local GRID = 60

-- Road laid from the final corner's exit (X0, Z0) heading north, off the ground grid's lines (see world/circuit);
-- start line START along it
local X0, Z0, START = 20, -3, 28
-- stylua: ignore
local LAYOUT = {
  98.7, 0, 11, 180, 4, 0, 24, -90, 10, 0,
  10, -40, 4, 0, 10, 40, 8, 0, 12, 90, 6, 0,
  14, 40, 14, -80, 14, 80, 14, -40, 4, 0,
  11, 90, 65.37, 0, 9, 90,
}

local scene = Scene.new()
Map.scene = scene

local HALF = Circuit.HALF
local W, H = 3, 2.4
local gates = {}
local function gate(x, z, y0, alongX)
  gates[#gates + 1] = Course.addGate(scene, x, z, W, H, y0, alongX)
end
-- Flag at x, z passed on the side dx, dz points to
local function flag(x, z, dx, dz)
  gates[#gates + 1] = Course.addFlag(scene, x, z, dx, dz)
end

-- Tunnel over the back straight, x T0..T1, its walls on the road edges, TH high inside; scored through its east
-- mouth
local T0, T1, TZ, TH = 62, 70, -12, 4.5
local tunnel = scene.addStructure()
tunnel:add((T0 + T1) / 2, TZ - HALF - 0.5, T1 - T0, 1, TH, 0)
tunnel:add((T0 + T1) / 2, TZ + HALF + 0.5, T1 - T0, 1, TH, 0)
tunnel:add((T0 + T1) / 2, TZ, T1 - T0, 2 * HALF + 2, 0.8, TH)

gate(X0, Z0 + START, 0.5, true)
gate(X0, 65, 1, true)
-- Hairpin apex, then its exit
flag(31, 101, 0, 1)
gate(42, 91, 1, true)
-- Sweeper apex, then the chicane in and out
flag(54, 78, -1, 0)
gate(75, 67.7, 1, false)
gate(96, 75, 1.5, false)
gate(111.9, 59, 1, true)
-- Esses apexes, then their exit
flag(111, 39, -1, 0)
flag(106.3, 22.2, 1, 0)
gate(105.4, 2, 1, true)
local mouth = Gap.new("GATE", 0, T1, 0, TZ - HALF, T1, TH, TZ + HALF)
-- Marker: centre and top (see Course opening), not part of a piece
mouth[9], mouth[10], mouth[11], mouth[12], mouth[13] = T1, TH / 2, TZ, TH, false
gates[#gates + 1] = mouth
-- Into the final corner, then its apex
gate(36, -12, 1, false)
flag(26.5, -5.5, -1, 0)
Map.gates = gates

-- Pit building along the straight, grandstand across from it
scene.addBox(31, 40, 5, 26, 3.5)
scene.addBox(8, 17, 5, 22, 6)

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(Ground.HILLS, Ground.horizon(quality))
  Circuit.draw(quality, LAYOUT, X0, Z0, 0, START)
  Ground.drawPad(X0, 5)
  scene.draw(quality)
end

function Map.update(_, _) end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

-- Video link: clean within 90 m of the circuit's centre, lost at 170 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 66, 47, 90, 170)
end

return Map
