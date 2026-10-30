-- Save files round trip and damaged-file handling.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local PATH = "/SCRIPTS/TOOLS/FPVSim/save.txt"
local BESTS = "/SCRIPTS/TOOLS/FPVSim/bests.txt"

local items = load("config/items")

local function fresh()
  local settings = load("config/settings")
  local Save = load("config/save", load("platform/storage"), settings)
  Save.load(items)
  return settings, Save
end

describe("save", function()
  before_each(function()
    H.files = {}
  end)

  it("keeps the defaults without a file", function()
    local settings = fresh()
    assert.equal(45, settings.camAngle)
    assert.is_false(settings.angleMode)
  end)

  describe("bests", function()
    it("a higher score beats the best", function()
      local _, Save = fresh()
      Save.record("pillars", 1200)
      assert.is_false(Save.record("pillars", 900))
      assert.is_true(Save.record("pillars", 1500))
    end)
    it("a lower lap time beats the best", function()
      local _, Save = fresh()
      assert.is_true(Save.record("gates", 42.5, true))
      assert.is_false(Save.record("gates", 50, true))
    end)
    it("are written only when flushed, and only when one changed", function()
      local _, Save = fresh()
      Save.record("pillars", 1200)
      assert.is_nil(H.files[BESTS])
      assert.is_nil(H.files[PATH])
      Save.flush()
      assert.equal("pillars=1200\n", H.files[BESTS])
      H.files[BESTS] = nil
      Save.record("pillars", 900)
      Save.flush()
      assert.is_nil(H.files[BESTS])
    end)
  end)

  it("round trips settings, the control mapping and bests", function()
    local settings, Save = fresh()
    settings.camAngle, settings.angleMode, settings.batterySim, settings.rollExpo = 63, true, false, 54
    settings.rollSrc, settings.thrSrc, settings.thrRev = "ch3", "ch1", true
    Save.record("pillars", 1500)
    Save.record("gates", 42.5, true)
    Save.write(items)
    Save.flush()
    assert.is_nil(string.find(H.files[PATH], "pillars"), "bests stay out of the settings file")

    settings, Save = fresh()
    assert.equal(63, settings.camAngle)
    assert.is_true(settings.angleMode)
    assert.is_false(settings.batterySim)
    assert.equal(54, settings.rollExpo)
    assert.equal("ch3", settings.rollSrc)
    assert.equal("ch1", settings.thrSrc)
    assert.is_true(settings.thrRev)
    assert.same({ pillars = 1500, gates = 42.5 }, Save.bests)
  end)

  describe("a damaged file", function()
    local settings, Save
    before_each(function()
      H.files[PATH] = "camAngle=999\nquality=7\nangleMode=maybe\nrollRcRate=abc\n\0\1junk\nrollRate=12.5\n"
        .. "yawRcRate=150\nrollSrc=../x\nyawSrc=ch2\n"
      H.files[BESTS] = "pillars=77\nx=notanumber\n\0junk\n"
      settings, Save = fresh()
    end)

    it("ignores out-of-range values", function()
      assert.equal(45, settings.camAngle)
      assert.equal(3, settings.quality)
      assert.is_false(settings.angleMode)
    end)
    it("ignores non-numeric and off-step values", function()
      assert.equal(100, settings.rollRcRate)
      assert.equal(70, settings.rollRate)
    end)
    it("keeps a valid value next to junk", function()
      assert.equal(150, settings.yawRcRate)
      assert.equal("ch2", settings.yawSrc)
    end)
    it("ignores a malformed control source", function()
      assert.equal("ail", settings.rollSrc)
    end)
    it("keeps only numeric bests", function()
      assert.same({ pillars = 77 }, Save.bests)
    end)
  end)
end)
