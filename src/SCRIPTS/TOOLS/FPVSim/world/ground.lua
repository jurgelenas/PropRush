-- The world around a map's scene: ground grid, horizon rings, the launch pad and the video signal range.
-- Everything draws through the current camera (render3d).

local R = ...

local floor = math.floor

local Ground = {}

-- Ground grid: one spacing everywhere (GRID_STEP unless the map picks its own); solid near the camera, dotted
-- further out
local GRID_STEP, NEAR_EXTENT = 30, 60
local FAR_EXTENT = { 270, 360, 450 }

-- Ground at distance d from height h sits focal * h / d below the horizon, so lines crossing the view there
-- are ~focal * h * step / d^2 apart. Beyond the distance where that drops under MIN_GAP_PX they only smudge.
local MIN_GAP_PX = 3

-- Distance where the grid ends for a quality level; horizon rings stand there so the grid runs right up to them
function Ground.horizon(quality)
  return FAR_EXTENT[quality]
end

-- One family of parallel grid lines. alongZ: lines of constant x running along z.
-- reach: how far from the camera lines are placed; length: radius of the circle they are trimmed to.
-- Line centres and directions are stepped in camera space instead of transforming every endpoint.
local function drawFamily(alongZ, ox, oz, reach, length, step)
  local o = alongZ and ox or oz
  local p = floor((o - reach) / step) * step
  -- Camera-space images of the step between lines and of the line direction (unit vectors)
  local sx, sy, sz, dx, dy, dz
  local cx, cy, cz
  if alongZ then
    sx, sy, sz = R.camVector(step, 0, 0)
    dx, dy, dz = R.camVector(0, 0, 1)
    cx, cy, cz = R.toCamera(p, 0, oz)
  else
    sx, sy, sz = R.camVector(0, 0, step)
    dx, dy, dz = R.camVector(1, 0, 0)
    cx, cy, cz = R.toCamera(ox, 0, p)
  end
  local last = o + reach
  local l2 = length * length
  while p <= last do
    local d = p - o
    local ad = d < 0 and -d or d
    -- Solid near the camera; dotted further out and on the outermost row, so lines entering at the edge fade in
    local shade = (ad <= NEAR_EXTENT and ad <= reach - step) and 4 or 2
    -- Trimmed to the circle of radius length, where the horizon stands
    local half = l2 - d * d
    if half > 0 then
      half = math.sqrt(half)
      local hx, hy, hz = dx * half, dy * half, dz * half
      R.camLine(cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz, shade)
    end
    cx, cy, cz = cx + sx, cy + sy, cz + sz
    p = p + step
  end
end

-- step: line spacing in metres, GRID_STEP by default
function Ground.drawGrid(quality, step)
  step = step or GRID_STEP
  local ox, oy, oz = R.cameraPos()
  local far = FAR_EXTENT[quality]
  local useful = math.sqrt(R.focal() * oy * step / MIN_GAP_PX)
  -- At least the near extent, so the edge where lines enter stays well ahead even when skimming the ground
  if useful < NEAR_EXTENT then
    useful = NEAR_EXTENT
  elseif useful > far then
    useful = far
  end
  -- Only lines within the uncrowded range are placed, but each runs on to the horizon: the ones heading
  -- away from the view become a few rays converging on it instead of a dense fan
  drawFamily(true, ox, oz, useful, far, step)
  drawFamily(false, ox, oz, useful, far, step)
end

-- Horizon ring: a ridge and its base line around the camera. It follows the camera, so it is never reached.
-- Ring points further off the view direction than the screen corners plus RING_MARGIN are skipped: ring points
-- are at most ~20 degrees apart, so a segment reaching into view is kept.
local RING_MARGIN = 22 * math.pi / 180

-- The base is a circle on the ground, nearly straight on screen, so it is drawn as a coarse polygon of its own
-- instead of through every ridge point: 20 degree chords sag under a third of a pixel
local BASE_N = 18
local BASE = { n = BASE_N, sin = {}, cos = {} }
for i = 1, BASE_N do
  local a = (i - 1) * 2 * math.pi / BASE_N
  BASE.sin[i], BASE.cos[i] = math.sin(a), math.cos(a)
end

-- Ridge elevations in degrees, evenly spaced around the compass from north turning east, or at the given
-- azimuths in degrees (ascending, below 360): two points at one azimuth draw a vertical step, as in a skyline.
function Ground.newRing(elevations, azimuths)
  local n = #elevations
  local ring = { n = n, sin = {}, cos = {}, tan = {} }
  for i = 1, n do
    local a = azimuths and azimuths[i] * math.pi / 180 or (i - 1) * 2 * math.pi / n
    ring.sin[i], ring.cos[i], ring.tan[i] = math.sin(a), math.cos(a), math.tan(elevations[i] * math.pi / 180)
  end
  return ring
end

Ground.HILLS =
  Ground.newRing({ 1.5, 3, 2, 4.5, 3.5, 1, 2.5, 5, 3, 2, 1, 3.5, 6, 4, 2, 1.5, 3, 2, 4, 2.5, 1, 3, 4.5, 2 })

-- Closed loop of ring points at distance dist from the camera, at their elevations (tans) or on the ground
local function drawLoop(loop, tans, dist, ox, oz, fx, fz, cull)
  local n, sins, coss = loop.n, loop.sin, loop.cos
  local prev, px, py, pz
  for i = 0, n do
    local k = i == 0 and n or i
    local s, c = sins[k], coss[k]
    if s * fx + c * fz > cull then
      local x, y, z = R.toCamera(ox + dist * s, tans and dist * tans[k] or 0, oz + dist * c)
      if prev then
        R.camLine(px, py, pz, x, y, z, 4)
      end
      px, py, pz, prev = x, y, z, true
    else
      prev = nil
    end
  end
end

function Ground.drawRing(ring, dist)
  local ox, _, oz = R.cameraPos()
  local fx, _, fz = R.forward()
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then
    fx, fz, len = 0, 1, 1
  end
  fx, fz = fx / len, fz / len
  local reach = R.cornerAngle() + RING_MARGIN
  local cull = reach < math.pi and math.cos(reach) or -1
  drawLoop(BASE, nil, dist, ox, oz, fx, fz, cull)
  drawLoop(ring, ring.tan, dist, ox, oz, fx, fz, cull)
end

-- Launch pad on the ground: a square with a cross, centred on x, z
local PAD = 1.5

function Ground.drawPad(x, z)
  local x0, z0, x1, z1 = x - PAD, z - PAD, x + PAD, z + PAD
  R.line(x0, 0, z0, x1, 0, z0, 4)
  R.line(x1, 0, z0, x1, 0, z1, 4)
  R.line(x1, 0, z1, x0, 0, z1, 4)
  R.line(x0, 0, z1, x0, 0, z0, 4)
  R.line(x0, 0, z0, x1, 0, z1, 4)
  R.line(x1, 0, z0, x0, 0, z1, 4)
end

-- Video signal loss at a point: 0 clean within fade metres (3D) of the centre (cx, 0, cz), 1 lost at lost
function Ground.rangeLoss(x, y, z, cx, cz, fade, lost)
  local dx, dz = x - cx, z - cz
  local d = math.sqrt(dx * dx + y * y + dz * dz)
  if d <= fade then
    return 0
  elseif d >= lost then
    return 1
  end
  return (d - fade) / (lost - fade)
end

return Ground
