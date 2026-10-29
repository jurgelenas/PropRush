-- Contacts with the ground and boxes: soft touches land or slide, edge-on hits strike the props, hard hits crash.

local H = dofile("test/harness.lua")
H.install(128, 64)

local CORE = "src/SCRIPTS/TOOLS/FPVSim/core/"
local R = assert(loadfile(CORE .. "render3d.lua"))()
local Kit = assert(loadfile(CORE .. "kit.lua"))(R)
local Quad = assert(loadfile(CORE .. "quad.lua"))(assert(loadfile(CORE .. "rates.lua"))())

local scene = Kit.newScene()
-- A 10 m cube north of the origin and a thin wall east of it
scene.addBox(0, 20, 10, 10, 10)
local wall = scene.addStructure()
wall.add(20, 0, 0.6, 20, 6, 0)

local settings = {
  angleMode = true,
  maxAngle = 55,
  batterySim = false,
  yawRcRate = 100,
  yawRate = 70,
  yawExpo = 0,
}
-- Hover throttle: thrust equal to weight
local sticks = { ail = 0, ele = 0, rud = 0, thr = 1 / 4.5 }

-- Flies the loop the flight screen runs, for t seconds from position p with velocity v
local function fly(p, v, t, thr)
  local q = Quad.new()
  q:reset(p[1], p[2], p[3], 0)
  q.vx, q.vy, q.vz = v[1], v[2], v[3]
  sticks.thr = thr or 1 / 4.5
  local struck = 0
  local h = 0.01
  for _ = 1, math.floor(t / h) do
    local ox, oy, oz = q.px, q.py, q.pz
    local crashed = q:step(h, sticks, settings)
    if not crashed then
      local hit = scene.collides(q.px, q.py, q.pz)
      crashed = hit == true or hit and Kit.collide(hit, q, ox, oy, oz, h)
    end
    if q.strike > struck then
      struck = q.strike
    end
    if crashed then
      return q, true, struck
    end
  end
  return q, false, struck
end

local failures = 0
local function check(name, ok, detail)
  print(string.format("%s %-44s %s", ok and "PASS" or "FAIL", name, detail or ""))
  if not ok then
    failures = failures + 1
  end
end

local function state(q, crashed, struck)
  return string.format(
    "crash=%s strike=%.2f pos=%.2f,%.2f,%.2f v=%.1f,%.1f,%.1f",
    tostring(crashed),
    struck,
    q.px,
    q.py,
    q.pz,
    q.vx,
    q.vy,
    q.vz
  )
end

local q, crashed, struck

q, crashed, struck = fly({ 0, 0.5, 0 }, { 0, -3, 0 }, 1, 0)
check("flat drop at 3 m/s lands", not crashed and struck == 0 and q.py == 0, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 1, 0 }, { 0, -10, 0 }, 1, 0)
check("flat onto grass at 10 m/s survives", not crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 1, 0 }, { 0, -13, 0 }, 1, 0)
check("flat onto grass at 13 m/s crashes", crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 11, 20 }, { 0, -7, 0 }, 1, 0)
check("flat onto a roof at 7 m/s survives", not crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 11, 20 }, { 0, -9, 0 }, 1, 0)
check("flat onto a roof at 9 m/s crashes", crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 0.3, 0 }, { 15, -1, 0 }, 0.5)
check("skimming the ground at 15 m/s survives", not crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 3, 13 }, { 0, 0, 4 }, 0.5)
check("level into a wall at 4 m/s strikes the props", not crashed and struck > 0, state(q, crashed, struck))
check("  and bounces back off it", q.vz < 0 and q.pz < 15 - 0.15 + 1e-9, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 3, 13 }, { 0, 0, 6 }, 0.5)
check("level into a wall at 6 m/s breaks a prop", crashed, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 0.3, 0 }, { 6, -6, 0 }, 0.5, 0)
check("6 m/s down onto grass, level, no strike", not crashed and struck == 0, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 3, 13 }, { 0, 0, 1 }, 2.5)
check(
  "brushing a wall at 1 m/s gives a light strike",
  not crashed and struck > 0 and struck < 0.1,
  state(q, crashed, struck)
)

q, crashed, struck = fly({ -6, 3, 10 }, { 1.5, 0, 20 }, 1)
check("glancing a wall at 20 m/s survives", not crashed, state(q, crashed, struck))
check("  and slides along its face", q.px <= -5.15 + 1e-9, state(q, crashed, struck))

q, crashed, struck = fly({ 0, 11, 20 }, { 0, -1, 0 }, 2, 0.2)
check("gentle drop onto the roof lands on it", not crashed and q.grounded and q.py == 10.15, state(q, crashed, struck))

q, crashed, struck = fly({ 19, 3, -5 }, { 30, 0, 2 }, 0.03)
check("30 m/s into a thin wall is no tunnel", crashed and q.px < 20, state(q, crashed, struck))

q, crashed, struck = fly({ 15, 3, -5 }, { 4, 0, 30 }, 1)
check("30 m/s along a thin wall, touching it", not crashed and q.px <= 19.55 + 1e-9, state(q, crashed, struck))

print(failures == 0 and "CONTACT OK" or string.format("CONTACT %d FAILED", failures))
exit(failures == 0 and 0 or 1)
