-- Arming: the arm source read as on or off, and the flight controller arming only from the switch off with the
-- throttle low.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end

local Quad = load("physics/quad", load("physics/rates"))

describe("arming", function()
  describe("the arm source", function()
    local settings, Input
    before_each(function()
      settings = load("config/settings")
      Input = load("platform/input", settings)
    end)

    it("is none with ALWAYS", function()
      assert.is_nil(Input.arm())
    end)
    it("is on above its middle", function()
      settings.armSrc = "sa"
      H.sticks = { sa = 1024 }
      assert.is_true(Input.arm())
      H.sticks.sa = 0
      assert.is_false(Input.arm())
      H.sticks.sa = -1024
      assert.is_false(Input.arm())
    end)
    it("reversed, below it", function()
      settings.armSrc, settings.armRev = "sa", true
      H.sticks = { sa = -1024 }
      assert.is_true(Input.arm())
      H.sticks.sa = 0
      assert.is_false(Input.arm())
    end)
    it("is none for a source the radio lacks", function()
      settings.armSrc = "sz"
      assert.is_nil(Input.arm())
    end)
  end)

  describe("the flight controller", function()
    local q = Quad.new()

    it("spawns disarmed", function()
      assert.is_false(q.armed)
    end)
    it("does not arm from a switch already on", function()
      assert.is_nil(q:arm(true, 0))
      assert.is_false(q.armed)
    end)
    it("arms when switched on again", function()
      assert.is_nil(q:arm(false, 0))
      assert.equal("armed", q:arm(true, 0))
      assert.is_true(q.armed)
    end)
    it("disarms when switched off", function()
      assert.equal("disarmed", q:arm(false, 0.5))
      assert.is_false(q.armed)
    end)
    it("waits for the throttle low", function()
      assert.equal("throttle", q:arm(true, 0.5))
      assert.equal("throttle", q:arm(true, 0.3))
      assert.equal("armed", q:arm(true, 0))
    end)
    it("after a respawn waits for the switch off again", function()
      q:reset(0, 0, 0, 0)
      assert.is_nil(q:arm(true, 0))
      assert.is_false(q.armed)
    end)
    it("with no arm source arms on throttle low and stays armed", function()
      q:reset(0, 0, 0, 0)
      assert.equal("throttle", q:arm(nil, 0.5))
      assert.equal("armed", q:arm(nil, 0))
      assert.is_nil(q:arm(nil, 1))
      assert.is_true(q.armed)
    end)

    local settings = { angleMode = true, maxAngle = 55, batterySim = false, yawRcRate = 100, yawRate = 70, yawExpo = 0 }
    local sticks = { ail = 0, ele = 0, rud = 0, thr = 1 }
    it("disarmed the motors are off: it sits on the ground", function()
      q:reset(0, 0, 0, 0)
      for _ = 1, 100 do
        assert.is_nil(q:step(0.01, sticks, settings))
      end
      assert.equal(0, q.py)
      assert.equal(0, q.throttle)
    end)
    it("disarmed in the air it falls", function()
      q:reset(0, 20, 0, 0)
      q.armed = true
      q:step(0.01, sticks, settings)
      assert.is_true(q.vy > 0)
      q.armed = false
      for _ = 1, 100 do
        q:step(0.01, sticks, settings)
      end
      assert.is_true(q.vy < -5, tostring(q.vy))
    end)
  end)
end)
