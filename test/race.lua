-- Racing: gates in order on the GATES map, the lap clock, best laps, and flying through a gate for real.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/FPVSim/"
local R = assert(loadfile(SRC .. "core/render3d.lua"))()
local World = assert(loadfile(SRC .. "core/world.lua"))(R)
local Scene = assert(loadfile(SRC .. "core/scene.lua"))(R)
local Course = assert(loadfile(SRC .. "core/course.lua"))(R, Scene)
local Race = assert(loadfile(SRC .. "core/race.lua"))(Course)
local Quad = assert(loadfile(SRC .. "core/quad.lua"))(assert(loadfile(SRC .. "core/rates.lua"))())
local Map = assert(loadfile(SRC .. "maps/gates.lua"))(World, Scene, Course)
local gates = Map.gates

local failures = 0
local function check(name, ok, detail)
  print(string.format("%s %-40s %s", ok and "PASS" or "FAIL", name, detail or ""))
  if not ok then
    failures = failures + 1
  end
end

local r = Race.new(Map)
local p = { px = 0, py = 1.5, pz = 0 }

-- Frames of dt seconds standing still at x, y, z
local function at(x, y, z, frames, dt)
  p.px, p.py, p.pz = x, y, z
  for _ = 1, frames or 1 do
    r:update(dt or 0.05, p)
  end
end

-- Through gate i's opening, off its centre by du sideways, taking a frame on each side
local function pass(i, du)
  local g = gates[i]
  local x, z = g.cx, g.cz
  if g.axis == 3 then
    at(x + (du or 0), g.cy, z - 1)
    at(x + (du or 0), g.cy, z + 1)
  else
    at(x - 1, g.cy, z + (du or 0))
    at(x + 1, g.cy, z + (du or 0))
  end
end

local function state()
  return string.format(
    "goal=%s clock=%s note=%s lap=%d t=%.2f",
    r.goal,
    tostring(r.clock),
    tostring(r.note),
    r.lap,
    r.time
  )
end

at(0, 1.5, 0)
check("before the start", r.goal == "1/6 12M" and not r.clock and not r.note, state())
pass(2)
check("  a later gate does not count", r.goal:sub(1, 4) == "1/6 ", state())
pass(1)
check("through the start gate", r.goal:sub(1, 4) == "2/6 " and r.lap == 1 and r.clock == "0.0S", state())
pass(4)
check("  out of order is ignored", r.goal:sub(1, 4) == "2/6 ", state())
pass(2, 3)
check("  beside the opening is no pass", r.goal:sub(1, 4) == "2/6 ", state())
for i = 2, 6 do
  pass(i)
end
at(0, 1.5, 0, 180)
local t = r.time
check(
  "the clock runs",
  t > 9 and r.goal == "1/6 12M" and r.clock == string.format("%.1fS", math.floor(t * 10) / 10),
  state()
)
pass(1)
check("lap closed", r.finished and math.abs(r.finished - t - 0.1) < 1e-6 and r.best == r.finished, state())
check("  shows its time", r.note == string.format("LAP 1 %.2fS", t + 0.1) and r.goal:sub(1, 4) == "2/6 ", state())
r.finished = nil
for i = 2, 6 do
  pass(i)
end
pass(1)
check("a faster lap is the best", r.best and math.abs(r.best - 0.6) < 1e-6, state())
for i = 2, 6 do
  pass(i)
end
at(0, 1.5, 0, 100)
pass(1)
check("  a slower one is not", math.abs(r.best - 0.6) < 1e-6 and r.finished > 5, state())
at(0, 1.5, 0, 40)
check("the lap time goes after 2 s", not r.note, state())

-- From the spawn straight through the start gate on the real quad, colliding with the map
local settings = { angleMode = true, maxAngle = 55, batterySim = false, yawRcRate = 100, yawRate = 70, yawExpo = 0 }
local sticks = { ail = 0, ele = 0, rud = 0, thr = 1 / 4.5 }
local function fly(x, y, z, vx, vz, t)
  local q = Quad.new()
  q:reset(x, y, z, 0)
  q.vx, q.vz = vx, vz
  r = Race.new(Map)
  for _ = 1, t / 0.05 do
    for _ = 1, 5 do
      local ox, oy, oz = q.px, q.py, q.pz
      local crashed = q:step(0.01, sticks, settings)
      local hit = not crashed and Map.collides(q.px, q.py, q.pz)
      if crashed or hit == true or hit and Scene.collide(hit, q, ox, oy, oz, 0.01) then
        return q, true
      end
    end
    r:update(0.05, q)
  end
  return q, false
end

local q, crashed = fly(0, 1.7, 0, 0, 10, 2)
check("flown through the start gate", not crashed and r.lap == 1 and r.goal:sub(1, 4) == "2/6 ", state())
q, crashed = fly(1.65, 1.7, 6, 0, 8, 2)
check("into its post at 8 m/s is a prop strike", not crashed and q.pz < 12, state())
q, crashed = fly(1.65, 1.7, 6, 0, 15, 2)
check("  at 15 m/s a crash", crashed and q.pz < 12, state())
q, crashed = fly(0, 3.3, 0, 0, 10, 2)
check("over it is no pass", r.lap == 0, state())

print(failures == 0 and "RACE OK" or string.format("RACE %d FAILED", failures))
exit(failures == 0 and 0 or 1)
