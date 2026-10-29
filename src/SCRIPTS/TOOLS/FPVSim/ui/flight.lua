local app = ...

local gfx, settings, input = app.gfx, app.settings, app.input
local R = app.load("core/render3d")
local Quad = app.load("core/quad")
local World = app.load("core/world", R)
local Hud = app.load("ui/hud", gfx)

R.setSink(gfx)

local MAX_STEP = 0.02
-- Frames longer than this (menu pauses, load hitches) are not simulated in full
local MAX_FRAME = 0.1
local CRASH_SHOW = 1.5
local ARM_THROTTLE = 0.05

local quad = Quad.new()
-- "arming": waiting for throttle low; "flying"; "crashed"
local state
local stateTime = 0

local function respawn()
  local s = World.spawn
  quad:reset(s.x, s.y, s.z, s.heading)
  state = "arming"
end

local Flight = {}

function Flight.enter()
  respawn()
end

function Flight.run(event, dt)
  if event == EVT_VIRTUAL_EXIT then
    return "intro"
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
    while dt > 0 do
      local h = dt > MAX_STEP and MAX_STEP or dt
      dt = dt - h
      if quad:step(h, sticks, settings) or World.collides(quad.px, quad.py, quad.pz) then
        state = "crashed"
        stateTime = 0
        break
      end
    end
    if state == "flying" and quad.battery <= 0 then
      state = "crashed"
      stateTime = 0
    end
  else
    stateTime = stateTime + dt
    message = quad.battery <= 0 and "BATTERY EMPTY" or "CRASH"
    if stateTime > CRASH_SHOW then
      respawn()
    end
  end

  gfx.clear()
  R.setCamera(quad, settings.camAngle, 0, 0, gfx.W, gfx.H, settings.fov)
  World.draw(settings.quality)
  Hud.draw(quad, settings, nil, message)
end

return Flight
