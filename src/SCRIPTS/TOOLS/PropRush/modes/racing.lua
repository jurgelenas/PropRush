-- Racing: the map's gates in order, the first being start and finish. The clock starts through the first gate and
-- each pass through it after all the others closes a lap. Only the next gate is tested, one plane a frame, and
-- only flown its way through.

local Gap = ...

local format, floor, sqrt = string.format, math.floor, math.sqrt
local through = Gap.through
-- Cue numbers (platform/cues)
local CUE_DENY, CUE_START, CUE_LAP, CUE_BEST_LAP = 1, 37, 39, 40

-- Seconds a lap time or WRONG WAY stays on the note line
local NOTE_SHOW = 2

-- Way through each gate ([15]: 1 towards +x, +y or +z across its plane, -1 back) unless the map set it (Course.dir):
-- away from the side the gate before's centre lies, or back the way that one went when it is in the same plane
local function directions(gates)
  local n = #gates
  for i = 1, n do
    local g = gates[i]
    if not g[15] then
      local p = gates[(i - 2) % n + 1]
      -- axis; at, the gate before's centre on that axis
      local axis = g[1]
      local d = p[8 + axis] - g[2]
      if d > 0.5 or d < -0.5 then
        g[15] = d < 0 and 1 or -1
      else
        assert(p[1] == axis and p[15], "gate " .. i .. " needs Course.dir")
        g[15] = -p[15]
      end
    end
  end
end

local Racing = {}
Racing.__index = Racing

-- map.gates: Course.addGate openings in course order; sound: platform/sound, optional; highscore: config/highscore, id: the
-- map's key there
function Racing.new(map, sound, highscore, id)
  directions(map.gates)
  local r = setmetatable({ gates = map.gates, sound = sound, highscore = highscore, id = id }, Racing)
  r:reset()
  return r
end

function Racing:reset()
  self.next, self.lap, self.time = 1, 0, 0
  -- Best lap of this run in seconds, the last lap closed, and whether a lap beat the map's best
  self.best, self.last, self.newBest = nil, nil, false
  self.show = 0
  -- HUD: goal the next gate and its distance (top right), clock the lap time (top centre), note a closed lap or
  -- WRONG WAY
  self.goal, self.clock, self.note = nil, nil, nil
  self.goalVal, self.clockVal, self.shown = nil, nil, nil
end

-- True, with WRONG WAY and the deny cue, when the quad came out of gate g's plane on the side it should go in from
function Racing:wrongWay(g, px, py, pz)
  -- axis, at, dir
  local axis = g[1]
  if ((axis == 1 and px or axis == 2 and py or pz) > g[2]) == (g[15] > 0) then
    return false
  end
  self.shown, self.show = "WRONG WAY", NOTE_SHOW
  if self.sound then
    self.sound.cue(CUE_DENY)
  end
  return true
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
  if through(g, ox, oy, oz, px, py, pz) and not self:wrongWay(g, px, py, pz) then
    if self.next == 1 then
      if self.lap > 0 then
        local t = self.time
        self.last = t
        if not self.best or t < self.best then
          self.best = t
        end
        self.shown = format("LAP %d %.2fS", self.lap, t)
        self.show = NOTE_SHOW
        -- Lap times are kept in hundredths, lowest best
        local newBest = self.highscore.record(self.id, floor(t * 100 + 0.5), true)
        if newBest then
          self.newBest = true
        end
        if self.sound then
          self.sound.cue(newBest and CUE_BEST_LAP or CUE_LAP)
        end
      elseif self.sound then
        self.sound.cue(CUE_START)
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
  -- cx, cy, cz
  local dx, dy, dz = g[9] - px, g[10] - py, g[11] - pz
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
    self.note = self.shown
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

-- Gate g's marker: a chevron over its top, or for a way round an arrow pointing back in at the frame as
-- the screen shows it, the way to turn. Returns whether it was on screen, and its camera-space x.
local function marker(R, gfx, g, bold)
  -- cx, top, cz
  local cx, top, cz = g[9], g[12], g[11]
  local sx, sy, x = onScreen(R, gfx, cx, top, cz)
  if not sx then
    return false, x
  end
  -- round
  local round = g[14]
  if round then
    -- A metre further out along the frame: x for a frame across z (axis 3), else z
    local ox, oz = g[1] == 3 and round or 0, g[1] == 3 and 0 or round
    local tx = onScreen(R, gfx, cx + ox, top, cz + oz)
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
  -- round; piece
  if after[14] then
    marker(R, gfx, after, false)
  elseif g[13] and after[13] == g[13] then
    -- Not while the one after is the nearer: from that side it would read as the way in. [9..11]: cx, cy, cz
    local ox, oy, oz = R.cameraPos()
    local ax, ay, az, gx, gy, gz = after[9] - ox, after[10] - oy, after[11] - oz, g[9] - ox, g[10] - oy, g[11] - oz
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
