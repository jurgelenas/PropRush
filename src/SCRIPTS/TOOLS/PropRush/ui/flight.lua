local app = ...

local gfx, settings, input, Sound = app.gfx, app.settings, app.input, app.sound
local R = app.load("gfx/render3d")
local Quad = app.load("physics/quad", app.rates)
local Ground = app.load("world/ground", R)
local Scene = app.load("world/scene", R)
local Gap = app.load("world/gap")
local Hud = app.load("ui/hud", gfx)

R.setSink(gfx)

-- EXIT pauses into ui/pause (about 8 KB more heap while paused); false: EXIT leaves flight at once
local PAUSE_MENU = true
-- Cue numbers (platform/cues)
local CUE_THROTTLE, CUE_ARMED, CUE_DISARMED, CUE_RESPAWN, CUE_LOW, CUE_EMPTY, CUE_RANGE, CUE_LINK =
  3, 4, 5, 6, 12, 13, 14, 15
local MAX_STEP = 0.02
-- Frames longer than this (menu pauses, load hitches) are not simulated in full
local MAX_FRAME = 0.1
-- Long enough to read the run's score
local CRASH_SHOW = 2
-- Crash static: full snow for CRASH_HOLD seconds, then fading out until the respawn
local CRASH_HOLD = 0.2
-- Signal loss at which the warning starts blinking
local OUT_OF_RANGE = 0.1
-- Throttle-down reminder: first after NAG_FIRST seconds of waiting to arm, then every NAG_EVERY
local NAG_FIRST, NAG_EVERY = 0.8, 1.5
-- Low battery beeps: cell voltage under LOW_CELL for LOW_TIME seconds, then every LOW_EVERY, LOW_MAX times; over
-- LOW_CLEAR it starts over
local LOW_CELL, LOW_CLEAR, LOW_TIME, LOW_EVERY, LOW_MAX = 3.3, 3.4, 1, 8, 3

local quad = Quad.new()
local Map
-- Freestyle maps: modes/freestyle, the scoring; racing maps: modes/racing, the gates and lap clock. Either keeps the
-- map's best and gives the HUD its goal, note and clock.
local mode
-- "flying" (armed or not) or "crashed"
local state
local stateTime = 0
-- Sound state: seconds waiting for the throttle to arm and the next reminder, seconds of low battery and beeps
-- given, battery dead, out of range warned, the warning blink was on
local waitTime, nagAt, lowTime, lowBeeps, dead, warned, blinkOn
-- ui/pause while paused
local pause

local function respawn()
  -- The run's garbage goes before the next one starts, under the static
  collectgarbage("collect")
  local s = Map.spawn
  quad:reset(s.x, s.y, s.z, s.heading)
  state, stateTime, waitTime, nagAt = "flying", 0, 0, NAG_FIRST
  lowTime, lowBeeps, dead, warned = 0, 0, false, false
  Sound.cue(CUE_RESPAWN)
  mode:reset()
end

local function crash()
  state = "crashed"
  stateTime = 0
  Sound.crash(quad.dead)
  mode:finish()
  app.highscore.flush()
end

local Flight = {}

-- entry: the map's catalogue entry
function Flight.enter(entry)
  Map = nil
  Map = app.load("maps/" .. entry.mode .. "/" .. entry.id, Ground, Scene, Gap, R, app.load)
  mode = app.load("modes/" .. entry.mode, Gap).new(Map, Sound, app.highscore, entry.id)
  R.setView(0, 0, gfx.W, gfx.H, settings.fov, settings.camAngle)
  respawn()
end

local function leave()
  if state ~= "crashed" then
    mode:keep()
  end
  app.highscore.flush()
  Map, mode, pause = nil, nil, nil
  Sound.stop()
  return "menu"
end

-- Paused: nothing moves and the clocks stop; the view is drawn as it stands under the menu, with the camera as
-- set there
local function paused(event)
  local action = pause.run(event)
  if action == "quit" then
    return leave()
  elseif action then
    pause = nil
    if action == "restart" then
      if state ~= "crashed" then
        mode:keep()
      end
      respawn()
    else
      collectgarbage("collect")
    end
  end
  R.setView(0, 0, gfx.W, gfx.H, settings.fov, settings.camAngle)
  gfx.clear()
  R.setCamera(quad)
  Map.draw(settings.quality)
  mode:draw(R, gfx)
  if pause then
    pause.draw()
  end
end

function Flight.run(event, dt)
  if event == EVT_VIRTUAL_EXIT and not pause then
    if not PAUSE_MENU then
      return leave()
    end
    Sound.stop()
    pause = app.load("ui/pause", app)
    event = 0
  end
  if pause then
    return paused(event)
  end

  local sticks = input.read()
  if dt > MAX_FRAME then
    dt = MAX_FRAME
  end

  local message
  if state == "flying" then
    -- Disarmed the quad still flies, motors off: it falls, lands or crashes
    local arming = quad:arm(input.arm(), sticks.thr)
    if arming == "throttle" then
      message = "THROTTLE DOWN"
      waitTime = waitTime + dt
      if waitTime >= nagAt then
        nagAt = nagAt + NAG_EVERY
        Sound.cue(CUE_THROTTLE)
      end
    else
      waitTime, nagAt = 0, NAG_FIRST
      if arming then
        Sound.cue(arming == "armed" and CUE_ARMED or CUE_DISARMED)
      end
      if not quad.armed then
        message = "ARM TO FLY"
      end
    end
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
          Sound.cue(CUE_EMPTY)
        end
      elseif v < LOW_CELL then
        lowTime = lowTime + frame
        if lowBeeps < LOW_MAX and lowTime >= LOW_TIME + LOW_EVERY * lowBeeps then
          lowBeeps = lowBeeps + 1
          -- Three beeps
          Sound.cue(CUE_LOW, 2)
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
        Sound.cue(CUE_RANGE)
      end
    elseif warned then
      warned = false
      Sound.cue(CUE_LINK)
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
