-- TNS|FPV Sim|TNE

local BASE = "/SCRIPTS/TOOLS/FPVSim/"

-- Collects before each load: first-run compiles otherwise run B&W radios out of memory
local function load(name, ...)
  collectgarbage("collect")
  local chunk = loadScript(string.format("%s%s.lua", BASE, name))
  if chunk == nil then
    error(name)
  end
  return chunk(...)
end

local app = { load = load }
local screens = {}
local screen
local lastTime

local function switchTo(name)
  screen = screens[name]
  if screen.enter then
    screen.enter()
  end
end

local function init()
  app.gfx = load("gfx/bw")
  app.settings = load("core/settings")
  app.input = load("platform/input")
  screens.intro = load("ui/intro", app)
  screens.flight = load("ui/flight", app)
  switchTo("intro")
  lastTime = getTime()
end

local function run(event)
  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now

  local nextScreen = screen.run(event, dt)
  if nextScreen == "quit" then
    return 1
  elseif nextScreen then
    switchTo(nextScreen)
  end
  return 0
end

return { init = init, run = run }
