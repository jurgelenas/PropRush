-- Freestyle scoring: flips, rolls, dives, gaps and proximity flown through the real quad, chained into combos.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Gap = assert(loadfile(SRC .. "world/gap.lua"))()
local Freestyle = assert(loadfile(SRC .. "modes/freestyle.lua"))(Gap)
local highscore = assert(loadfile(SRC .. "config/highscore.lua"))({
  write = function()
    return true
  end,
})

-- A wall across z = 20 with a 4 x 3 m window at x -2..2, y 2..5, and a long wall along x = 30
local scene = Scene.new()
local wall = scene.addStructure()
wall:add(-6, 20, 8, 0.6, 8, 0)
wall:add(6, 20, 8, 0.6, 8, 0)
wall:add(0, 20, 4, 0.6, 2, 0)
wall:add(0, 20, 4, 0.6, 3, 5)
scene.addBox(30.5, 50, 1, 100, 10)
local map = { gaps = { Gap.new("WINDOW", 10, -2, 2, 20, 2, 5, 20) }, near = scene.near }

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
-- The sound cues asked for, as "trick roll 2 1", "tick hangTick 0", "cue lost"
local cues
local NAMES = dofile("test/cue_names.lua")
local sound = {
  trick = function(id, n, mult)
    cues[#cues + 1] = string.format("trick %s %d %d", NAMES[id], n or 1, mult)
  end,
  tick = function(id, k)
    cues[#cues + 1] = string.format("tick %s %d", NAMES[id], k)
  end,
  cue = function(id)
    cues[#cues + 1] = "cue " .. NAMES[id]
  end,
}

-- At x, y, z (x and z default 0), flying north at v m/s
local function start(y, v, x, z)
  q = Quad.new()
  q:reset(x or 0, y, z or 0, 0)
  q.armed = true
  q.vz = v or 0
  t = Freestyle.new(map, sound, highscore, "test")
  notes, cues = {}, {}
end

-- Flies the frame loop for s seconds with the given sticks, in 50 ms frames of 10 ms steps
local function fly(s, ail, ele, thr, rud)
  sticks.ail, sticks.ele, sticks.thr, sticks.rud = ail or 0, ele or 0, thr or HOVER, rud or 0
  for _ = 1, math.floor(s / 0.05 + 0.5) do
    local ox, oy, oz = q.px, q.py, q.pz
    for _ = 1, 5 do
      q:step(0.01, sticks, settings)
    end
    t:update(0.05, q, ox, oy, oz)
    if t.note and t.note ~= notes[#notes] then
      notes[#notes + 1] = t.note
    end
  end
end

-- Score, multiplier, the notes shown and the cues, for a failure
local function state()
  return string.format("score=%d x%d | %s | %s", t.score, t.mult, table.concat(notes, " / "), table.concat(cues, " / "))
end

local function cued(cue)
  for _, c in ipairs(cues) do
    if c == cue then
      return true
    end
  end
  return false
end

local function noted(trick)
  for _, n in ipairs(notes) do
    if n:find(trick, 1, true) then
      return true
    end
  end
  return false
end

describe("tricks", function()
  -- Default rates turn 667 deg/s at full stick: a flip takes 0.55 s
  describe("flips and rolls", function()
    it("a flip scores at once", function()
      start(30)
      fly(0.55, 0, 1)
      fly(0.3)
      assert.equal(10, t.score, state())
      assert.equal("PTS 10", t.goal, state())
      assert.equal(1, t.mult, state())
      assert.is_true(cued("trick flip 1 1"), state())
    end)
    it("the combo ends after its time", function()
      fly(3)
      assert.equal(10, t.score, state())
      assert.equal(0, t.mult, state())
      assert.is_false(cued("cue bank"), "a combo of one trick is not banked")
    end)
    it("a double roll", function()
      start(30)
      fly(1.1, 1, 0)
      fly(0.3)
      assert.equal(30, t.score, state())
      assert.is_true(noted("DOUBLE ROLL +30"), state())
      assert.is_true(cued("trick roll 2 1"), state())
    end)
    it("a flip then a roll: the roll x2", function()
      start(30)
      fly(0.55, 0, 1)
      fly(0.5)
      fly(0.55, 1, 0)
      fly(0.3)
      assert.equal(10 + 20, t.score, state())
      assert.is_true(noted("ROLL +20 x2"), state())
      assert.is_true(cued("trick roll 1 2"), state())
    end)
    it("the combo of two is banked when it ends", function()
      fly(3)
      assert.is_true(cued("cue bank"), state())
    end)
    it("tilting about is no trick", function()
      start(30)
      fly(0.2, 0, 0.3)
      fly(0.3)
      fly(1)
      assert.equal(0, t.score, state())
    end)
  end)

  describe("a prop strike", function()
    it("ends the combo and keeps the points", function()
      start(30)
      fly(0.55, 0, 1)
      fly(0.5)
      fly(0.55, 0, 1)
      fly(0.3)
      q.strike = 0.2
      fly(0.05)
      q.strike = 0
      assert.equal(30, t.score, state())
      assert.equal(0, t.mult, state())
      assert.is_true(noted("COMBO LOST"), state())
      assert.is_true(cued("cue lost"), state())
    end)
    it("and the next trick starts at x1", function()
      fly(0.55, 0, 1)
      fly(0.3)
      assert.equal(40, t.score, state())
    end)
  end)

  -- Nose down (stick forward), motors idle: a fall, then level out and power up
  it("a dive", function()
    start(60)
    fly(0.2, 0, 0.85)
    fly(2, 0, 0, 0)
    fly(0.2, 0, -0.85)
    fly(1.5, 0, 0, 0.6)
    assert.is_true(noted("DIVE 23M +23"), state())
    assert.equal(23, t.score, state())
  end)

  -- Half stick pitches 154 deg/s: a loop takes 2.3 s, about 4.5 m across at 12 m/s
  describe("loops", function()
    it("a power loop", function()
      start(30, 12)
      fly(2.35, 0, -0.5, 1)
      fly(0.5)
      assert.is_true(noted("POWER LOOP"), state())
      assert.is_false(noted("FLIP"), state())
    end)
    it("a quick backflip at speed is no loop", function()
      start(30, 12)
      fly(0.55, 0, -1, 0.5)
      fly(0.5)
      assert.is_true(noted("BACKFLIP +10"), state())
      assert.is_false(noted("LOOP"), state())
    end)
    it("a split-S", function()
      start(30, 12)
      fly(0.27, 1, 0)
      fly(1.17, 0, -0.5, 0.4)
      fly(0.5)
      assert.is_true(noted("SPLIT-S"), state())
    end)
  end)

  describe("spins", function()
    it("a yaw spin", function()
      start(30)
      fly(0.55, 0, 0, HOVER, 1)
      fly(0.3)
      assert.is_true(noted("YAW SPIN +10"), state())
    end)
    it("a trippy spin", function()
      start(30)
      fly(0.6, 0, 0, 0, 1)
      fly(0.3, 0, 0, HOVER)
      assert.is_true(noted("TRIPPY SPIN +20"), state())
    end)
    it("orbit-speed yaw is no spin", function()
      start(30)
      fly(4, 0, 0, HOVER, 0.25)
      assert.equal(0, #notes, state())
    end)
  end)

  describe("held attitudes", function()
    it("an inverted hang", function()
      start(40)
      fly(0.27, 1, 0)
      fly(1.3, 0, 0, 0)
      fly(0.27, 1, 0)
      fly(0.5)
      assert.is_true(noted("HANG 1."), state())
      assert.is_true(cued("tick hangTick 0"), state())
      assert.is_true(cued("trick hang 1 1"), state())
    end)
    it("a knife edge", function()
      start(30, 15)
      fly(0.135, 1, 0)
      fly(1, 0, 0, 0.5)
      fly(0.135, -1, 0)
      fly(0.3)
      assert.is_true(noted("KNIFE EDGE"), state())
    end)
    it("a hard banked turn is no knife edge", function()
      start(30, 15)
      fly(0.135, 1, 0)
      fly(1.5, 0, -0.6, 0.6)
      fly(0.135, -1, 0)
      fly(0.3)
      assert.is_false(noted("KNIFE"), state())
    end)
  end)

  describe("gaps", function()
    it("through the window", function()
      start(3.5, 10, 0, 10)
      fly(1.5)
      assert.equal(10, t.score, state())
      assert.is_true(noted("WINDOW +10"), state())
    end)
    it("again straight after scores nothing", function()
      q.pz, q.vz = 10, 10
      fly(1.5)
      assert.equal(10, t.score, state())
    end)
    it("but does once the combo is over", function()
      fly(2)
      q.pz, q.vz = 10, 10
      fly(1.5)
      assert.equal(20, t.score, state())
    end)
    it("inverted through the window", function()
      start(3.6, 10, 0, 17)
      q:rotate(0, 0, math.pi)
      fly(0.5, 0, 0, 0)
      assert.is_true(noted("INVERTED WINDOW +20"), state())
      assert.is_true(cued("trick gapInverted 1 1"), state())
    end)
    it("into the wall beside the window is no gap", function()
      start(6, 10, 6, 10)
      fly(1.5)
      assert.equal(0, t.score, state())
    end)
  end)

  describe("the map's best", function()
    it("a crash keeps the run's score", function()
      start(30)
      fly(0.55, 0, 1)
      fly(0.3)
      t:finish()
      assert.equal("NEW BEST 10", t.note, state())
      assert.equal(10, highscore.byMap.test, state())
      assert.is_true(cued("cue best"), state())
    end)
    it("passing it is cued", function()
      start(30)
      fly(1.1, 1, 0)
      fly(0.3)
      assert.is_true(cued("cue record"), state())
    end)
    it("a lower score is not kept", function()
      start(30)
      fly(0.55, 0, 1)
      fly(0.3)
      t:finish()
      assert.equal("PTS 10", t.note, state())
      assert.equal(10, highscore.byMap.test, state())
      assert.is_false(cued("cue record"), state())
    end)
  end)

  describe("proximity", function()
    it("along a wall", function()
      start(3, 16, 29, 5)
      fly(0.8)
      q.px = 20
      fly(0.3)
      assert.is_true(noted("PROXIMITY 0."), state())
    end)
    it("slow along a wall is none", function()
      start(3, 6, 29, 5)
      fly(1)
      q.px = 20
      fly(0.3)
      assert.equal(0, #notes, state())
    end)
    it("skimming the ground is none", function()
      start(0.5, 16, -50, 0)
      fly(1)
      assert.equal(0, #notes, state())
    end)
  end)
end)
