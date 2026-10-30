-- The version check before the game: older EdgeTX gets a screen saying so instead.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function start(major, minor, rev)
  H.version = { major, minor, rev }
  H.files = {}
  local tool = assert(loadfile("src/SCRIPTS/TOOLS/PropRush/main.lua"))()
  tool.init()
  return tool
end

local function frame(tool, event)
  H.time = H.time + 5
  H.resetStats()
  return tool.run(event or 0)
end

local function shown()
  local t = {}
  for _, s in pairs(H.text) do
    t[#t + 1] = s
  end
  return table.concat(t, " ")
end

describe("firmware check", function()
  it("stops on 2.12.3", function()
    local tool = start(2, 12, 3)
    frame(tool)
    assert.truthy(shown():find("Needs EdgeTX 2.12.4", 1, true))
    assert.truthy(shown():find("runs 2.12.3", 1, true))
  end)

  it("quits from it on EXIT", function()
    local tool = start(2, 11, 9)
    frame(tool)
    assert.equal(1, frame(tool, EVT_VIRTUAL_EXIT))
  end)

  it("starts the game on 2.12.4", function()
    local tool = start(2, 12, 4)
    frame(tool)
    assert.truthy(shown():find("PROPRUSH", 1, true))
    assert.falsy(shown():find("Needs EdgeTX", 1, true))
  end)

  it("starts the game on 3.0.0", function()
    local tool = start(3, 0, 0)
    frame(tool)
    assert.falsy(shown():find("Needs EdgeTX", 1, true))
  end)
end)
