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
local CRASH_SPEED = 6
-- Body up-axis height (cos of tilt) below which a quad on the ground tips over: 60 degrees
local TIP_OVER = 0.5

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

-- Betaflight-style rate curve: centre sensitivity at the stick centre, max rate at full deflection
local function rateCurve(x, center, max)
  local a = abs(x)
  return x * (center + (max - center) * a * a)
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
  self.throttle = 0
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
end

-- Sticks: ail/ele/rud -1..1, thr 0..1. Returns true on a crash.
function Quad:step(dt, sticks, settings)
  local pitchRate, rollRate
  local yawRate = rateCurve(sticks.rud, settings.rateCenter, settings.rateMax)
  if settings.angleMode then
    pitchRate = (-sticks.ele * settings.maxAngle - self:pitchDeg()) * ANGLE_GAIN
    rollRate = (sticks.ail * settings.maxAngle - self:rollDeg()) * ANGLE_GAIN
  else
    pitchRate = -rateCurve(sticks.ele, settings.rateCenter, settings.rateMax)
    rollRate = rateCurve(sticks.ail, settings.rateCenter, settings.rateMax)
  end
  local thr = 0
  if not self.dead then
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

  if self.py < 0 then
    if v > CRASH_SPEED or (v > 2 and self.uy < 0.7) or self.uy < TIP_OVER then
      return true
    end
    self.py = 0
    if self.vy < 0 then
      self.vy = 0
    end
    local friction = 1 - 6 * dt
    if friction < 0 then
      friction = 0
    end
    self.vx = self.vx * friction
    self.vz = self.vz * friction
  end
end

return Quad
