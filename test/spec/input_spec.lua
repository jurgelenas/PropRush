-- Control mapping and source picking: each axis reads its chosen source, reversed when set, and moving a control
-- picks it.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/PropRush/" .. name .. ".lua"))(...)
end

describe("input", function()
  local settings, Input
  before_each(function()
    settings = load("config/settings")
    Input = load("platform/input", settings)
    H.sticks = { ail = 512, ele = -1024, thr = -1024, rud = 2000, ch1 = 1024, ch3 = -512 }
  end)

  it("reads the sticks by default, clamped", function()
    local s = Input.read()
    assert.equal(0.5, s.ail)
    assert.equal(-1, s.ele)
    assert.equal(1, s.rud)
    assert.equal(0, s.thr)
  end)

  it("reads channel sources", function()
    settings.rollSrc, settings.thrSrc = "ch3", "ch1"
    local s = Input.read()
    assert.equal(-0.5, s.ail)
    assert.equal(1, s.thr)
  end)

  it("reverses", function()
    settings.rollRev, settings.thrRev, settings.yawRev = true, true, true
    local s = Input.read()
    assert.equal(-0.5, s.ail)
    assert.equal(1, s.thr)
    assert.equal(-1, s.rud)
  end)

  it("falls back to the stick for a source the radio lacks", function()
    settings.pitchSrc = "nosuch"
    assert.equal(-1, Input.read().ele)
  end)

  describe("sources", function()
    local Sources, list
    before_each(function()
      Sources = load("platform/sources", Input)
      list = Sources.list()
    end)

    it("lists the sticks and pots, then the channels", function()
      assert.equal("rud ele thr ail s1 s2 ch1 ch2 ch3", table.concat(list.names, " "))
      assert.equal(6, list.moving)
    end)

    it("for arming lists ALWAYS, then the switches after the sticks and pots", function()
      list = Sources.list(true)
      assert.equal("always rud ele thr ail s1 s2 sa sb ch1 ch2 ch3", table.concat(list.names, " "))
      assert.equal(9, list.moving)
      assert.equal("ALWAYS", Sources.label(list, "always"))
      assert.equal("SB", Sources.label(list, "sb"))
    end)

    it("picks a switch flipped", function()
      list = Sources.list(true)
      H.sticks = { thr = -1024, sb = -1024 }
      Sources.snapshot(list)
      H.sticks.sb = 0
      assert.equal("sb", Sources.moved(list))
    end)

    it("labels in capitals, without icons", function()
      assert.equal("AIL", Sources.label(list, "ail"))
      assert.equal("S1", Sources.label(list, "s1"))
      assert.equal("CH9", Sources.label(list, "ch9"))
    end)

    it("picks a control moved well away", function()
      H.sticks = { ail = 0, ele = 0, thr = -1024, rud = 0, s2 = 0 }
      Sources.snapshot(list)
      H.sticks.ail = 200
      assert.is_nil(Sources.moved(list))
      H.sticks.s2 = -900
      assert.equal("s2", Sources.moved(list))
    end)
  end)
end)
