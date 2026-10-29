-- Building blocks for maps: ground grid, horizon rings, scenes of buildings and custom objects, signal range.
-- Everything draws through the current camera (render3d).

local R = ...

local floor = math.floor

local Kit = {}

-- Ground grid: one spacing everywhere (GRID_STEP unless the map picks its own); solid near the camera, dotted
-- further out
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
function Kit.drawGrid(quality, step)
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

function Kit.drawRing(ring, dist)
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

-- Full detail within DRAW_DIST, fogged out to OUTLINE_FACTOR times that: no pop-in
local DRAW_DIST = { 100, 150, 200 }
local OUTLINE_FACTOR = 3
-- Boxes: white faces, black outline and edges. One erase span per row; dither would cost two.
-- Distant boxes: light dither with a dotted outline, a fog that fades them in; they are small, so the
-- second call per row is cheap.
local BOX_SHADE, BOX_EDGE, FAR_SHADE, FAR_EDGE = 0, 4, 1, 2
local SORT_EVERY = 4
-- Upright bars (columns, posts: at least twice as tall as wide) narrower than this on screen are drawn as their
-- outline instead of a box: the same picture, as the fill between the sides is a pixel at most, so nothing behind
-- shows through
local BAR_PX = 3

-- Axis-aligned box from its base: centre x, centre z, width (x), depth (z), height, base height y0.
-- Carries the bounding sphere the scene culls and sorts with, and bar, its half width when it is an upright bar.
local function newBox(x, z, w, d, h, y0)
  local wide = w > d and w or d
  return {
    x0 = x - w / 2,
    y0 = y0,
    z0 = z - d / 2,
    x1 = x + w / 2,
    y1 = y0 + h,
    z1 = z + d / 2,
    cx = x,
    cy = y0 + h / 2,
    cz = z,
    rad = math.sqrt(w * w + h * h + d * d) / 2,
    dist = 0,
    bar = h >= 2 * wide and wide / 2,
  }
end

local function drawBox(b, fogged)
  local bar = b.bar
  if bar and R.bar(b.cx, b.cz, b.y0, b.y1, bar, BAR_PX, fogged and FAR_EDGE or BOX_EDGE) then
    return
  end
  if fogged then
    R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, FAR_SHADE, FAR_EDGE)
  else
    R.box(b.x0, b.y0, b.z0, b.x1, b.y1, b.z1, BOX_SHADE, BOX_EDGE)
  end
end

-- Quad radius: boxes collide this far out from their faces, so the camera stays clear of them
local RADIUS = 0.15

local function insideBox(b, x, y, z)
  return x > b.x0 - RADIUS
    and x < b.x1 + RADIUS
    and z > b.z0 - RADIUS
    and z < b.z1 + RADIUS
    and y > b.y0 - RADIUS
    and y < b.y1 + RADIUS
end

-- Squared distance from x, y, z to box b, 0 inside it
local function boxDistance2(b, x, y, z)
  local d, t = 0, 0
  if x < b.x0 then
    t = b.x0 - x
  elseif x > b.x1 then
    t = x - b.x1
  end
  d = t * t
  t = 0
  if y < b.y0 then
    t = b.y0 - y
  elseif y > b.y1 then
    t = y - b.y1
  end
  d = d + t * t
  t = 0
  if z < b.z0 then
    t = b.z0 - z
  elseif z > b.z1 then
    t = z - b.z1
  end
  return d + t * t
end

-- Insertion sort on dist, farthest first: the order barely changes between frames, and B&W radios have no
-- table lib
local function sortByDistance(list)
  for i = 2, #list do
    local b = list[i]
    local d = b.dist
    local j = i - 1
    while j > 0 and list[j].dist < d do
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = b
  end
end

-- Structure parts on one level, drawn far to near
local function drawLevel(parts, ox, oz, fogged)
  for i = 1, #parts do
    local b = parts[i]
    local dx, dz = b.cx - ox, b.cz - oz
    b.dist = dx * dx + dz * dz
  end
  sortByDistance(parts)
  for i = 1, #parts do
    local b = parts[i]
    if R.sphereVisible(b.cx, b.cy, b.cz, b.rad) then
      drawBox(b, fogged)
    end
  end
end

-- Levels away from the camera's one go first, from the far end inwards, and the camera's own level last.
-- Levels never overlap in height, so a sight line crosses them in that order.
local function drawStructure(st, fogged)
  local ox, oy, oz = R.cameraPos()
  local levels, bases = st.levels, st.bases
  local n = #levels
  local c = 1
  while c < n and bases[c + 1] <= oy do
    c = c + 1
  end
  for i = n, c + 1, -1 do
    drawLevel(levels[i], ox, oz, fogged)
  end
  for i = 1, c - 1 do
    drawLevel(levels[i], ox, oz, fogged)
  end
  drawLevel(levels[c], ox, oz, fogged)
end

local function structureCollides(st, x, y, z)
  if not insideBox(st.bounds, x, y, z) then
    return false
  end
  local parts = st.parts
  for i = 1, #parts do
    local b = parts[i]
    if insideBox(b, x, y, z) then
      return b
    end
  end
  return false
end

local function structureNear(st, x, y, z, d2)
  if boxDistance2(st.bounds, x, y, z) >= d2 then
    return false
  end
  local parts = st.parts
  for i = 1, #parts do
    if boxDistance2(parts[i], x, y, z) < d2 then
      return true
    end
  end
  return false
end

-- Scene: objects drawn back to front, culled to the view, with collision.
-- Each object has a bounding sphere cx, cy, cz, rad and dist, its squared ground distance from the camera.
-- Buildings are axis-aligned boxes x0, y0, z0, x1, y1, z1; custom objects carry draw(obj, fogged) and
-- optionally collides(obj, x, y, z) instead, returning the box it hit, true for a hit with no box, or false,
-- and near(obj, x, y, z, d2), true when a surface is closer than the square root of d2.
function Kit.newScene()
  local objects = {}
  local frame = 0
  local scene = { objects = objects }

  -- Building standing on the ground: centre x, centre z, width (x), depth (z), height
  function scene.addBox(x, z, w, d, h)
    local b = newBox(x, z, w, d, h, 0)
    objects[#objects + 1] = b
    return b
  end

  -- Custom object: needs cx, cy, cz, rad and draw(obj, fogged); fogged is set beyond the full-detail distance
  function scene.addObject(obj)
    obj.dist = 0
    objects[#objects + 1] = obj
    return obj
  end

  -- Structure: one building made of boxes, such as floors on columns or a wall with openings, sorted as a
  -- whole against the rest of the scene. Its parts are grouped into levels by base height and drawn level
  -- by level, so floors and the columns between them overlap correctly from inside and out. A part must
  -- stay below the next level's base: columns are split at every floor.
  -- add(x, z, w, d, h, y0) takes a part as addBox does, standing at height y0.
  function scene.addStructure()
    local bounds = newBox(0, 0, 0, 0, 0, 0)
    local st =
      { levels = {}, bases = {}, parts = {}, bounds = bounds, draw = drawStructure, collides = structureCollides }
    st.near = structureNear
    local first = true

    function st.add(x, z, w, d, h, y0)
      local b = newBox(x, z, w, d, h, y0)
      st.parts[#st.parts + 1] = b
      local levels, bases = st.levels, st.bases
      local i = 1
      while bases[i] and bases[i] < y0 do
        i = i + 1
      end
      if bases[i] ~= y0 then
        for j = #bases, i, -1 do
          bases[j + 1], levels[j + 1] = bases[j], levels[j]
        end
        bases[i], levels[i] = y0, {}
      end
      local level = levels[i]
      level[#level + 1] = b

      if first then
        bounds.x0, bounds.y0, bounds.z0, bounds.x1, bounds.y1, bounds.z1 = b.x0, b.y0, b.z0, b.x1, b.y1, b.z1
        first = false
      else
        bounds.x0, bounds.y0, bounds.z0 =
          math.min(bounds.x0, b.x0), math.min(bounds.y0, b.y0), math.min(bounds.z0, b.z0)
        bounds.x1, bounds.y1, bounds.z1 =
          math.max(bounds.x1, b.x1), math.max(bounds.y1, b.y1), math.max(bounds.z1, b.z1)
      end
      local bw, bh, bd = bounds.x1 - bounds.x0, bounds.y1 - bounds.y0, bounds.z1 - bounds.z0
      st.cx, st.cy, st.cz = bounds.x0 + bw / 2, bounds.y0 + bh / 2, bounds.z0 + bd / 2
      st.rad = math.sqrt(bw * bw + bh * bh + bd * bd) / 2
      return b
    end

    return scene.addObject(st)
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
      sortByDistance(objects)
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
        else
          drawBox(b, b.dist >= maxDist)
        end
      end
    end
  end

  -- The box at x, y, z, true for a custom object hit with no box, or nil
  function scene.collides(x, y, z)
    for i = 1, #objects do
      local b = objects[i]
      if b.draw then
        local hit = b.collides and b.collides(b, x, y, z)
        if hit then
          return hit
        end
      elseif insideBox(b, x, y, z) then
        return b
      end
    end
  end

  -- True when a surface is within dist of x, y, z
  function scene.near(x, y, z, dist)
    local d2 = dist * dist
    for i = 1, #objects do
      local b = objects[i]
      if b.draw then
        if b.near and b.near(b, x, y, z, d2) then
          return true
        end
      elseif boxDistance2(b, x, y, z) < d2 then
        return true
      end
    end
    return false
  end

  return scene
end

-- Gap for freestyle scoring: a flat rectangle x0, y0, z0 .. x1, y1, z1, flat along one axis (x0 == x1: a
-- window in a wall along z; y0 == y1: a hole in a roof), worth points flown through.
function Kit.gap(name, points, x0, y0, z0, x1, y1, z1)
  local g = { name = name, points = points }
  if x0 == x1 then
    g.axis, g.at, g.u0, g.u1, g.v0, g.v1 = 1, x0, y0, y1, z0, z1
  elseif y0 == y1 then
    g.axis, g.at, g.u0, g.u1, g.v0, g.v1 = 2, y0, x0, x1, z0, z1
  else
    assert(z0 == z1, "gap is not flat")
    g.axis, g.at, g.u0, g.u1, g.v0, g.v1 = 3, z0, x0, x1, y0, y1
  end
  return g
end

-- The quad q has moved into box b from ox, oy, oz: it came through the top (a roof to land on) or the bottom if
-- it was above or below the box, else through the nearest side. Moves it back onto that face and hands the contact
-- to q:contact; returns true on a crash.
function Kit.collide(b, q, ox, oy, oz, dt)
  local y0, y1 = b.y0 - RADIUS, b.y1 + RADIUS
  if oy >= y1 then
    q.py = y1
    return q:contact(0, 1, 0, dt)
  elseif oy <= y0 then
    q.py = y0
    return q:contact(0, -1, 0, dt)
  end
  local x0, x1, z0, z1 = b.x0 - RADIUS, b.x1 + RADIUS, b.z0 - RADIUS, b.z1 + RADIUS
  -- The side it came from, so a fast quad deep into a thin wall is not pushed out the far side; the nearest one
  -- when it came from a corner or was already inside
  local outX = ox <= x0 or ox >= x1
  local outZ = oz <= z0 or oz >= z1
  local x, z = q.px, q.pz
  if outX and not outZ then
    x, z = ox, (z0 + z1) / 2
  elseif outZ and not outX then
    x, z = (x0 + x1) / 2, oz
  end
  local t, side = x - x0, 1
  if x1 - x < t then
    t, side = x1 - x, 2
  end
  if z - z0 < t then
    t, side = z - z0, 3
  end
  if z1 - z < t then
    side = 4
  end
  if side == 1 then
    q.px = x0
    return q:contact(-1, 0, 0, dt)
  elseif side == 2 then
    q.px = x1
    return q:contact(1, 0, 0, dt)
  elseif side == 3 then
    q.pz = z0
    return q:contact(0, 0, -1, dt)
  end
  q.pz = z1
  return q:contact(0, 0, 1, dt)
end

-- Launch pad on the ground: a square with a cross, centred on x, z
local PAD = 1.5

function Kit.drawPad(x, z)
  local x0, z0, x1, z1 = x - PAD, z - PAD, x + PAD, z + PAD
  R.line(x0, 0, z0, x1, 0, z0, 4)
  R.line(x1, 0, z0, x1, 0, z1, 4)
  R.line(x1, 0, z1, x0, 0, z1, 4)
  R.line(x0, 0, z1, x0, 0, z0, 4)
  R.line(x0, 0, z0, x1, 0, z1, 4)
  R.line(x1, 0, z0, x0, 0, z1, 4)
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
