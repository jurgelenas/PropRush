-- Freestyle scoring: flips, rolls, dives, gaps and proximity flown through the real quad, chained into combos.

local H = dofile("test/harness.lua")
H.install(128, 64)

local CORE = "src/SCRIPTS/TOOLS/FPVSim/core/"
local Quad = assert(loadfile(CORE .. "quad.lua"))(assert(loadfile(CORE .. "rates.lua"))())
local Kit = assert(loadfile(CORE .. "kit.lua"))(assert(loadfile(CORE .. "render3d.lua"))())
local Tricks = assert(loadfile(CORE .. "tricks.lua"))(Kit)

-- A wall across z = 20 with a 4 x 3 m window at x -2..2, y 2..5, and a long wall along x = 30
local scene = Kit.newScene()
local wall = scene.addStructure()
wall.add(-6, 20, 8, 0.6, 8, 0)
wall.add(6, 20, 8, 0.6, 8, 0)
wall.add(0, 20, 4, 0.6, 2, 0)
wall.add(0, 20, 4, 0.6, 3, 5)
scene.addBox(30.5, 50, 1, 100, 10)
local map = { gaps = { Kit.gap("WINDOW", 10, -2, 2, 20, 2, 5, 20) }, near = scene.near }

local settings = {
  angleMode = false,
  maxAngle = 55,
  batterySim = false,
  rollRcRate = 100,
  rollRate = 70,
  rollExpo = 0,
  pitchRcRate = 100,
  pitchRate = 70,
  pitchExpo = 0,
  yawRcRate = 100,
  yawRate = 70,
  yawExpo = 0,
}
local HOVER = 1 / 4.5
local sticks = { ail = 0, ele = 0, rud = 0, thr = HOVER }

local q, t
local notes

-- At x, y, z (x and z default 0), flying north at v m/s
local function start(y, v, x, z)
  q = Quad.new()
  q:reset(x or 0, y, z or 0, 0)
  q.vz = v or 0
  t = Tricks.new(map)
  notes = {}
end

-- Flies the frame loop for s seconds with the given sticks, in 50 ms frames of 10 ms steps
local function fly(s, ail, ele, thr, rud)
  sticks.ail, sticks.ele, sticks.thr, sticks.rud = ail or 0, ele or 0, thr or HOVER, rud or 0
  for _ = 1, math.floor(s / 0.05 + 0.5) do
    for _ = 1, 5 do
      q:step(0.01, sticks, settings)
    end
    t:update(0.05, q)
    if t.note and t.note ~= notes[#notes] then
      notes[#notes + 1] = t.note
    end
  end
end

local failures = 0
local function check(name, ok)
  print(
    string.format(
      "%s %-34s score=%d x%d | %s",
      ok and "PASS" or "FAIL",
      name,
      t.score,
      t.mult,
      table.concat(notes, " / ")
    )
  )
  if not ok then
    failures = failures + 1
  end
end

local function noted(trick)
  for _, n in ipairs(notes) do
    if n:find(trick, 1, true) then
      return true
    end
  end
  return false
end

-- Default rates turn 667 deg/s at full stick: a flip takes 0.55 s
start(30)
fly(0.55, 0, 1)
fly(0.3)
check("flip scores at once", t.score == 10 and t.goal == "PTS 10" and t.mult == 1)
fly(3)
check("the combo ends after its time", t.score == 10 and t.mult == 0)

start(30)
fly(1.1, 1, 0)
fly(0.3)
check("double roll", t.score == 30 and noted("DOUBLE ROLL +30"))

start(30)
fly(0.55, 0, 1)
fly(0.5)
fly(0.55, 1, 0)
fly(0.3)
check("flip then roll: the roll x2", t.score == 10 + 20 and noted("ROLL +20 x2"))

start(30)
fly(0.2, 0, 0.3)
fly(0.3)
fly(1)
check("tilting about is no trick", t.score == 0)

-- Nose down (stick forward), motors idle: a fall, then level out and power up
start(60)
fly(0.2, 0, 0.85)
fly(2, 0, 0, 0)
fly(0.2, 0, -0.85)
fly(1.5, 0, 0, 0.6)
check("dive", noted("DIVE 23M +23") and t.score == 23)

start(30)
fly(0.55, 0, 1)
fly(0.5)
fly(0.55, 0, 1)
fly(0.3)
q.strike = 0.2
fly(0.05)
q.strike = 0
check("prop strike ends the combo, keeps the points", t.score == 30 and t.mult == 0 and noted("COMBO LOST"))
fly(0.55, 0, 1)
fly(0.3)
check("  and the next trick starts at x1", t.score == 40)

-- Half stick pitches 154 deg/s: a loop takes 2.3 s, about 4.5 m across at 12 m/s
start(30, 12)
fly(2.35, 0, -0.5, 1)
fly(0.5)
check("power loop", noted("POWER LOOP") and not noted("FLIP"))

start(30, 12)
fly(0.55, 0, -1, 0.5)
fly(0.5)
check("quick backflip at speed is no loop", noted("BACKFLIP +10") and not noted("LOOP"))

start(30, 12)
fly(0.27, 1, 0)
fly(1.17, 0, -0.5, 0.4)
fly(0.5)
check("split-S", noted("SPLIT-S"))

start(30)
fly(0.55, 0, 0, HOVER, 1)
fly(0.3)
check("yaw spin", noted("YAW SPIN +10"))

start(30)
fly(0.6, 0, 0, 0, 1)
fly(0.3, 0, 0, HOVER)
check("trippy spin", noted("TRIPPY SPIN +20"))

start(30)
fly(4, 0, 0, HOVER, 0.25)
check("orbit-speed yaw is no spin", #notes == 0)

start(40)
fly(0.27, 1, 0)
fly(1.3, 0, 0, 0)
fly(0.27, 1, 0)
fly(0.5)
check("inverted hang", noted("HANG 1."))

start(30, 15)
fly(0.135, 1, 0)
fly(1, 0, 0, 0.5)
fly(0.135, -1, 0)
fly(0.3)
check("knife edge", noted("KNIFE EDGE"))

start(30, 15)
fly(0.135, 1, 0)
fly(1.5, 0, -0.6, 0.6)
fly(0.135, -1, 0)
fly(0.3)
check("hard banked turn is no knife edge", not noted("KNIFE"))

start(3.5, 10, 0, 10)
fly(1.5)
check("through the window", t.score == 10 and noted("WINDOW +10"))
q.pz, q.vz, t.ox = 10, 10, nil
fly(1.5)
check("  again straight after scores nothing", t.score == 10)
fly(2)
q.pz, q.vz, t.ox = 10, 10, nil
fly(1.5)
check("  but does once the combo is over", t.score == 20)

start(3.6, 10, 0, 17)
q:rotate(0, 0, math.pi)
fly(0.5, 0, 0, 0)
check("inverted through the window", noted("INVERTED WINDOW +20"))

start(6, 10, 6, 10)
fly(1.5)
check("into the wall beside the window is no gap", t.score == 0)

start(3, 16, 29, 5)
fly(0.8)
q.px = 20
fly(0.3)
check("proximity along a wall", noted("PROXIMITY 0."))

start(3, 6, 29, 5)
fly(1)
q.px = 20
fly(0.3)
check("slow along a wall is no proximity", #notes == 0)

start(0.5, 16, -50, 0)
fly(1)
check("skimming the ground is no proximity", #notes == 0)

print(failures == 0 and "TRICKS OK" or string.format("TRICKS %d FAILED", failures))
exit(failures == 0 and 0 or 1)
