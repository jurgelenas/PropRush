-- Racing: the map's gates in order, the first being start and finish. The clock starts through the first gate and
-- each pass through it after all the others closes a lap. Only the next gate is tested, one plane a frame.

local Course = ...

local format, floor, sqrt = string.format, math.floor, math.sqrt
local through = Course.through

-- Seconds a lap time stays on the note line
local LAP_SHOW = 2

local Racing = {}
Racing.__index = Racing

-- map.gates: Course.addGate openings in course order; sound: platform/sound, optional; save: config/save, id: the
-- map's key there
function Racing.new(map, sound, save, id)
  local r = setmetatable({ gates = map.gates, sound = sound, save = save, id = id }, Racing)
  r:reset()
  return r
end

function Racing:reset()
  self.next, self.lap, self.time = 1, 0, 0
  -- Best lap of this run in seconds, the last lap closed, and whether a lap beat the map's best
  self.best, self.last, self.newBest = nil, nil, false
  self.show = 0
  -- HUD: goal the next gate and its distance (top right), clock the lap time (top centre), note a closed lap
  self.goal, self.clock, self.note = nil, nil, nil
  self.goalVal, self.clockVal, self.lapNote = nil, nil, nil
end

-- Once per frame of flight, after the physics; ox, oy, oz: where the quad was before it
function Racing:update(dt, q, ox, oy, oz)
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

-- Chevron pointing down at x, y on screen, held inside the HUD bars; bold: two pixels thick
local function chevron(gfx, x, y, bold)
  local FH = gfx.FH
  if y < FH + 6 then
    y = FH + 6
  elseif y > gfx.H - FH - 3 then
    y = gfx.H - FH - 3
  end
  gfx.line(x - 3, y - 3, x, y, 4)
  gfx.line(x, y, x + 3, y - 3, 4)
  if bold then
    gfx.line(x - 3, y - 4, x, y - 1, 4)
    gfx.line(x, y - 1, x + 3, y - 4, 4)
  end
end

-- Screen point of a marker at x, y, z, or nil when it is behind or off to the side; also its camera-space x
local function onScreen(R, gfx, x, y, z)
  x, y, z = R.toCamera(x, y, z)
  if z > 0.2 then
    local f, cx = R.focal() / z, gfx.W / 2
    local sx = x * f
    if sx > -cx + 4 and sx < cx - 4 then
      return cx + sx, gfx.H / 2 - y * f - 2, x
    end
  end
  return nil, nil, x
end

-- Arrow pointing sideways at x, y on screen, dir 1 right or -1 left, held as chevron is; bold: two pixels thick
local function sideways(gfx, x, y, dir, bold)
  local FH = gfx.FH
  if y < FH + 6 then
    y = FH + 6
  elseif y > gfx.H - FH - 3 then
    y = gfx.H - FH - 3
  end
  gfx.line(x - 3 * dir, y - 3, x, y, 4)
  gfx.line(x, y, x - 3 * dir, y + 3, 4)
  if bold then
    gfx.line(x - 4 * dir, y - 3, x - dir, y, 4)
    gfx.line(x - dir, y, x - 4 * dir, y + 3, 4)
  end
end

-- Gate g's marker: a chevron over its top, or for a way round (g.round) an arrow pointing back in at the frame as
-- the screen shows it, the way to turn. Returns whether it was on screen, and its camera-space x.
local function marker(R, gfx, g, bold)
  local sx, sy, x = onScreen(R, gfx, g.cx, g.top, g.cz)
  if not sx then
    return false, x
  end
  local round = g.round
  if round then
    -- A metre further out along the frame: x for a frame across z (axis 3), else z
    local ox, oz = g.axis == 3 and round or 0, g.axis == 3 and 0 or round
    local tx = onScreen(R, gfx, g.cx + ox, g.top, g.cz + oz)
    local dir = -round
    if tx then
      dir = tx < sx and 1 or -1
    end
    sideways(gfx, sx, sy, dir, bold)
  else
    chevron(gfx, sx, sy, bold)
  end
  return true, x
end

-- The next gate's marker, two pixels thick so it reads over the scenery, held inside the HUD bars when it is above
-- or below the view, or an arrow on a white patch at the side it lies to when it is off to the side or behind. A
-- thin marker previews what comes after when it is a way round, or the next opening of the same piece (into a cube
-- and out of a side) and further away.
function Racing:draw(R, gfx)
  local gates = self.gates
  local g = gates[self.next]
  local after = gates[self.next % #gates + 1]
  if after.round then
    marker(R, gfx, after, false)
  elseif g.piece and after.piece == g.piece then
    -- Not while the one after is the nearer: from that side it would read as the way in
    local ox, oy, oz = R.cameraPos()
    local ax, ay, az, gx, gy, gz = after.cx - ox, after.cy - oy, after.cz - oz, g.cx - ox, g.cy - oy, g.cz - oz
    if ax * ax + ay * ay + az * az > gx * gx + gy * gy + gz * gz then
      marker(R, gfx, after, false)
    end
  end
  local shown, x = marker(R, gfx, g, true)
  if shown then
    return
  end
  local W, cy = gfx.W, gfx.H / 2
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
function Racing:keep() end

-- The run ended in a crash: its best lap goes on the note line
function Racing:finish()
  local best = self.best
  self.note = best and format(self.newBest and "NEW BEST %.2fS" or "BEST LAP %.2fS", best) or "NO LAP"
end

return Racing
