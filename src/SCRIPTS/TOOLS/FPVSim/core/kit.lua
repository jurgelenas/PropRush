-- Building blocks for maps: ground grid, horizon rings, scenes of buildings and custom objects, signal range.
-- Everything draws through the current camera (render3d).

local R = ...

local floor = math.floor

local Kit = {}

-- Ground grid: one spacing everywhere; solid near the camera, dotted further out
local GRID_STEP, NEAR_EXTENT = 30, 60
local FAR_EXTENT = { 270, 360, 450 }

-- Ground at distance d from height h sits focal * h / d below the horizon, so lines crossing the view there
-- are ~focal * h * step / d^2 apart. Beyond the distance where that drops under MIN_GAP_PX they only smudge.
local MIN_GAP_PX = 3

-- Distance where the grid ends for a quality level; horizon rings stand there so the grid runs right up to them
function Kit.horizon(quality)
  return FAR_EXTENT[quality]
end

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
    -- Trimmed to the circle of radius length, where the horizon stands
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

function Kit.drawGrid(quality)
  local ox, oy, oz = R.cameraPos()
  local far = FAR_EXTENT[quality]
  local useful = math.sqrt(R.focal() * oy * GRID_STEP / MIN_GAP_PX)
  -- At least the near extent, so the edge where lines enter stays well ahead even when skimming the ground
  if useful < NEAR_EXTENT then
    useful = NEAR_EXTENT
  elseif useful > far then
    useful = far
  end
  -- Only lines within the uncrowded range are placed, but each runs on to the horizon: the ones heading
  -- away from the view become a few rays converging on it instead of a dense fan
  drawFamily(true, ox, oz, useful, far)
  drawFamily(false, ox, oz, useful, far)
end

-- Horizon ring: a ridge and its base line around the camera. It follows the camera, so it is never reached.
-- Ring points this far behind the view direction are skipped (dot product).
local RING_CULL = -0.2

-- Ridge elevations in degrees, evenly spaced around the compass from north turning east, or at the given
-- azimuths in degrees (ascending, below 360): two points at one azimuth draw a vertical step, as in a skyline.
function Kit.newRing(elevations, azimuths)
  local n = #elevations
  local ring = { n = n, sin = {}, cos = {}, tan = {} }
  for i = 1, n do
    local a = azimuths and azimuths[i] * math.pi / 180 or (i - 1) * 2 * math.pi / n
    ring.sin[i], ring.cos[i], ring.tan[i] = math.sin(a), math.cos(a), math.tan(elevations[i] * math.pi / 180)
  end
  return ring
end

Kit.HILLS = Kit.newRing({ 1.5, 3, 2, 4.5, 3.5, 1, 2.5, 5, 3, 2, 1, 3.5, 6, 4, 2, 1.5, 3, 2, 4, 2.5, 1, 3, 4.5, 2 })

function Kit.drawRing(ring, dist)
  local ox, _, oz = R.cameraPos()
  local n, sins, coss, tans = ring.n, ring.sin, ring.cos, ring.tan
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
    local s, c = sins[k], coss[k]
    if s * fx + c * fz > RING_CULL then
      local x, z = ox + dist * s, oz + dist * c
      local cx, cy, cz = R.toCamera(x, 0, z)
      local ux, uy, uz = R.toCamera(x, dist * tans[k], z)
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

-- Full detail within DRAW_DIST, fogged out to OUTLINE_FACTOR times that: no pop-in
local DRAW_DIST = { 100, 150, 200 }
local OUTLINE_FACTOR = 3
-- Boxes: white faces, black outline and edges. One erase span per row; dither would cost two.
-- Distant boxes: light dither with a dotted outline, a fog that fades them in; they are small, so the
-- second call per row is cheap.
local BOX_SHADE, BOX_EDGE, FAR_SHADE, FAR_EDGE = 0, 4, 1, 2
local SORT_EVERY = 4

-- Scene: objects drawn back to front, culled to the view, with collision.
-- Each object has a bounding sphere cx, cy, cz, rad and dist, its squared ground distance from the camera.
-- Buildings are axis-aligned boxes x0, y0, z0, x1, y1, z1; custom objects carry draw(obj, fogged) and
-- optionally collides(obj, x, y, z) instead.
function Kit.newScene()
  local objects = {}
  local frame = 0
  local scene = { objects = objects }

  -- Building standing on the ground: centre x, centre z, width (x), depth (z), height
  function scene.addBox(x, z, w, d, h)
    local b = {
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
    objects[#objects + 1] = b
    return b
  end

  -- Custom object: needs cx, cy, cz, rad and draw(obj, fogged); fogged is set beyond the full-detail distance
  function scene.addObject(obj)
    obj.dist = 0
    objects[#objects + 1] = obj
    return obj
  end

  -- Insertion sort, farthest first: the order barely changes between frames, and B&W radios have no table lib.
  local function sortByDistance()
    for i = 2, #objects do
      local b = objects[i]
      local d = b.dist
      local j = i - 1
      while j > 0 and objects[j].dist < d do
        objects[j + 1] = objects[j]
        j = j - 1
      end
      objects[j + 1] = b
    end
  end

  function scene.draw(quality)
    local ox, _, oz = R.cameraPos()
    local maxDist = DRAW_DIST[quality]
    for i = 1, #objects do
      local b = objects[i]
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

    for i = 1, #objects do
      local b = objects[i]
      if b.dist < outlineDist and R.sphereVisible(b.cx, b.cy, b.cz, b.rad) then
        local draw = b.draw
        if draw then
          draw(b, b.dist >= maxDist)
        elseif b.dist < maxDist then
          R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, BOX_SHADE, BOX_EDGE)
        else
          R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, FAR_SHADE, FAR_EDGE)
        end
      end
    end
  end

  function scene.collides(x, y, z)
    for i = 1, #objects do
      local b = objects[i]
      if b.draw then
        if b.collides and b.collides(b, x, y, z) then
          return true
        end
      elseif x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 and y < b.y1 then
        return true
      end
    end
  end

  return scene
end

-- Video signal loss at a point: 0 clean within fade metres (3D) of the centre (cx, 0, cz), 1 lost at lost
function Kit.rangeLoss(x, y, z, cx, cz, fade, lost)
  local dx, dz = x - cx, z - cz
  local d = math.sqrt(dx * dx + y * y + dz * dz)
  if d <= fade then
    return 0
  elseif d >= lost then
    return 1
  end
  return (d - fade) / (lost - fade)
end

return Kit
