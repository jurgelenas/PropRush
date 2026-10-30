-- Racing: gates in order on a six-gate loop, the lap clock, best laps, and flying through a gate for real.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Ground = assert(loadfile(SRC .. "world/ground.lua"))(R)
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Gap = assert(loadfile(SRC .. "world/gap.lua"))()
local Racing = assert(loadfile(SRC .. "modes/racing.lua"))(Gap)
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())
local Course = assert(loadfile(SRC .. "world/course.lua"))(R, Scene, Gap)
-- Six gates 3 x 2.4 m round open fields from a spawn at the origin: {x, z, bottom height, frame along x}
local scene = Scene.new()
local gates = {}
-- stylua: ignore
local COURSE = {
  0, 12, 0.5, true,
  8, 55, 2, true,
  35, 80, 1, false,
  60, 50, 5, true,
  55, 10, 0.5, true,
  25, -15, 1.5, false,
}
for i = 1, #COURSE, 4 do
  gates[#gates + 1] = Course.addGate(scene, COURSE[i], COURSE[i + 1], 3, 2.4, COURSE[i + 2], COURSE[i + 3])
end
local Map = {
  gates = gates,
  collides = function(x, y, z)
    return scene.collides(x, y, z)
  end,
}
local highscore = assert(loadfile(SRC .. "config/highscore.lua"))({
  write = function()
    return true
  end,
})

local r = Racing.new(Map, nil, highscore, "loop")
local p = { px = 0, py = 1.5, pz = 0 }

-- Frames of dt seconds standing still at x, y, z, the first moving there from the last
local function at(x, y, z, frames, dt)
  local ox, oy, oz = p.px, p.py, p.pz
  p.px, p.py, p.pz = x, y, z
  for _ = 1, frames or 1 do
    r:update(dt or 0.05, p, ox, oy, oz)
    ox, oy, oz = x, y, z
  end
end

-- Through gate i's opening its way, or back the other way, off its centre by du sideways: put on one side, then a
-- frame there and one on the other
local function pass(i, du, back)
  local g = gates[i]
  -- cx, cz; dir; axis; cy
  local x, z, s = g[9], g[11], back and -g[15] or g[15]
  local x0, z0, x1, z1 = x + (du or 0), z - s, x + (du or 0), z + s
  if g[1] ~= 3 then
    x0, z0, x1, z1 = x - s, z + (du or 0), x + s, z + (du or 0)
  end
  p.px, p.py, p.pz = x0, g[10], z0
  at(x0, g[10], z0)
  at(x1, g[10], z1)
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

-- From the spawn straight through the start gate on the real quad, colliding with the map
local settings = { angleMode = true, maxAngle = 55, batterySim = false, yawRcRate = 100, yawRate = 70, yawExpo = 0 }
local sticks = { ail = 0, ele = 0, rud = 0, thr = 1 / 4.5 }
local function fly(x, y, z, vx, vz, t)
  local q = Quad.new()
  q:reset(x, y, z, 0)
  q.armed = true
  q.vx, q.vz = vx, vz
  r = Racing.new(Map, nil, highscore, "loop")
  for _ = 1, t / 0.05 do
    local fx, fy, fz = q.px, q.py, q.pz
    for _ = 1, 5 do
      local ox, oy, oz = q.px, q.py, q.pz
      local crashed = q:step(0.01, sticks, settings)
      local hit = not crashed and Map.collides(q.px, q.py, q.pz)
      if crashed or hit == true or hit and Scene.collide(hit, q, ox, oy, oz, 0.01) then
        return q, true
      end
    end
    r:update(0.05, q, fx, fy, fz)
  end
  return q, false
end

describe("racing", function()
  -- One race, its steps in order: each test goes on from where the last left it
  describe("a lap", function()
    it("waits before the start", function()
      at(0, 1.5, 0)
      assert.equal("1/6 12M", r.goal, state())
      assert.is_nil(r.clock, state())
      assert.is_nil(r.note, state())
    end)
    it("does not count a later gate first", function()
      pass(2)
      assert.matches("^1/6 ", r.goal, state())
    end)
    it("does not start through the start gate the wrong way", function()
      pass(1, 0, true)
      assert.equal(0, r.lap, state())
      assert.is_nil(r.clock, state())
      assert.equal("WRONG WAY", r.note, state())
    end)
    it("starts through the start gate", function()
      pass(1)
      assert.matches("^2/6 ", r.goal, state())
      assert.equal(1, r.lap, state())
      assert.equal("0.0S", r.clock, state())
    end)
    it("does not count a gate flown the wrong way", function()
      pass(2, 0, true)
      assert.matches("^2/6 ", r.goal, state())
      assert.equal("WRONG WAY", r.note, state())
    end)
    it("warns through the gate after the next flown backwards", function()
      at(p.px, p.py, p.pz, 41)
      assert.is_nil(r.note, state())
      pass(3, 0, true)
      assert.matches("^2/6 ", r.goal, state())
      assert.equal("WRONG WAY", r.note, state())
    end)
    it("ignores gates out of order", function()
      pass(4)
      assert.matches("^2/6 ", r.goal, state())
    end)
    it("does not count passing beside the opening", function()
      pass(2, 3)
      assert.matches("^2/6 ", r.goal, state())
    end)

    local t
    it("runs the clock", function()
      for i = 2, 6 do
        pass(i)
      end
      at(0, 1.5, 0, 180)
      t = r.time
      assert.is_true(t > 9, state())
      assert.equal("1/6 12M", r.goal, state())
      assert.equal(string.format("%.1fS", math.floor(t * 10) / 10), r.clock, state())
    end)
    it("closes through the start gate and shows its time", function()
      pass(1)
      assert.near(t + 0.1, r.last, 1e-6, state())
      assert.equal(r.last, r.best, state())
      assert.equal(math.floor((t + 0.1) * 100 + 0.5), highscore.byMap.loop, state())
      assert.equal(string.format("LAP 1 %.2fS", t + 0.1), r.note, state())
      assert.matches("^2/6 ", r.goal, state())
    end)
    it("keeps a faster lap as the best", function()
      for i = 2, 6 do
        pass(i)
      end
      pass(1)
      assert.near(0.6, r.best, 1e-6, state())
    end)
    it("does not keep a slower one", function()
      for i = 2, 6 do
        pass(i)
      end
      at(0, 1.5, 0, 100)
      pass(1)
      assert.near(0.6, r.best, 1e-6, state())
      assert.is_true(r.last > 5, state())
      assert.equal(60, highscore.byMap.loop, state())
    end)
    it("drops the lap time after 2 s", function()
      at(0, 1.5, 0, 40)
      assert.is_nil(r.note, state())
    end)
    it("shows its best lap after a crash", function()
      r:finish()
      assert.equal("NEW BEST 0.60S", r.note, state())
    end)
  end)

  describe("TECH", function()
    local Tech = assert(loadfile(SRC .. "maps/racing/tech.lua"))(Ground, Scene, Gap, R, function(name, ...)
      return assert(loadfile(SRC .. name .. ".lua"))(...)
    end)
    it("warns going up the east side of the ladder before its first rung", function()
      local t = Racing.new(Tech, nil, highscore, "tech")
      t.next = 2
      -- The way round the first rung: its marker x, the rung's z
      local x, z = Tech.gates[3][9], Tech.gates[2][11]
      t:update(0.05, { px = x, py = 2, pz = z + 1 }, x, 2, z - 1)
      assert.equal(2, t.next)
      assert.equal("WRONG WAY", t.note)
    end)
    it("has the triple gate flown east three times", function()
      for i = 9, 11 do
        -- axis, dir
        assert.equal(1, Tech.gates[i][1])
        assert.equal(1, Tech.gates[i][15])
      end
    end)
  end)

  describe("on the real quad", function()
    it("flies through the start gate", function()
      local _, crashed = fly(0, 1.7, 0, 0, 10, 2)
      assert.is_false(crashed, state())
      assert.equal(1, r.lap, state())
      assert.matches("^2/6 ", r.goal, state())
    end)
    it("strikes the props on its post at 8 m/s", function()
      local q, crashed = fly(1.65, 1.7, 6, 0, 8, 2)
      assert.is_false(crashed, state())
      assert.is_true(q.pz < 12, state())
    end)
    it("crashes into its post at 16 m/s", function()
      local q, crashed = fly(1.65, 1.7, 10.5, 0, 16, 2)
      assert.is_true(crashed, state())
      assert.is_true(q.pz < 12, state())
    end)
    it("does not count flying over it", function()
      fly(0, 3.3, 0, 0, 10, 2)
      assert.equal(0, r.lap, state())
    end)
  end)
end)
