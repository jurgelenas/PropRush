local R = ...

local floor = math.floor

-- Far enough that the line projects onto the true horizon
local HORIZON_DIST = 2000
-- One grid spacing; solid near the camera, dotted further out so distant lines stay light.
local GRID_STEP, NEAR_EXTENT = 30, 60

-- Indexed by quality: 1 LOW, 2 MED, 3 HIGH
local FAR_EXTENT = { 120, 150, 180 }
-- Full detail within DRAW_DIST, fogged out to OUTLINE_FACTOR times that: no pop-in
local DRAW_DIST = { 100, 150, 200 }
local OUTLINE_FACTOR = 3

local World = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

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

-- Lines every step metres within extent of the camera, stepped in camera space.
-- xx..zz: camera-space images of the world X and Z unit vectors.
local function drawGrid(ox, oz, step, extent, shade, xx, xy, xz, zx, zy, zz)
  local x0 = floor((ox - extent) / step) * step
  local z0 = floor((oz - extent) / step) * step
  local span = 2 * extent
  local count = floor(span / step)
  local sx, sy, sz = xx * step, xy * step, xz * step
  local tx, ty, tz = zx * step, zy * step, zz * step
  local ax, ay, az = R.toCamera(x0, 0, z0)
  local lx, ly, lz = zx * span, zy * span, zz * span
  local px, py, pz = ax, ay, az
  for _ = 0, count do
    R.camLine(px, py, pz, px + lx, py + ly, pz + lz, shade)
    px, py, pz = px + sx, py + sy, pz + sz
  end
  lx, ly, lz = xx * span, xy * span, xz * span
  px, py, pz = ax, ay, az
  for _ = 0, count do
    R.camLine(px, py, pz, px + lx, py + ly, pz + lz, shade)
    px, py, pz = px + tx, py + ty, pz + tz
  end
end

local function drawGround(ox, oz, quality)
  -- Third and sixth values are the camera forward's world x and z
  local xx, xy, xz, zx, zy, zz = R.groundAxes()

  -- Horizon: a line through two far ground points either side of the view direction
  local len = math.sqrt(xz * xz + zz * zz)
  if len > 0.01 then
    local hx, hz = xz / len * HORIZON_DIST, zz / len * HORIZON_DIST
    local ax, ay, az = R.toCamera(ox + hx - hz, 0, oz + hz + hx)
    local bx, by, bz = R.toCamera(ox + hx + hz, 0, oz + hz - hx)
    R.camLine(ax, ay, az, bx, by, bz, 4)
  end

  drawGrid(ox, oz, GRID_STEP, NEAR_EXTENT, 4, xx, xy, xz, zx, zy, zz)
  drawGrid(ox, oz, GRID_STEP, FAR_EXTENT[quality], 2, xx, xy, xz, zx, zy, zz)
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

function World.collides(x, y, z)
  for i = 1, #boxes do
    local b = boxes[i]
    if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 and y < b.y1 then
      return true
    end
  end
end

return World
