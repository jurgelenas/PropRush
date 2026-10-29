-- Freestyle scoring: tricks read from the quad's flight, chained into combos. Each trick scores at once, times the
-- combo multiplier, which grows with every trick within COMBO_TIME of the last; a prop strike or a crash resets it.

local Kit = ...

local format, floor, abs = string.format, math.floor, math.abs

local RAD = math.pi / 180
-- Flips and rolls: the quad's turn about pitch and roll is summed from leaving upright (up axis height under
-- UPRIGHT); one that went past INVERTED counts its whole turns once it has been upright again for SETTLE seconds,
-- so a double roll passing upright midway stays one trick. Leaving upright skips ~45 degrees of a turn, so
-- TURN_SLACK makes up for that and some sloppiness.
local UPRIGHT, INVERTED = 0.7, -0.3
local SETTLE = 0.2
local TURN_SLACK = 120 * RAD
local TURN = 360 * RAD
-- n turns in one go score TURN_POINTS * (1 + 2 + .. + n)
local TURN_POINTS = 10
-- Dives: a descent starts below DIVE_START m/s down and ends above DIVE_END; it counts when it dropped DIVE_DROP
-- metres, reached DIVE_SPEED and went nose down (forward axis height under NOSE_DOWN), pulled out before landing
local DIVE_START, DIVE_END = -3, -1
local DIVE_DROP, DIVE_SPEED = 10, 10
local NOSE_DOWN = -0.5
local DIVE_POINTS = 1
-- From a turn's flight path (velocity and height on the last upright frame before it): a single flip from LOOP_SPEED m/s that climbs LOOP_RISE
-- metres and reverses at the top is a power loop; through inverted with no whole turn, coming out the opposite way
-- (over 135 degrees off) SPLIT_DROP metres lower, a split-S
local LOOP_SPEED, LOOP_RISE, LOOP_POINTS = 5, 4, 20
local SPLIT_DROP, SPLIT_POINTS = 3, 15
-- Yaw spins: yaw summed while it turns faster than SPIN_RATE; whole turns score as flips do. With the throttle
-- under TRIPPY_THROTTLE and falling all through, a trippy spin, worth double.
local SPIN_RATE = 180 * RAD
local SPIN_SLACK = 30 * RAD
local TRIPPY_THROTTLE = 0.15
-- Inverted hang: up axis height under HANG_UY for HANG_TIME seconds or more, HANG_POINTS a second
local HANG_UY, HANG_TIME, HANG_POINTS = -0.7, 1, 10
-- Knife edge: right axis within ~25 degrees of vertical, over KNIFE_SPEED m/s level, the nose holding its heading
-- within ~30 degrees (in a banked turn it swings round), for KNIFE_TIME seconds or more, KNIFE_POINTS a second
local KNIFE_RY, KNIFE_SPEED, KNIFE_TIME, KNIFE_POINTS = 0.9, 10, 0.8, 15
-- Proximity: a surface (a building, not the ground: skimming that is easy) within PROXY_DIST metres while faster
-- than PROXY_SPEED m/s, for PROXY_TIME seconds or more, PROXY_POINTS a second
local PROXY_DIST, PROXY_SPEED, PROXY_TIME, PROXY_POINTS = 1.5, 8, 0.5, 20
-- cos^2 of 30 and 135 degrees, for direction checks on squared dot products
local COS2_30, COS2_135 = 0.75, 0.5
local COMBO_TIME = 3
local MULT_MAX = 5
local NOTE_TIME = 1.5

local through = Kit.through

local TIMES = { "", "DOUBLE ", "TRIPLE " }

local Tricks = {}
Tricks.__index = Tricks

-- map: its gaps (Kit.gap) and near(x, y, z, dist), both optional
function Tricks.new(map)
  local t = setmetatable({ gaps = map and map.gaps, near = map and map.near }, Tricks)
  t:reset()
  return t
end

function Tricks:reset()
  self.score = 0
  -- HUD strings, rebuilt only when they change: goal "PTS n" and note, the latest trick or banked combo
  self.goal = "PTS 0"
  self.note, self.noteTime = nil, 0
  self.mult, self.comboTime = 0, 0
  self.pitch, self.roll, self.inverted, self.settle = 0, 0, false, 0
  -- The turn's flight path: started, level velocity and height before it, top height, reversed at some point
  self.turning, self.svx, self.svz, self.sy, self.top, self.reversed = false, 0, 0, 0, 0, false
  self.diving, self.diveTop, self.diveSpeed, self.noseDown = false, 0, 0, false
  self.yaw, self.trippy = 0, true
  self.hang = 0
  self.knife, self.kfx, self.kfz = 0, 0, 0
  self.proxy = 0
  -- Position on the last frame, and the gap scored last: flown again in the same combo with nothing between, it
  -- scores nothing
  self.ox, self.oy, self.oz, self.lastGap = nil, nil, nil, nil
end

function Tricks:show(note)
  self.note, self.noteTime = note, NOTE_TIME
end

function Tricks:award(name, points)
  self.lastGap = nil
  if self.mult < MULT_MAX then
    self.mult = self.mult + 1
  end
  self.comboTime = COMBO_TIME
  points = points * self.mult
  self.score = self.score + points
  self.goal = format("PTS %d", self.score)
  if self.mult > 1 then
    self:show(format("%s +%d x%d", name, points, self.mult))
  else
    self:show(format("%s +%d", name, points))
  end
end

-- Ends the combo still running
function Tricks:drop()
  if self.mult > 1 then
    self:show("COMBO LOST")
  end
  self.mult = 0
end

local function turns(angle)
  return floor((abs(angle) + TURN_SLACK) / TURN)
end

local function named(n, trick)
  return (TIMES[n] or format("%dX ", n)) .. trick
end

-- The turn is over, upright again: flips, rolls, a power loop or a split-S
function Tricks:endTurn(q)
  local flips, rolls = turns(self.pitch), turns(self.roll)
  local n = flips + rolls
  local svx, svz = self.svx, self.svz
  local s2 = svx * svx + svz * svz
  local dot = q.vx * svx + q.vz * svz
  local fast = s2 >= LOOP_SPEED * LOOP_SPEED
  if flips == 1 and rolls == 0 and fast and self.reversed and dot > 0 and self.top - self.sy >= LOOP_RISE then
    self:award("POWER LOOP", LOOP_POINTS)
  elseif n > 0 then
    local name
    if flips > 0 and rolls > 0 then
      name = "FLIP+ROLL"
    elseif flips > 0 then
      name = named(n, self.pitch > 0 and "BACKFLIP" or "FRONTFLIP")
    else
      name = named(n, "ROLL")
    end
    self:award(name, TURN_POINTS * n * (n + 1) // 2)
  elseif
    fast
    and self.sy - q.py >= SPLIT_DROP
    and dot < 0
    and dot * dot >= COS2_135 * s2 * (q.vx * q.vx + q.vz * q.vz)
  then
    self:award("SPLIT-S", SPLIT_POINTS)
  end
end

-- Gaps flown through since the last frame; upside down they score double
function Tricks:gapsFlown(q)
  local ox, oy, oz = self.ox, self.oy, self.oz
  local px, py, pz = q.px, q.py, q.pz
  self.ox, self.oy, self.oz = px, py, pz
  if not ox then
    return
  end
  local gaps = self.gaps
  for i = 1, #gaps do
    local g = gaps[i]
    if g ~= self.lastGap and through(g, ox, oy, oz, px, py, pz) then
      if q.uy < INVERTED then
        self:award("INVERTED " .. g.name, 2 * g.points)
      else
        self:award(g.name, g.points)
      end
      self.lastGap = g
    end
  end
end

-- Once per frame of flight, after the physics
function Tricks:update(dt, q)
  local dPitch, dRoll, dYaw = q.turnPitch, q.turnRoll, q.turnYaw
  q.turnPitch, q.turnRoll, q.turnYaw = 0, 0, 0

  if q.strike > 0 or q.grounded then
    if q.strike > 0 then
      self:drop()
    end
    self.pitch, self.roll, self.inverted, self.turning = 0, 0, false, false
    self.diving = false
    self.yaw, self.trippy, self.hang, self.knife, self.proxy = 0, true, 0, 0, 0
    self.ox = nil
  else
    if self.gaps then
      self:gapsFlown(q)
    end
    self:flight(dt, q, dPitch, dRoll, dYaw)
  end

  if self.mult > 0 then
    self.comboTime = self.comboTime - dt
    if self.comboTime <= 0 then
      self.mult, self.lastGap = 0, nil
    end
  end
  if self.note then
    self.noteTime = self.noteTime - dt
    if self.noteTime <= 0 then
      self.note = nil
    end
  end
end

-- Off the ground and no prop strike
function Tricks:flight(dt, q, dPitch, dRoll, dYaw)
  local uy = q.uy
  if uy > UPRIGHT then
    if not self.inverted then
      self.pitch, self.roll, self.turning = 0, 0, false
      self.svx, self.svz, self.sy = q.vx, q.vz, q.py
    elseif self.settle < SETTLE then
      self.settle = self.settle + dt
      self.pitch, self.roll = self.pitch + dPitch, self.roll + dRoll
    else
      self:endTurn(q)
      self.pitch, self.roll, self.inverted, self.turning = 0, 0, false, false
    end
  else
    if not self.turning then
      self.turning, self.top, self.reversed = true, q.py, false
    end
    self.settle = 0
    self.pitch, self.roll = self.pitch + dPitch, self.roll + dRoll
    if uy < INVERTED then
      self.inverted = true
    end
  end
  if self.turning then
    if q.py > self.top then
      self.top = q.py
    end
    if q.vx * self.svx + q.vz * self.svz < 0 then
      self.reversed = true
    end
  end

  if dYaw > SPIN_RATE * dt or dYaw < -SPIN_RATE * dt then
    self.yaw = self.yaw + dYaw
    if q.throttle > TRIPPY_THROTTLE or q.vy > 0 then
      self.trippy = false
    end
  else
    local n = floor((abs(self.yaw) + SPIN_SLACK) / TURN)
    if n > 0 then
      local points = TURN_POINTS * n * (n + 1) // 2
      if self.trippy then
        self:award(named(n, "TRIPPY SPIN"), 2 * points)
      else
        self:award(named(n, "YAW SPIN"), points)
      end
    end
    self.yaw, self.trippy = 0, true
  end

  if uy < HANG_UY then
    self.hang = self.hang + dt
  else
    if self.hang >= HANG_TIME then
      self:award(format("HANG %.1fS", self.hang), floor(self.hang * HANG_POINTS))
    end
    self.hang = 0
  end

  local fx, fz = q.fx, q.fz
  local edge = (q.ry > KNIFE_RY or q.ry < -KNIFE_RY) and q.vx * q.vx + q.vz * q.vz > KNIFE_SPEED * KNIFE_SPEED
  if edge and self.knife > 0 then
    local kfx, kfz = self.kfx, self.kfz
    local dot = fx * kfx + fz * kfz
    edge = dot > 0 and dot * dot >= COS2_30 * (fx * fx + fz * fz) * (kfx * kfx + kfz * kfz)
  end
  if edge then
    if self.knife == 0 then
      self.kfx, self.kfz = fx, fz
    end
    self.knife = self.knife + dt
  else
    if self.knife >= KNIFE_TIME then
      self:award(format("KNIFE EDGE %.1fS", self.knife), floor(self.knife * KNIFE_POINTS))
    end
    self.knife = 0
  end

  local near = self.near
  if near then
    local vx, vy, vz = q.vx, q.vy, q.vz
    if vx * vx + vy * vy + vz * vz > PROXY_SPEED * PROXY_SPEED and near(q.px, q.py, q.pz, PROXY_DIST) then
      self.proxy = self.proxy + dt
    else
      if self.proxy >= PROXY_TIME then
        self:award(format("PROXIMITY %.1fS", self.proxy), floor(self.proxy * PROXY_POINTS))
      end
      self.proxy = 0
    end
  end

  if not self.diving then
    if q.vy < DIVE_START then
      self.diving, self.diveTop, self.diveSpeed, self.noseDown = true, q.py, 0, false
    end
  else
    if -q.vy > self.diveSpeed then
      self.diveSpeed = -q.vy
    end
    if q.fy < NOSE_DOWN then
      self.noseDown = true
    end
    if q.vy > DIVE_END then
      self.diving = false
      local drop = floor(self.diveTop - q.py)
      if drop >= DIVE_DROP and self.diveSpeed >= DIVE_SPEED and self.noseDown then
        self:award(format("DIVE %dM", drop), drop * DIVE_POINTS)
      end
    end
  end
end

return Tricks
