-- TNS|PropRush|TNE

local BASE = "/SCRIPTS/TOOLS/PropRush/"

-- Collects before each load: first-run compiles otherwise run B&W radios out of memory
local function load(name, ...)
  collectgarbage("collect")
  local chunk, err = loadScript(string.format("%s%s.lua", BASE, name))
  if chunk == nil then
    error(string.format("%s: %s", name, tostring(err)))
  end
  return chunk(...)
end

local app = { load = load }
local screen
local lastTime

-- Screens are loaded when opened, and the previous one is released first: menus and flight are never
-- in memory together.
local function switchTo(name, arg)
  screen = nil
  screen = load("ui/" .. name, app)
  if screen.enter then
    screen.enter(arg)
  end
  -- Frees what compiling and building the screen left behind
  collectgarbage("collect")
end

local function init()
  app.gfx = load("gfx/bw")
  app.rates = load("physics/rates")
  app.settings = load("config/settings")
  app.storage = load("platform/storage")
  load("config/prefs", app.storage, app.settings).read(load("config/items", load))
  app.highscore = load("config/highscore", app.storage)
  app.highscore.load()
  app.input = load("platform/input", app.settings)
  app.sound = load("platform/sound", app.settings, load("platform/cues"))
  switchTo("intro")
  lastTime = getTime()
end

local function run(event)
  local now = getTime()
  local dt = (now - lastTime) / 100
  lastTime = now

  local nextScreen, arg = screen.run(event, dt)
  if nextScreen == "quit" then
    return 1
  elseif nextScreen then
    switchTo(nextScreen, arg)
  end
  return 0
end

return { init = init, run = run }
