local R = ...

local floor = math.floor

-- Ground grid: one spacing everywhere; solid near the camera, dotted further out
local GRID_STEP, NEAR_EXTENT = 30, 60
local FAR_EXTENT = { 270, 360, 450 }

-- Hills ringing the ground at the far grid extent, so the grid runs right up to the visible horizon.
-- Elevation of the ridge in degrees per azimuth step; the ring follows the camera, so it is never reached.
local HILLS = { 1.5, 3, 2, 4.5, 3.5, 1, 2.5, 5, 3, 2, 1, 3.5, 6, 4, 2, 1.5, 3, 2, 4, 2.5, 1, 3, 4.5, 2 }
local HILL_SIN, HILL_COS, HILL_TAN = {}, {}, {}
local HILL_CULL = -0.2
for i = 1, #HILLS do
  local a = (i - 1) * 2 * math.pi / #HILLS
  HILL_SIN[i], HILL_COS[i], HILL_TAN[i] = math.sin(a), math.cos(a), math.tan(HILLS[i] * math.pi / 180)
end
-- Full detail within DRAW_DIST, fogged out to OUTLINE_FACTOR times that: no pop-in
local DRAW_DIST = { 100, 150, 200 }
local OUTLINE_FACTOR = 3

local World = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

-- Video link: clean within FADE of the map centre, fully lost at LOST (3D distance from the centre on the ground)
local RANGE_X, RANGE_Z, RANGE_FADE, RANGE_LOST = 0, 60, 150, 400

-- Axis-aligned boxes: x0, y0, z0, x1, y1, z1
local boxes = {}

local function addBox(x, z, w, d, h)
  boxes[#boxes + 1] = {
    x0 = x - w / 2,
    y0 = 0,
    z0 = z - d / 2,
    x1 = x + w / 2,
    y1 = h,
    z1 = z + d / 2,
    cx = x,
    cy = h / 2,
    cz = z,
    rad = math.sqrt(w * w + h * h + d * d) / 2,
    dist = 0,
  }
end

for i = 0, 7 do
  local a = i * math.pi / 4
  addBox(math.sin(a) * 30, math.cos(a) * 30 + 60, 2, 2, 8 + (i % 3) * 4)
end
addBox(-25, 110, 16, 10, 14)
addBox(30, 120, 10, 18, 22)

-- Boxes: white faces, black outline and edges. One erase span per row; dither would cost two.
-- Distant boxes: light dither with a dotted outline, a fog that fades them in; they are small, so the
-- second call per row is cheap.
local BOX_SHADE, BOX_EDGE, FAR_SHADE, FAR_EDGE = 0, 4, 1, 2

-- Ground at distance d from height h sits focal * h / d below the horizon, so lines crossing the view there
-- are ~focal * h * step / d^2 apart. Beyond the distance where that drops under MIN_GAP_PX they only smudge.
local MIN_GAP_PX = 3

-- One family of parallel grid lines. alongZ: lines of constant x running along z.
-- reach: how far from the camera lines are placed; length: radius of the circle they are trimmed to.
-- Line centres and directions are stepped in camera space instead of transforming every endpoint.
local function drawFamily(alongZ, ox, oz, reach, length)
  local o = alongZ and ox or oz
  local p = floor((o - reach) / GRID_STEP) * GRID_STEP
  -- Camera-space images of the step between lines and of the line direction (unit vectors)
  local sx, sy, sz, dx, dy, dz
  local cx, cy, cz
  if alongZ then
    sx, sy, sz = R.camVector(GRID_STEP, 0, 0)
    dx, dy, dz = R.camVector(0, 0, 1)
    cx, cy, cz = R.toCamera(p, 0, oz)
  else
    sx, sy, sz = R.camVector(0, 0, GRID_STEP)
    dx, dy, dz = R.camVector(1, 0, 0)
    cx, cy, cz = R.toCamera(ox, 0, p)
  end
  local last = o + reach
  local l2 = length * length
  while p <= last do
    local d = p - o
    local ad = d < 0 and -d or d
    -- Solid near the camera; dotted further out and on the outermost row, so lines entering at the edge fade in
    local shade = (ad <= NEAR_EXTENT and ad <= reach - GRID_STEP) and 4 or 2
    -- Trimmed to the circle of radius length, where the hills stand
    local half = l2 - d * d
    if half > 0 then
      half = math.sqrt(half)
      local hx, hy, hz = dx * half, dy * half, dz * half
      R.camLine(cx - hx, cy - hy, cz - hz, cx + hx, cy + hy, cz + hz, shade)
    end
    cx, cy, cz = cx + sx, cy + sy, cz + sz
    p = p + GRID_STEP
  end
end

local function drawHills(ox, oz, dist)
  local n = #HILLS
  -- Ring points more than ~100 degrees from the view direction can never be on screen
  local fx, _, fz = R.forward()
  local len = math.sqrt(fx * fx + fz * fz)
  if len < 0.01 then
    fx, fz, len = 0, 1, 1
  end
  fx, fz = fx / len, fz / len
  local prev
  local bx, by, bz, tx, ty, tz
  for i = 0, n do
    local k = i == 0 and n or i
    local s, c = HILL_SIN[k], HILL_COS[k]
    if s * fx + c * fz > HILL_CULL then
      local x, z = ox + dist * s, oz + dist * c
      local cx, cy, cz = R.toCamera(x, 0, z)
      local ux, uy, uz = R.toCamera(x, dist * HILL_TAN[k], z)
      if prev then
        R.camLine(bx, by, bz, cx, cy, cz, 4)
        R.camLine(tx, ty, tz, ux, uy, uz, 4)
      end
      bx, by, bz, tx, ty, tz = cx, cy, cz, ux, uy, uz
      prev = true
    else
      prev = nil
    end
  end
end

local function drawGround(ox, oz, quality)
  local _, oy = R.cameraPos()
  local far = FAR_EXTENT[quality]
  local useful = math.sqrt(R.focal() * oy * GRID_STEP / MIN_GAP_PX)
  -- At least the near extent, so the edge where lines enter stays well ahead even when skimming the ground
  if useful < NEAR_EXTENT then
    useful = NEAR_EXTENT
  elseif useful > far then
    useful = far
  end
  -- Only lines within the uncrowded range are placed, but each runs on to the hills: the ones heading
  -- away from the view become a few rays converging on the horizon instead of a dense fan
  drawFamily(true, ox, oz, useful, far)
  drawFamily(false, ox, oz, useful, far)
  drawHills(ox, oz, far)
end

-- Insertion sort, farthest first: the order barely changes between frames, and B&W radios have no table lib.
local function sortByDistance()
  for i = 2, #boxes do
    local b = boxes[i]
    local d = b.dist
    local j = i - 1
    while j > 0 and boxes[j].dist < d do
      boxes[j + 1] = boxes[j]
      j = j - 1
    end
    boxes[j + 1] = b
  end
end

function World.draw(quality)
  World.drawGround(quality)
  World.drawBoxes(quality)
end

function World.drawGround(quality)
  local ox, _, oz = R.cameraPos()
  drawGround(ox, oz, quality)
end

local SORT_EVERY = 4
local frame = 0

function World.drawBoxes(quality)
  local ox, _, oz = R.cameraPos()
  local maxDist = DRAW_DIST[quality]
  for i = 1, #boxes do
    local b = boxes[i]
    local dx = b.cx - ox
    local dz = b.cz - oz
    b.dist = dx * dx + dz * dz
  end
  frame = frame + 1
  if frame % SORT_EVERY == 0 then
    sortByDistance()
  end
  local outlineDist = maxDist * OUTLINE_FACTOR
  outlineDist = outlineDist * outlineDist
  maxDist = maxDist * maxDist

  for i = 1, #boxes do
    local b = boxes[i]
    if b.dist < outlineDist and R.sphereVisible(b.cx, b.cy, b.cz, b.rad) then
      if b.dist < maxDist then
        R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, BOX_SHADE, BOX_EDGE)
      else
        R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, FAR_SHADE, FAR_EDGE)
      end
    end
  end
end

-- Video signal loss at a point: 0 clean .. 1 lost
function World.signalLoss(x, y, z)
  local dx, dz = x - RANGE_X, z - RANGE_Z
  local d = math.sqrt(dx * dx + y * y + dz * dz)
  if d <= RANGE_FADE then
    return 0
  elseif d >= RANGE_LOST then
    return 1
  end
  return (d - RANGE_FADE) / (RANGE_LOST - RANGE_FADE)
end

function World.collides(x, y, z)
  for i = 1, #boxes do
    local b = boxes[i]
    if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 and y < b.y1 then
      return true
    end
  end
end

return World
