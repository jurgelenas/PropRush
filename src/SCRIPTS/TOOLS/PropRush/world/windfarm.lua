-- Wind farm kit: turbines with turning rotors, and lattice pylons with the lines between them, drawn
-- through the current camera (render3d). Only the wind farm map loads it.

local R, Scene = ...

local sqrt, sin, cos = math.sqrt, math.sin, math.cos
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_SHADE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_SHADE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15
-- Upright bars narrower than this on screen are their outline, as the scene's
local BAR_PX = 3

local Kit = {}

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }
local function setBox(x0, y0, z0, x1, y1, z1)
  BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] = x0, y0, z0, x1, y1, z1
  return BOX
end

-- Scene object slots [1..11] round x0, y0, z0 .. x1, y1, z1: bounds, then the sphere's centre and radius
local function bound(o, x0, y0, z0, x1, y1, z1)
  o[1], o[2], o[3], o[4], o[5], o[6] = x0, y0, z0, x1, y1, z1
  local w, h, d = x1 - x0, y1 - y0, z1 - z0
  o[7], o[8], o[9], o[10], o[11] = x0 + w / 2, y0 + h / 2, z0 + d / 2, sqrt(w * w + h * h + d * d) / 2, 0
end

-- Turbines face south, the rotor turning in the plane OVERHANG south of the tower. Arrays: [1..11] as a box's;
-- [12], [13] the tower's x, z; [14] hub height; [15] blade length; [16] the rotor's angle offset.
local OVERHANG, TOWER, NACELLE, HUB = 4, 0.8, 1.1, 0.7
-- Blades: ROOT_W half wide at ROOT out from the hub, narrowing to a point at the tip, BLADE_T half thick
local ROOT, ROOT_W, BLADE_T = 0.8, 0.45, 0.25
-- Rotor speed in rad/s, about 15 rpm
local SPIN, TURN, THIRD = 1.6, 2 * math.pi, 2 * math.pi / 3
local angle = 0

function Kit.turn(dt)
  angle = (angle + SPIN * dt) % TURN
end

-- Part k of turbine t into BOX: 1 tower, 2 nacelle, 3 hub
local function part(t, k)
  local x, z, h = t[12], t[13], t[14]
  if k == 1 then
    return setBox(x - TOWER, 0, z - TOWER, x + TOWER, h - NACELLE, z + TOWER)
  elseif k == 2 then
    return setBox(x - NACELLE, h - NACELLE, z - OVERHANG + BLADE_T, x + NACELLE, h + NACELLE, z + 2)
  end
  return setBox(x - HUB, h - HUB, z - OVERHANG - HUB, x + HUB, h + HUB, z - OVERHANG + BLADE_T)
end

local function drawPart(t, k, shade, edge)
  local b = part(t, k)
  R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
end

-- Blades as outlines, or fogged a line each, worked out in camera space from the hub along the rotor's plane
local function drawBlades(t, edge, fogged)
  local l = t[15]
  local hx, hy, hz = R.toCamera(t[12], t[14], t[13] - OVERHANG)
  local ax, ay, az = R.camVector(1, 0, 0)
  local bx, by, bz = R.camVector(0, 1, 0)
  for k = 0, 2 do
    local a = angle + t[16] + k * THIRD
    local c, s = cos(a), sin(a)
    -- Along the blade and across it
    local ux, uy, uz = ax * c + bx * s, ay * c + by * s, az * c + bz * s
    local vx, vy, vz = (bx * c - ax * s) * ROOT_W, (by * c - ay * s) * ROOT_W, (bz * c - az * s) * ROOT_W
    local tx, ty, tz = hx + ux * l, hy + uy * l, hz + uz * l
    local rx, ry, rz = hx + ux * ROOT, hy + uy * ROOT, hz + uz * ROOT
    if fogged then
      R.camLine(rx, ry, rz, tx, ty, tz, edge)
    else
      R.camLine(rx + vx, ry + vy, rz + vz, tx, ty, tz, edge)
      R.camLine(rx - vx, ry - vy, rz - vz, tx, ty, tz, edge)
      R.camLine(rx + vx, ry + vy, rz + vz, rx - vx, ry - vy, rz - vz, edge)
    end
  end
end

-- The rotor is in front of the nacelle from the south, behind it from the north; the nacelle sits on the tower
local function drawTurbine(t, fogged)
  local shade, edge = fogged and FAR_SHADE or SHADE, fogged and FAR_EDGE or EDGE
  local _, oy, oz = R.cameraPos()
  local front = oz < t[13] - OVERHANG
  if not front then
    drawPart(t, 3, shade, edge)
    drawBlades(t, edge, fogged)
  end
  local below = oy < t[14]
  if below then
    drawPart(t, 2, shade, edge)
  end
  if not R.bar(t[12], t[13], 0, t[14] - NACELLE, TOWER, BAR_PX, edge) then
    drawPart(t, 1, shade, edge)
  end
  if not below then
    drawPart(t, 2, shade, edge)
  end
  if front then
    drawBlades(t, edge, fogged)
    drawPart(t, 3, shade, edge)
  end
end

-- A blade is a crash, whichever way it meets the quad
local function turbineCollides(t, x, y, z)
  if not touches(t, x, y, z) then
    return false
  end
  for k = 1, 3 do
    local b = part(t, k)
    if touches(b, x, y, z) then
      return b
    end
  end
  local dz = z - t[13] + OVERHANG
  if dz > BLADE_T + RADIUS or dz < -BLADE_T - RADIUS then
    return false
  end
  local dx, dy, l = x - t[12], y - t[14], t[15]
  for k = 0, 2 do
    local a = angle + t[16] + k * THIRD
    local c, s = cos(a), sin(a)
    local along = dx * c + dy * s
    if along > ROOT - RADIUS and along < l + RADIUS then
      local across, w = dy * c - dx * s, ROOT_W * (l - along) / (l - ROOT) + RADIUS
      if across < w and across > -w then
        return true
      end
    end
  end
  return false
end

-- Near the tower, nacelle and hub, or the disc the blades sweep
local function turbineNear(t, x, y, z, d2)
  if distance2(t, x, y, z) >= d2 then
    return false
  end
  for k = 1, 3 do
    if distance2(part(t, k), x, y, z) < d2 then
      return true
    end
  end
  local dz = z - t[13] + OVERHANG
  dz = (dz < 0 and -dz or dz) - BLADE_T
  local dx, dy = x - t[12], y - t[14]
  local r = sqrt(dx * dx + dy * dy) - t[15]
  dz, r = dz > 0 and dz or 0, r > 0 and r or 0
  return dz * dz + r * r < d2
end

local TURBINE = { __index = { draw = drawTurbine, collides = turbineCollides, near = turbineNear } }

-- Turbine with its tower at x, z, the hub h up, blades l long, the rotor turned by phase (radians)
function Kit.addTurbine(scene, x, z, h, l, phase)
  local t = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, x, z, h, l, phase }, TURBINE)
  bound(t, x - l, 0, z - OVERHANG - HUB, x + l, h + l, z + 2)
  return scene.addObject(t)
end

-- Pylons: lattice towers for a line running along z, two conductors hanging from the arms across x and an earth wire
-- on the peak. Arrays: [1..11] as a box's; [12], [13] x, z. Legs taper from BASE_W (half) on the ground to WAIST_W at
-- the waist, clear between them to fly through, then braced up to the arms, ARMS_W at the arms' height.
local WAIST, ARMS, PEAK, ARM, DROP = 9, 15, 19, 6, 1.2
local BASE_W, WAIST_W, ARMS_W, LEG = 2, 1.2, 0.8, 0.1
-- Drawn thinner than they collide, so a near pylon stays a lattice of single lines
local DRAW_HALF = 0.04
Kit.ARM, Kit.HANG, Kit.PEAK = ARM, ARMS - DROP, PEAK

-- Joints from the base centre: corners round the base, the waist and the arms' level, then the peak, the arm tips
-- and the insulators' ends under them
local JX, JY, JZ = {}, {}, {}
local SX, SZ = { -1, 1, 1, -1 }, { -1, -1, 1, 1 }
for i = 1, 4 do
  JX[i], JY[i], JZ[i] = SX[i] * BASE_W, 0, SZ[i] * BASE_W
  JX[i + 4], JY[i + 4], JZ[i + 4] = SX[i] * WAIST_W, WAIST, SZ[i] * WAIST_W
  JX[i + 8], JY[i + 8], JZ[i + 8] = SX[i] * ARMS_W, ARMS, SZ[i] * ARMS_W
end
-- stylua: ignore
local TIPS = { 0, PEAK, 0, -ARM, ARMS, 0, ARM, ARMS, 0, -ARM, ARMS - DROP, 0, ARM, ARMS - DROP, 0 }
for i = 1, 5 do
  JX[12 + i], JY[12 + i], JZ[12 + i] = TIPS[3 * i - 2], TIPS[3 * i - 1], TIPS[3 * i]
end
-- Legs, rings, cross bracing, peak, arms, insulators
-- stylua: ignore
local BARS = {
  1, 5, 2, 6, 3, 7, 4, 8, 5, 9, 6, 10, 7, 11, 8, 12,
  5, 6, 6, 7, 7, 8, 8, 5, 9, 10, 10, 11, 11, 12, 12, 9,
  5, 10, 6, 9, 6, 11, 7, 10, 7, 12, 8, 11, 8, 9, 5, 12,
  9, 13, 10, 13, 11, 13, 12, 13,
  9, 14, 12, 14, 10, 15, 11, 15,
  14, 16, 15, 17,
}
-- The joints placed at a pylon
local PX, PY, PZ = {}, {}, {}

local function drawPylon(p, fogged)
  local x, z = p[12], p[13]
  for i = 1, #JX do
    PX[i], PY[i], PZ[i] = JX[i] + x, JY[i], JZ[i] + z
  end
  R.frame(PX, PY, PZ, BARS, DRAW_HALF, #BARS // 2, fogged and FAR_EDGE or EDGE)
end

-- Its half width at height y on the legs or the braced part
local function pylonHalf(y)
  if y < WAIST then
    return BASE_W + (WAIST_W - BASE_W) * y / WAIST
  end
  return WAIST_W + (ARMS_W - WAIST_W) * (y - WAIST) / (ARMS - WAIST)
end

-- The legs apart below the waist, the braced part and peak as solid, the arms as one bar across
local function pylonCollides(p, x, y, z)
  if not touches(p, x, y, z) then
    return false
  end
  local px, pz = p[12], p[13]
  local dx, dz = x - px, z - pz
  local ax, az = dx < 0 and -dx or dx, dz < 0 and -dz or dz
  if y > ARMS - LEG - RADIUS and y < ARMS + LEG + RADIUS and az < ARMS_W + RADIUS then
    return setBox(px - ARM, ARMS - LEG, pz - ARMS_W, px + ARM, ARMS + LEG, pz + ARMS_W)
  elseif y < WAIST then
    local w = pylonHalf(y)
    local reach = LEG + RADIUS
    if ax > w - reach and ax < w + reach and az > w - reach and az < w + reach then
      local lx, lz = dx < 0 and px - w or px + w, dz < 0 and pz - w or pz + w
      return setBox(lx - LEG, y - 1, lz - LEG, lx + LEG, y + 1, lz + LEG)
    end
  elseif y < ARMS then
    local w = pylonHalf(y)
    if ax < w + RADIUS and az < w + RADIUS then
      return setBox(px - w, WAIST, pz - w, px + w, ARMS, pz + w)
    end
  else
    local w = ARMS_W * (PEAK - y) / (PEAK - ARMS)
    if ax < w + RADIUS and az < w + RADIUS then
      return setBox(px - w, ARMS, pz - w, px + w, PEAK, pz + w)
    end
  end
  return false
end

local function pylonNear(p, x, y, z, d2)
  if distance2(p, x, y, z) >= d2 then
    return false
  end
  local px, pz = p[12], p[13]
  return distance2(setBox(px - BASE_W, 0, pz - BASE_W, px + BASE_W, PEAK, pz + BASE_W), x, y, z) < d2
    or distance2(setBox(px - ARM, ARMS - LEG, pz - LEG, px + ARM, ARMS + LEG, pz + LEG), x, y, z) < d2
end

local PYLON = { __index = { draw = drawPylon, collides = pylonCollides, near = pylonNear } }

function Kit.addPylon(scene, x, z)
  local p = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, x, z }, PYLON)
  bound(p, x - ARM, 0, z - BASE_W, x + ARM, PEAK, z + BASE_W)
  return scene.addObject(p)
end

-- Spans: the line between two supports along z, drawn only. Arrays: [1..11] as a box's; [12], [13], [14] x, z and
-- the conductors' height at one end, [15..17] at the other; [18] true for an earth wire between pylons' peaks.
-- Conductors sag SAG in the middle, the earth wire half as much.
local SAG = 3

local function drawSpan(s, fogged)
  local edge = fogged and FAR_EDGE or EDGE
  local ax, az, ay, bx, bz, by = s[12], s[13], s[14], s[15], s[16], s[17]
  local mx, mz = (ax + bx) / 2, (az + bz) / 2
  local my = (ay + by) / 2 - SAG
  for u = -ARM, ARM, 2 * ARM do
    R.line(ax + u, ay, az, mx + u, my, mz, edge)
    R.line(mx + u, my, mz, bx + u, by, bz, edge)
  end
  if s[18] and not fogged then
    R.line(ax, PEAK, az, mx, PEAK - SAG / 2, mz, edge)
    R.line(mx, PEAK - SAG / 2, mz, bx, PEAK, bz, edge)
  end
end

local SPAN = { __index = { draw = drawSpan } }

function Kit.addSpan(scene, ax, az, ay, bx, bz, by, earth)
  local s = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ax, az, ay, bx, bz, by, earth }, SPAN)
  local x0, z0, x1, z1 = math.min(ax, bx) - ARM, math.min(az, bz), math.max(ax, bx) + ARM, math.max(az, bz)
  bound(s, x0, math.min(ay, by) - SAG, z0, x1, earth and PEAK or math.max(ay, by), z1)
  return scene.addObject(s)
end

return Kit
