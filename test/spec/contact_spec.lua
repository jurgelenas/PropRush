-- Contacts with the ground and boxes: soft touches land or slide, edge-on hits strike the props, hard hits crash.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())

local scene = Scene.new()
-- A 10 m cube north of the origin, a thin wall east of it and a 10 cm post west of it
scene.addBox(0, 20, 10, 10, 10)
local wall = scene.addStructure()
wall:add(20, 0, 0.6, 20, 6, 0)
scene.addBox(-20, 0, 0.1, 0.1, 6)

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
  q.armed = true
  q.vx, q.vy, q.vz = v[1], v[2], v[3]
  sticks.thr = thr or 1 / 4.5
  local struck = 0
  local h = 0.01
  for _ = 1, math.floor(t / h) do
    local ox, oy, oz = q.px, q.py, q.pz
    local crashed = q:step(h, sticks, settings)
    if not crashed then
      local hit = scene.collides(q.px, q.py, q.pz)
      crashed = hit == true or hit and Scene.collide(hit, q, ox, oy, oz, h)
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

-- The run's end state, shown with any failure
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

describe("contacts", function()
  local q, crashed, struck, msg
  local function run(p, v, t, thr)
    q, crashed, struck = fly(p, v, t, thr)
    msg = state(q, crashed, struck)
  end

  describe("flat onto the ground or a roof", function()
    it("lands from a 3 m/s drop", function()
      run({ 0, 0.5, 0 }, { 0, -3, 0 }, 1, 0)
      assert.is_false(crashed, msg)
      assert.equal(0, struck, msg)
      assert.equal(0, q.py, msg)
    end)
    it("survives grass at 22 m/s", function()
      run({ 0, 1, 0 }, { 0, -22, 0 }, 1, 0)
      assert.is_false(crashed, msg)
    end)
    it("crashes on grass at 25 m/s", function()
      run({ 0, 1, 0 }, { 0, -25, 0 }, 1, 0)
      assert.is_true(crashed, msg)
    end)
    it("survives a roof at 16.5 m/s", function()
      run({ 0, 12, 20 }, { 0, -16.5, 0 }, 1, 0)
      assert.is_false(crashed, msg)
    end)
    it("crashes on a roof at 19 m/s", function()
      run({ 0, 12, 20 }, { 0, -19, 0 }, 1, 0)
      assert.is_true(crashed, msg)
    end)
    it("lands on the roof from a gentle drop", function()
      run({ 0, 11, 20 }, { 0, -1, 0 }, 2, 0.2)
      assert.is_false(crashed, msg)
      assert.is_true(q.grounded, msg)
      assert.equal(10.15, q.py, msg)
    end)
    it("takes 6 m/s down onto grass, level, without a strike", function()
      run({ 0, 0.3, 0 }, { 6, -6, 0 }, 0.5, 0)
      assert.is_false(crashed, msg)
      assert.equal(0, struck, msg)
    end)
    it("survives skimming the ground at 15 m/s", function()
      run({ 0, 0.3, 0 }, { 15, -1, 0 }, 0.5)
      assert.is_false(crashed, msg)
    end)
  end)

  describe("level into a wall", function()
    it("strikes the props at 4 m/s and bounces back", function()
      run({ 0, 3, 13 }, { 0, 0, 4 }, 0.5)
      assert.is_false(crashed, msg)
      assert.is_true(struck > 0, msg)
      assert.is_true(q.vz < 0 and q.pz < 15 - 0.15 + 1e-9, msg)
    end)
    it("survives a strike at 9 m/s", function()
      run({ 0, 3, 13 }, { 0, 0, 9 }, 0.5)
      assert.is_false(crashed, msg)
      assert.is_true(struck > 0.4, msg)
    end)
    it("survives a strike at 13 m/s", function()
      run({ 0, 3, 14.5 }, { 0, 0, 13 }, 0.5)
      assert.is_false(crashed, msg)
    end)
    it("breaks a prop at 15 m/s", function()
      run({ 0, 3, 14.5 }, { 0, 0, 15 }, 0.5)
      assert.is_true(crashed, msg)
    end)
    it("gives a light strike brushing it at 1 m/s", function()
      run({ 0, 3, 13 }, { 0, 0, 1 }, 2.5)
      assert.is_false(crashed, msg)
      assert.is_true(struck > 0 and struck < 0.1, msg)
    end)
    it("survives a glance at 20 m/s and slides along the face", function()
      run({ -6, 3, 10 }, { 1.5, 0, 20 }, 1)
      assert.is_false(crashed, msg)
      assert.is_true(q.px <= -5.15 + 1e-9, msg)
    end)
  end)

  -- The post is 0.1 m wide and the quad reaches 0.15 m: its centre passing 0.1 m beside the post, the post's edge
  -- takes the hit slanting 42 degrees off head-on (3/4 of the speed), 0.12 m beside 53 degrees (3/5), and from
  -- 0.15 m beside it misses
  describe("a post clipped", function()
    it("dead centre breaks a prop at 15 m/s", function()
      run({ -20, 3, -0.5 }, { 0, 0, 15 }, 0.5)
      assert.is_true(crashed, msg)
    end)
    it("by its edge survives 18 m/s and is pushed aside", function()
      run({ -19.85, 3, -2 }, { 0, 0, 18 }, 0.5)
      assert.is_false(crashed, msg)
      assert.is_true(struck > 0, msg)
      assert.is_true(q.px > -19.85 and q.pz > 0, msg)
    end)
    it("by a little survives 22 m/s", function()
      run({ -19.83, 3, -2 }, { 0, 0, 22 }, 0.3)
      assert.is_false(crashed, msg)
      assert.is_true(struck > 0, msg)
    end)
    it("not at all past its corner", function()
      run({ -19.79, 3, -2 }, { 0, 0, 25 }, 0.3)
      assert.equal(0, struck, msg)
    end)
  end)

  describe("a roof edge clipped", function()
    it("slants the hit off the top", function()
      run({ 0, 10.1, 12 }, { 0, 0, 20 }, 0.3)
      assert.is_false(crashed, msg)
      assert.is_true(q.py > 10.1, msg)
    end)
  end)

  describe("a thin wall", function()
    it("is no tunnel at 30 m/s", function()
      run({ 19, 3, -5 }, { 30, 0, 2 }, 0.03)
      assert.is_true(crashed, msg)
      assert.is_true(q.px < 20, msg)
    end)
    it("can be flown along at 30 m/s, touching it", function()
      run({ 15, 3, -5 }, { 4, 0, 30 }, 1)
      assert.is_false(crashed, msg)
      assert.is_true(q.px <= 19.55 + 1e-9, msg)
    end)
  end)
end)
