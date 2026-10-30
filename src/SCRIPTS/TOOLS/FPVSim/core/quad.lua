-- stickRate: core/rates
local stickRate = ...

-- World axes: x east, y up, z north. Body axes r/u/f (right, up, forward) are unit vectors in world space.

local sin, cos, sqrt, abs, asin, atan = math.sin, math.cos, math.sqrt, math.abs, math.asin, math.atan

local G = 9.81
local RAD = math.pi / 180
local TWR = 4.5
-- Quadratic drag: terminal speed at full throttle ~33 m/s (120 km/h)
local DRAG = 0.04
local ANGLE_GAIN = 8
-- Full-throttle battery life in seconds
local BATTERY_LIFE = 150
-- LiPo cell: resting voltage at 0 %, 10 % .. 100 % charge
local CELL_CURVE = { [0] = 3.0, 3.61, 3.69, 3.71, 3.73, 3.77, 3.79, 3.84, 3.92, 4.03, 4.2 }
local CELL_FULL = 4.2
-- Loaded cell voltage at which the flight controller browns out and the motors stop for good
local CELL_CUTOFF = 3.1
-- Voltage sag at full throttle on a full pack, growing by SAG_EMPTY as it drains; settles at SAG_RATE per second
local SAG_FULL, SAG_EMPTY, SAG_RATE = 0.15, 0.2, 8
-- Contacts, by speed into the surface (m/s), for a 5" quad whose props pass a blade ~700 times a second at hover,
-- so each pass bites about speed / 700 deep. From STRIKE_SPEED (under 1 mm a pass) an edge-on hit strikes the
-- props. A crash is a hit over the limit edge-on (the props take it) or flat on (the frame does), blended by tilt;
-- soft ground (grass) gives way, so it takes more. The limits are set for play, about twice what breaks a real
-- prop or arm: most hits are a prop strike to fly out of, only big ones end the run. From BOUNCE_SPEED hits bounce
-- back with BOUNCE of that speed.
local STRIKE_SPEED = 0.5
local CRASH_EDGE, CRASH_FLAT = 10, 14
local SOFT_EDGE, SOFT_FLAT = 14, 20
local BOUNCE_SPEED, BOUNCE = 1, 0.2
-- Prop strike: tumble rate per m/s of edge-on impact (rad/s) and its cap, seconds of strike per m/s and their cap;
-- while it lasts the flight controller has lost its hold and the props give STRIKE_THRUST of their thrust
local TUMBLE_GAIN, TUMBLE_MAX = 2, 15
local STRIKE_TIME, STRIKE_MAX = 0.05, 0.6
local STRIKE_THRUST = 0.3
local TUMBLE_DAMP = 1.5
-- Surfaces with a normal this close to up are floors the quad can rest and slide on
local FLOOR = 0.7
-- Body up-axis height (cos of tilt) below which a quad resting on a floor has tipped over: 60 degrees
local TIP_OVER = 0.5
local REST_SPEED = 2
-- Arming waits for the throttle under this
local ARM_THROTTLE = 0.05

local Quad = {}
Quad.__index = Quad

local function clamp1(x)
  if x > 1 then
    return 1
  elseif x < -1 then
    return -1
  end
  return x
end

function Quad.new()
  local q = setmetatable({}, Quad)
  q:reset(0, 0, 0, 0)
  return q
end

function Quad:reset(x, y, z, headingDeg)
  self.px, self.py, self.pz = x, y, z
  self.vx, self.vy, self.vz = 0, 0, 0
  local s, c = sin(headingDeg * RAD), cos(headingDeg * RAD)
  self.rx, self.ry, self.rz = c, 0, -s
  self.ux, self.uy, self.uz = 0, 1, 0
  self.fx, self.fy, self.fz = s, 0, c
  self.battery = 1
  self.sag = 0
  self.voltage = CELL_FULL
  self.dead = false
  -- Disarmed, and the arm source must be seen off before it arms
  self.armed, self.armReady = false, false
  self.throttle = 0
  -- Prop strike seconds left and the tumble, in world rad/s
  self.strike = 0
  self.wx, self.wy, self.wz = 0, 0, 0
  self.grounded = false
  -- Pitch, roll and yaw turned (radians, body axes) since freestyle scoring last read them
  self.turnPitch, self.turnRoll, self.turnYaw = 0, 0, 0
  -- Hardest contact and prop strike (speed into the surface, edge-on share) since the sound last read them
  self.hit, self.struck = 0, 0
end

function Quad:speed()
  return sqrt(self.vx * self.vx + self.vy * self.vy + self.vz * self.vz)
end

function Quad:pitchDeg()
  return asin(clamp1(self.fy)) / RAD
end

function Quad:rollDeg()
  return atan(-self.ry, self.uy) / RAD
end

-- Rotate the body by small angles (radians) about its own axes.
function Quad:rotate(pitchUp, yawRight, rollRight)
  local rx, ry, rz = self.rx, self.ry, self.rz
  local ux, uy, uz = self.ux, self.uy, self.uz
  local fx, fy, fz = self.fx, self.fy, self.fz
  local s, c

  s, c = sin(pitchUp), cos(pitchUp)
  ux, uy, uz, fx, fy, fz =
    ux * c - fx * s, uy * c - fy * s, uz * c - fz * s, fx * c + ux * s, fy * c + uy * s, fz * c + uz * s

  s, c = sin(yawRight), cos(yawRight)
  fx, fy, fz, rx, ry, rz =
    fx * c + rx * s, fy * c + ry * s, fz * c + rz * s, rx * c - fx * s, ry * c - fy * s, rz * c - fz * s

  s, c = sin(rollRight), cos(rollRight)
  rx, ry, rz, ux, uy, uz =
    rx * c - ux * s, ry * c - uy * s, rz * c - uz * s, ux * c + rx * s, uy * c + ry * s, uz * c + rz * s

  -- Re-orthonormalise: f, then r = u x f, then u = f x r
  local n = 1 / sqrt(fx * fx + fy * fy + fz * fz)
  fx, fy, fz = fx * n, fy * n, fz * n
  rx, ry, rz = uy * fz - uz * fy, uz * fx - ux * fz, ux * fy - uy * fx
  n = 1 / sqrt(rx * rx + ry * ry + rz * rz)
  rx, ry, rz = rx * n, ry * n, rz * n
  ux, uy, uz = fy * rz - fz * ry, fz * rx - fx * rz, fx * ry - fy * rx

  self.rx, self.ry, self.rz = rx, ry, rz
  self.ux, self.uy, self.uz = ux, uy, uz
  self.fx, self.fy, self.fz = fx, fy, fz
  self.turnPitch, self.turnRoll, self.turnYaw =
    self.turnPitch + pitchUp, self.turnRoll + rollRight, self.turnYaw + yawRight
end

-- The flight controller's arming, once a frame. on: the arm source is on, nil for none (armed on throttle low).
-- Returns "armed" or "disarmed" when it changes, "throttle" while arming waits for the throttle low.
function Quad:arm(on, thr)
  if on == nil then
    on, self.armReady = true, true
  end
  if not on then
    self.armReady = true
    if self.armed then
      self.armed = false
      return "disarmed"
    end
  elseif not self.armed and self.armReady then
    if thr >= ARM_THROTTLE then
      return "throttle"
    end
    self.armed = true
    return "armed"
  end
end

-- Sticks: ail/ele/rud -1..1, thr 0..1. Disarmed or with the battery dead the motors are off and the flight
-- controller holds nothing. Returns true on a crash.
function Quad:step(dt, sticks, settings)
  local pitchRate, rollRate
  local s = settings
  local yawRate = stickRate(sticks.rud, s.yawRcRate, s.yawRate, s.yawExpo)
  if s.angleMode then
    pitchRate = (-sticks.ele * settings.maxAngle - self:pitchDeg()) * ANGLE_GAIN
    rollRate = (sticks.ail * settings.maxAngle - self:rollDeg()) * ANGLE_GAIN
  else
    pitchRate = -stickRate(sticks.ele, s.pitchRcRate, s.pitchRate, s.pitchExpo)
    rollRate = stickRate(sticks.ail, s.rollRcRate, s.rollRate, s.rollExpo)
  end
  local thr = 0
  local motors = self.armed and not self.dead
  if self.strike > 0 then
    self.strike = self.strike - dt
    local wx, wy, wz = self.wx, self.wy, self.wz
    self:rotate(
      -(wx * self.rx + wy * self.ry + wz * self.rz) * dt,
      (wx * self.ux + wy * self.uy + wz * self.uz) * dt,
      -(wx * self.fx + wy * self.fy + wz * self.fz) * dt
    )
    local k = 1 - TUMBLE_DAMP * dt
    self.wx, self.wy, self.wz = wx * k, wy * k, wz * k
    if motors then
      thr = sticks.thr * STRIKE_THRUST
    end
  elseif motors then
    self:rotate(pitchRate * RAD * dt, yawRate * RAD * dt, rollRate * RAD * dt)
    thr = sticks.thr
  end
  self.throttle = thr
  -- Motor rpm follows voltage, thrust follows rpm squared
  local vr = self.voltage / CELL_FULL
  local acc = thr * TWR * G * vr * vr
  local v = self:speed()
  local drag = DRAG * v
  self.vx = self.vx + (self.ux * acc - self.vx * drag) * dt
  self.vy = self.vy + (self.uy * acc - G - self.vy * drag) * dt
  self.vz = self.vz + (self.uz * acc - self.vz * drag) * dt
  self.px = self.px + self.vx * dt
  self.py = self.py + self.vy * dt
  self.pz = self.pz + self.vz * dt

  -- Battery simulation off: the pack stays full
  if settings.batterySim then
    self.battery = self.battery - dt * (0.1 + 0.9 * thr * sqrt(thr)) / BATTERY_LIFE
    if self.battery < 0 then
      self.battery = 0
    end
    local k = self.battery * 10
    local i = k // 1
    local rest = i >= 10 and CELL_FULL or CELL_CURVE[i] + (CELL_CURVE[i + 1] - CELL_CURVE[i]) * (k - i)
    -- Current, and so sag, grows with throttle^1.5 like the drain
    local sag = thr * sqrt(thr) * (SAG_FULL + SAG_EMPTY * (1 - self.battery))
    local f = SAG_RATE * dt
    self.sag = self.sag + (sag - self.sag) * (f > 1 and 1 or f)
    self.voltage = rest - self.sag
    if self.voltage < CELL_CUTOFF then
      self.dead = true
    end
  end

  self.grounded = false
  if self.py < 0 then
    self.py = 0
    return self:contact(0, 1, 0, dt, true)
  end
end

-- Touching a surface with outward unit normal n, the quad already moved back onto it; soft: the ground. Speed into
-- it is stopped (bounced back from BOUNCE_SPEED) and friction slows the slide along it. An edge-on hit from
-- STRIKE_SPEED strikes the props and tumbles the quad about the touching rim. Returns true on a crash.
function Quad:contact(nx, ny, nz, dt, soft)
  local vn = -(self.vx * nx + self.vy * ny + self.vz * nz)
  local floor = ny > FLOOR
  if floor then
    self.grounded = true
  end
  if vn > 0 then
    -- Up-axis share along the normal: 1 flat on (the frame takes it), 0 edge-on (the props do)
    local d = nx * self.ux + ny * self.uy + nz * self.uz
    local edge = 1 - d * d
    if edge < 0 then
      edge = 0
    end
    local flat, limit = CRASH_FLAT, CRASH_EDGE
    if soft then
      flat, limit = SOFT_FLAT, SOFT_EDGE
    end
    if vn > flat + (limit - flat) * edge then
      return true
    end
    if vn > self.hit then
      self.hit = vn
    end
    local k = vn * (vn > BOUNCE_SPEED and 1 + BOUNCE or 1)
    self.vx, self.vy, self.vz = self.vx + k * nx, self.vy + k * ny, self.vz + k * nz
    local vs = vn * sqrt(edge)
    if vs > STRIKE_SPEED then
      -- Tumble about u x n, away from the surface; flat-on hits have u x n near zero but no strike either
      local ax, ay, az = self.uy * nz - self.uz * ny, self.uz * nx - self.ux * nz, self.ux * ny - self.uy * nx
      local n = sqrt(ax * ax + ay * ay + az * az)
      if n > 1e-3 then
        local w = TUMBLE_GAIN * vs
        w = (w > TUMBLE_MAX and TUMBLE_MAX or w) / n
        if d < 0 then
          w = -w
        end
        self.wx, self.wy, self.wz = ax * w, ay * w, az * w
        if vs > self.struck then
          self.struck = vs
        end
        local t = STRIKE_TIME * vs
        self.strike = t > STRIKE_MAX and STRIKE_MAX or t
      end
    end
  end
  if floor then
    if self.uy < TIP_OVER and self:speed() < REST_SPEED then
      return true
    end
    local friction = 1 - 6 * dt
    if friction < 0 then
      friction = 0
    end
    self.vx = self.vx * friction
    self.vz = self.vz * friction
  else
    -- Walls and ceilings: the slide along them slows
    local friction = 1 - 3 * dt
    self.vx, self.vy, self.vz = self.vx * friction, self.vy * friction, self.vz * friction
  end
end

return Quad
