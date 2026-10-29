local app = ...

local gfx, settings, input = app.gfx, app.settings, app.input
local R = app.load("core/render3d")
local Quad = app.load("core/quad", app.rates)
local Kit = app.load("core/kit", R)
local Hud = app.load("ui/hud", gfx)

R.setSink(gfx)

local MAX_STEP = 0.02
-- Frames longer than this (menu pauses, load hitches) are not simulated in full
local MAX_FRAME = 0.1
local CRASH_SHOW = 1.5
local ARM_THROTTLE = 0.05
-- Signal loss at which the warning starts blinking
local OUT_OF_RANGE = 0.1

local quad = Quad.new()
local Map
-- "arming": waiting for throttle low; "flying"; "crashed"
local state
local stateTime = 0

local function respawn()
  local s = Map.spawn
  quad:reset(s.x, s.y, s.z, s.heading)
  state = "arming"
end

local Flight = {}

-- entry: the map's catalogue entry
function Flight.enter(entry)
  Map = nil
  Map = app.load("maps/" .. entry.id, Kit, R)
  respawn()
end

function Flight.run(event, dt)
  if event == EVT_VIRTUAL_EXIT then
    Map = nil
    return "menu"
  end

  local sticks = input.read()
  if dt > MAX_FRAME then
    dt = MAX_FRAME
  end

  local message
  if state == "arming" then
    quad.throttle = sticks.thr
    if sticks.thr < ARM_THROTTLE then
      state = "flying"
    else
      message = "THROTTLE DOWN"
    end
  elseif state == "flying" then
    Map.update(dt, quad)
    while dt > 0 do
      local h = dt > MAX_STEP and MAX_STEP or dt
      dt = dt - h
      if quad:step(h, sticks, settings) or Map.collides(quad.px, quad.py, quad.pz) then
        state = "crashed"
        stateTime = 0
        break
      end
    end
    if quad.dead then
      message = "BATTERY EMPTY"
      -- Motors are off: the run ends where the quad comes down, crash or not
      if state == "flying" and quad.py <= 0 then
        state = "crashed"
        stateTime = 0
      end
    end
  else
    stateTime = stateTime + dt
    message = quad.dead and "BATTERY EMPTY" or "CRASH"
    if stateTime > CRASH_SHOW then
      respawn()
    end
  end

  -- Loss rises with the square of distance past the fade start: a slow onset, then a quick breakup
  local loss = Map.signalLoss(quad.px, quad.py, quad.pz)
  loss = loss * loss

  gfx.clear()
  if loss < 1 then
    R.setCamera(quad, settings.camAngle, 0, 0, gfx.W, gfx.H, settings.fov)
    Map.draw(settings.quality)
  end
  if loss > 0 then
    gfx.static(loss)
    if not message and loss > OUT_OF_RANGE and getTime() % 100 < 60 then
      message = "OUT OF RANGE"
    end
  end
  Hud.draw(quad, settings, nil, message)
end

return Flight
