-- Racing: the map's gates in order, the first being start and finish. The clock starts through the first gate and
-- each pass through it after all the others closes a lap. Only the next gate is tested, one plane a frame.

local Course = ...

local format, floor, sqrt = string.format, math.floor, math.sqrt
local through = Course.through

-- Seconds a lap time stays on the note line
local LAP_SHOW = 2

local Race = {}
Race.__index = Race

-- map.gates: Course.addGate openings in course order; sound: platform/sound, optional; save: core/save, id: the
-- map's key there
function Race.new(map, sound, save, id)
  local r = setmetatable({ gates = map.gates, sound = sound, save = save, id = id }, Race)
  r:reset()
  return r
end

function Race:reset()
  self.next, self.lap, self.time = 1, 0, 0
  -- Best lap of this run in seconds, the last lap closed, and whether a lap beat the map's best
  self.best, self.last, self.newBest = nil, nil, false
  self.show = 0
  -- HUD: goal the next gate and its distance (top right), clock the lap time (top centre), note a closed lap
  self.goal, self.clock, self.note = nil, nil, nil
  self.goalVal, self.clockVal, self.lapNote = nil, nil, nil
end

-- Once per frame of flight, after the physics; ox, oy, oz: where the quad was before it
function Race:update(dt, q, ox, oy, oz)
  local gates = self.gates
  local n = #gates
  local px, py, pz = q.px, q.py, q.pz
  if self.lap > 0 then
    self.time = self.time + dt
  end
  local g = gates[self.next]
  if through(g, ox, oy, oz, px, py, pz) then
    if self.next == 1 then
      if self.lap > 0 then
        local t = self.time
        self.last = t
        if not self.best or t < self.best then
          self.best = t
        end
        self.lapNote = format("LAP %d %.2fS", self.lap, t)
        self.show = LAP_SHOW
        -- Lap times are kept in hundredths, lowest best
        local newBest = self.save.record(self.id, floor(t * 100 + 0.5), true)
        if newBest then
          self.newBest = true
        end
        if self.sound then
          self.sound.cue(newBest and "bestLap" or "lap")
        end
      elseif self.sound then
        self.sound.cue("start")
      end
      self.lap, self.time = self.lap + 1, 0
    elseif self.sound then
      self.sound.gate(self.next, n)
    end
    self.next = self.next % n + 1
    g = gates[self.next]
  end

  -- Strings are rebuilt only when the shown number changes: the distance about every other frame, the clock
  -- every other
  local dx, dy, dz = g.cx - px, g.cy - py, g.cz - pz
  local d = floor(sqrt(dx * dx + dy * dy + dz * dz) + 0.5)
  local v = self.next * 10000 + d
  if v ~= self.goalVal then
    self.goalVal = v
    self.goal = format("%d/%d %dM", self.next, n, d)
  end
  if self.lap > 0 then
    v = floor(self.time * 10)
    if v ~= self.clockVal then
      self.clockVal = v
      self.clock = format("%.1fS", v / 10)
    end
  end
  if self.show > 0 then
    self.show = self.show - dt
    self.note = self.lapNote
  else
    self.note = nil
  end
end

-- The next gate's marker, two pixels thick so it reads over the scenery: a chevron over its top, held inside the
-- HUD bars when it is above or below the view, or an arrow on a white patch at the side it lies to when it is off
-- to the side or behind
function Race:draw(R, gfx)
  local g = self.gates[self.next]
  local W, H, FH = gfx.W, gfx.H, gfx.FH
  local cx, cy = W / 2, H / 2
  local x, y, z = R.toCamera(g.cx, g.top, g.cz)
  local f = R.focal()
  if z > 0.2 then
    local sx = x * f / z
    if sx > -cx + 4 and sx < cx - 4 then
      sx = cx + sx
      local sy = cy - y * f / z - 2
      if sy < FH + 6 then
        sy = FH + 6
      elseif sy > H - FH - 3 then
        sy = H - FH - 3
      end
      gfx.line(sx - 3, sy - 4, sx, sy - 1, 4)
      gfx.line(sx, sy - 1, sx + 3, sy - 4, 4)
      gfx.line(sx - 3, sy - 3, sx, sy, 4)
      gfx.line(sx, sy, sx + 3, sy - 3, 4)
      return
    end
  end
  if x < 0 then
    gfx.rect(0, cy - 5, 7, 11, 0)
    gfx.line(4, cy - 3, 1, cy, 4)
    gfx.line(1, cy, 4, cy + 3, 4)
    gfx.line(5, cy - 3, 2, cy, 4)
    gfx.line(2, cy, 5, cy + 3, 4)
  else
    gfx.rect(W - 7, cy - 5, 7, 11, 0)
    gfx.line(W - 5, cy - 3, W - 2, cy, 4)
    gfx.line(W - 2, cy, W - 5, cy + 3, 4)
    gfx.line(W - 6, cy - 3, W - 3, cy, 4)
    gfx.line(W - 3, cy, W - 6, cy + 3, 4)
  end
end

-- Laps are kept as they close
function Race:keep() end

-- The run ended in a crash: its best lap goes on the note line
function Race:finish()
  local best = self.best
  self.note = best and format(self.newBest and "NEW BEST %.2fS" or "BEST LAP %.2fS", best) or "NO LAP"
end

return Race
