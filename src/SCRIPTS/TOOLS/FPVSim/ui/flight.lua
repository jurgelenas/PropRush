local app = ...

local gfx, settings, input, Sound = app.gfx, app.settings, app.input, app.sound
local R = app.load("core/render3d")
local Quad = app.load("core/quad", app.rates)
local World = app.load("core/world", R)
local Scene = app.load("core/scene", R)
local Course = app.load("core/course", R, Scene)
local Hud = app.load("ui/hud", gfx)

R.setSink(gfx)

local MAX_STEP = 0.02
-- Frames longer than this (menu pauses, load hitches) are not simulated in full
local MAX_FRAME = 0.1
-- Long enough to read the run's score
local CRASH_SHOW = 2
-- Crash static: full snow for CRASH_HOLD seconds, then fading out until the respawn
local CRASH_HOLD = 0.2
local ARM_THROTTLE = 0.05
-- Signal loss at which the warning starts blinking
local OUT_OF_RANGE = 0.1
-- Throttle-down reminder: first after NAG_FIRST seconds of arming, then every NAG_EVERY
local NAG_FIRST, NAG_EVERY = 0.8, 1.5
-- Low battery beeps: cell voltage under LOW_CELL for LOW_TIME seconds, then every LOW_EVERY, LOW_MAX times; over
-- LOW_CLEAR it starts over
local LOW_CELL, LOW_CLEAR, LOW_TIME, LOW_EVERY, LOW_MAX = 3.3, 3.4, 1, 8, 3

local quad = Quad.new()
local Map
-- Freestyle maps: core/tricks, the scoring; racing maps: core/race, the gates and lap clock. Either keeps the
-- map's best and gives the HUD its goal, note and clock.
local mode
-- "arming": waiting for throttle low; "flying"; "crashed"
local state
local stateTime = 0
-- Sound state: next throttle reminder, seconds of low battery and beeps given, battery dead, out of range warned,
-- the warning blink was on
local nagAt, lowTime, lowBeeps, dead, warned, blinkOn

local function respawn()
  local s = Map.spawn
  quad:reset(s.x, s.y, s.z, s.heading)
  state, stateTime, nagAt = "arming", 0, NAG_FIRST
  lowTime, lowBeeps, dead, warned = 0, 0, false, false
  Sound.cue("respawn")
  mode:reset()
end

local function crash()
  state = "crashed"
  stateTime = 0
  Sound.crash(quad.dead)
  mode:finish()
end

local Flight = {}

-- entry: the map's catalogue entry
function Flight.enter(entry)
  Map = nil
  Map = app.load("maps/" .. entry.id, World, Scene, Course)
  mode = app.load(entry.mode == "racing" and "core/race" or "core/tricks", Course).new(Map, Sound, app.save, entry.id)
  R.setView(0, 0, gfx.W, gfx.H, settings.fov, settings.camAngle)
  respawn()
end

function Flight.run(event, dt)
  if event == EVT_VIRTUAL_EXIT then
    if state ~= "crashed" then
      mode:keep()
    end
    Map, mode = nil, nil
    Sound.stop()
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
      Sound.cue("armed")
    else
      message = "THROTTLE DOWN"
      stateTime = stateTime + dt
      if stateTime >= nagAt then
        nagAt = nagAt + NAG_EVERY
        Sound.cue("throttle")
      end
    end
  elseif state == "flying" then
    Map.update(dt, quad)
    local frame = dt
    local fx, fy, fz = quad.px, quad.py, quad.pz
    while dt > 0 do
      local h = dt > MAX_STEP and MAX_STEP or dt
      dt = dt - h
      local ox, oy, oz = quad.px, quad.py, quad.pz
      local crashed = quad:step(h, sticks, settings)
      if not crashed then
        local hit = Map.collides(quad.px, quad.py, quad.pz)
        crashed = hit == true or hit and Scene.collide(hit, quad, ox, oy, oz, h)
      end
      if crashed then
        crash()
        break
      end
    end
    if state == "flying" then
      Sound.contact(quad.hit, quad.struck)
      Sound.motor(quad, frame)
      local v = quad.voltage
      if quad.dead then
        if not dead then
          dead = true
          Sound.cue("empty")
        end
      elseif v < LOW_CELL then
        lowTime = lowTime + frame
        if lowBeeps < LOW_MAX and lowTime >= LOW_TIME + LOW_EVERY * lowBeeps then
          lowBeeps = lowBeeps + 1
          -- Three beeps
          Sound.cue("low", 2)
        end
      elseif v > LOW_CLEAR then
        lowTime, lowBeeps = 0, 0
      end
    end
    quad.hit, quad.struck = 0, 0
    if quad.dead then
      message = "BATTERY EMPTY"
      -- Motors are off: the run ends where the quad comes down, crash or not
      if state == "flying" and quad.grounded then
        crash()
      end
    end
    if state == "flying" then
      mode:update(frame, quad, fx, fy, fz)
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
  local blink = getTime() % 100 < 60
  if state == "flying" then
    Sound.crackle(loss)
    if loss > OUT_OF_RANGE then
      if blink and not blinkOn then
        warned = true
        Sound.cue("range")
      end
    elseif warned then
      warned = false
      Sound.cue("link")
    end
  end
  blinkOn = blink
  if state == "crashed" then
    local hit = stateTime < CRASH_HOLD and 1 or (CRASH_SHOW - stateTime) / (CRASH_SHOW - CRASH_HOLD)
    if hit > loss then
      loss = hit
    end
  end

  gfx.clear()
  if loss < 1 then
    R.setCamera(quad)
    Map.draw(settings.quality)
    mode:draw(R, gfx)
  end
  if loss > 0 then
    gfx.static(loss)
    if not message and loss > OUT_OF_RANGE and blink then
      message = "OUT OF RANGE"
    end
  end
  Hud.draw(quad, settings, mode.goal, message, mode.note, mode.clock)
end

return Flight
