local app = ...

local gfx, settings, input = app.gfx, app.settings, app.input
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

local quad = Quad.new()
local Map, mapId
-- Freestyle maps: scoring; racing maps: the gates and lap clock. result: the crash screen's line
local tricks, race, result
-- A lap this run beat the map's best
local newBest
-- "arming": waiting for throttle low; "flying"; "crashed"
local state
local stateTime = 0

local function respawn()
  local s = Map.spawn
  quad:reset(s.x, s.y, s.z, s.heading)
  state = "arming"
  if tricks then
    tricks:reset()
  elseif race then
    race:reset()
    newBest = false
  end
end

-- The run ends: the score is kept if it is the map's best
local function crash()
  state = "crashed"
  stateTime = 0
  if tricks then
    local score = tricks.score
    if score > 0 and app.save.record(mapId, score) then
      result = string.format("NEW BEST %d", score)
    else
      result = string.format("PTS %d", score)
    end
  elseif race then
    local best = race.best
    result = best and string.format(newBest and "NEW BEST %.2fS" or "BEST LAP %.2fS", best) or "NO LAP"
  end
end

local Flight = {}

-- entry: the map's catalogue entry
function Flight.enter(entry)
  Map = nil
  Map = app.load("maps/" .. entry.id, World, Scene, Course)
  mapId = entry.id
  tricks = entry.mode == "freestyle" and app.load("core/tricks", Course).new(Map) or nil
  race = entry.mode == "racing" and app.load("core/race", Course).new(Map) or nil
  R.setView(0, 0, gfx.W, gfx.H, settings.fov, settings.camAngle)
  respawn()
end

function Flight.run(event, dt)
  if event == EVT_VIRTUAL_EXIT then
    if tricks and state ~= "crashed" and tricks.score > 0 then
      app.save.record(mapId, tricks.score)
    end
    Map, tricks, race = nil, nil, nil
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
    local frame = dt
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
    if quad.dead then
      message = "BATTERY EMPTY"
      -- Motors are off: the run ends where the quad comes down, crash or not
      if state == "flying" and quad.grounded then
        crash()
      end
    end
    if tricks and state == "flying" then
      tricks:update(frame, quad)
    elseif race and state == "flying" then
      race:update(frame, quad)
      -- Lap times are kept in hundredths, lowest best
      local lap = race.finished
      if lap then
        race.finished = nil
        if app.save.record(mapId, math.floor(lap * 100 + 0.5), true) then
          newBest = true
        end
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
    if race then
      race:drawMarker(R, gfx)
    end
  end
  if loss > 0 then
    gfx.static(loss)
    if not message and loss > OUT_OF_RANGE and getTime() % 100 < 60 then
      message = "OUT OF RANGE"
    end
  end
  local goal, note, clock
  local scoring = tricks or race
  if scoring then
    goal = scoring.goal
    note = state == "crashed" and result or scoring.note
  end
  if race then
    clock = race.clock
  end
  Hud.draw(quad, settings, goal, message, note, clock)
end

return Flight
