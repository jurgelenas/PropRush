-- Scenes of buildings and custom objects: drawn back to front through the current camera (render3d), with
-- collision and proximity.

local R = ...

local Scene = {}

-- Full detail within DRAW_DIST, fogged out to OUTLINE_FACTOR times that: no pop-in
local DRAW_DIST = { 100, 150, 200 }
local OUTLINE_FACTOR = 3
-- Boxes: white faces, black outline and edges. One erase span per row; dither would cost two.
-- Distant boxes: light dither with a dotted outline, a fog that fades them in; they are small, so the
-- second call per row is cheap.
local BOX_SHADE, BOX_EDGE, FAR_SHADE, FAR_EDGE = 0, 4, 1, 2
-- Shades for custom objects drawn to match the boxes
Scene.SHADE, Scene.EDGE, Scene.FAR_SHADE, Scene.FAR_EDGE = BOX_SHADE, BOX_EDGE, FAR_SHADE, FAR_EDGE
local SORT_EVERY = 4
-- Upright bars (columns, posts: at least twice as tall as wide) narrower than this on screen are drawn as their
-- outline instead of a box: the same picture, as the fill between the sides is a pixel at most, so nothing behind
-- shows through
local BAR_PX = 3

-- Boxes are arrays, as a table of named fields costs over twice the memory on the radio:
-- [1..6] x0, y0, z0, x1, y1, z1; [7..9] the centre of the bounding sphere the scene culls and sorts with, [10] its
-- radius; [11] squared ground distance from the camera; [12] half width when it is an upright bar, else false.
-- Every scene object carries slots 1..11 (a custom object its bounds and sphere).

-- Axis-aligned box from its base: centre x, centre z, width (x), depth (z), height, base height y0
local function newBox(x, z, w, d, h, y0)
  local wide = w > d and w or d
  return {
    x - w / 2, -- [1] x0
    y0, -- [2] y0
    z - d / 2, -- [3] z0
    x + w / 2, -- [4] x1
    y0 + h, -- [5] y1
    z + d / 2, -- [6] z1
    x, -- [7] cx
    y0 + h / 2, -- [8] cy
    z, -- [9] cz
    math.sqrt(w * w + h * h + d * d) / 2, -- [10] rad
    0, -- [11] dist
    h >= 2 * wide and wide / 2, -- [12] bar
  }
end

-- b[12] bar; b[7], b[9] cx, cz; b[1..6] x0, y0, z0, x1, y1, z1
local function drawBox(b, fogged)
  local bar = b[12]
  if bar and R.bar(b[7], b[9], b[2], b[5], bar, BAR_PX, fogged and FAR_EDGE or BOX_EDGE) then
    return
  end
  if fogged then
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], FAR_SHADE, FAR_EDGE)
  else
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], BOX_SHADE, BOX_EDGE)
  end
end

-- Quad radius: boxes collide this far out from their faces, so the camera stays clear of them
local RADIUS = 0.15

-- Squared distance from x, y, z to box b, 0 inside it; b[1..6]: x0, y0, z0, x1, y1, z1
local function boxDistance2(b, x, y, z)
  local d, t = 0, 0
  if x < b[1] then
    t = b[1] - x
  elseif x > b[4] then
    t = x - b[4]
  end
  d = t * t
  t = 0
  if y < b[2] then
    t = b[2] - y
  elseif y > b[5] then
    t = y - b[5]
  end
  d = d + t * t
  t = 0
  if z < b[3] then
    t = b[3] - z
  elseif z > b[6] then
    t = z - b[6]
  end
  return d + t * t
end

-- The quad at x, y, z within RADIUS of box b: the box grown by RADIUS with rounded edges and corners, so clipping
-- one hits it at an angle; b[1..6]: x0, y0, z0, x1, y1, z1
local function touches(b, x, y, z)
  return x > b[1] - RADIUS
    and x < b[4] + RADIUS
    and z > b[3] - RADIUS
    and z < b[6] + RADIUS
    and y > b[2] - RADIUS
    and y < b[5] + RADIUS
    and boxDistance2(b, x, y, z) < RADIUS * RADIUS
end

Scene.touches, Scene.distance2 = touches, boxDistance2

-- list[i..j] by dist ([11]), farthest first
local function sortRange(list, i, j)
  for k = i + 1, j do
    local b = list[k]
    local d = b[11]
    local m = k - 1
    while m >= i and list[m][11] < d do
      list[m + 1] = list[m]
      m = m - 1
    end
    list[m + 1] = b
  end
end

-- Structure: one building made of boxes, such as floors on columns or a wall with openings, sorted as a
-- whole against the rest of the scene. Its parts are grouped into levels by base height and drawn level
-- by level, so floors and the columns between them overlap correctly from inside and out. A part must
-- stay below the next level's base: columns are split at every floor.
-- Slots 1..11 are its bounds, sphere and dist as a box's; its parts follow from PARTS on in base height order,
-- so a level is a run of them. st:add(x, z, w, d, h, y0) takes a part as addBox does, standing at height y0.
local PARTS = 12

-- Parts st[i..j], one level, drawn far to near
local function drawLevel(st, i, j, ox, oz, fogged)
  for k = i, j do
    local b = st[k]
    -- dist from cx, cz
    local dx, dz = b[7] - ox, b[9] - oz
    b[11] = dx * dx + dz * dz
  end
  sortRange(st, i, j)
  for k = i, j do
    local b = st[k]
    -- cx, cy, cz, rad
    if R.sphereVisible(b[7], b[8], b[9], b[10]) then
      drawBox(b, fogged)
    end
  end
end

-- Levels away from the camera's one go first, from the far end inwards, and the camera's own level last.
-- Levels never overlap in height, so a sight line crosses them in that order. Parts' [2] is y0.
local function drawStructure(st, fogged)
  local ox, oy, oz = R.cameraPos()
  local n = #st
  -- The camera's level c0..c1: the highest at or below it, else the lowest
  local c0, c1 = PARTS, PARTS
  local i = PARTS
  while i <= n do
    local base, j = st[i][2], i
    while j < n and st[j + 1][2] == base do
      j = j + 1
    end
    if base > oy and i > PARTS then
      break
    end
    c0, c1, i = i, j, j + 1
  end
  local j = n
  while j > c1 do
    local k = j
    while k > c1 + 1 and st[k - 1][2] == st[j][2] do
      k = k - 1
    end
    drawLevel(st, k, j, ox, oz, fogged)
    j = k - 1
  end
  i = PARTS
  while i < c0 do
    local k = i
    while k < c0 - 1 and st[k + 1][2] == st[i][2] do
      k = k + 1
    end
    drawLevel(st, i, k, ox, oz, fogged)
    i = k + 1
  end
  drawLevel(st, c0, c1, ox, oz, fogged)
end

local function structureCollides(st, x, y, z)
  if not touches(st, x, y, z) then
    return false
  end
  for i = PARTS, #st do
    local b = st[i]
    if touches(b, x, y, z) then
      return b
    end
  end
  return false
end

local function structureNear(st, x, y, z, d2)
  if boxDistance2(st, x, y, z) >= d2 then
    return false
  end
  for i = PARTS, #st do
    if boxDistance2(st[i], x, y, z) < d2 then
      return true
    end
  end
  return false
end

-- Inserted after the parts at or below its base
local function addPart(st, x, z, w, d, h, y0)
  local b = newBox(x, z, w, d, h, y0)
  local i = #st
  -- y0
  while i >= PARTS and st[i][2] > y0 do
    st[i + 1] = st[i]
    i = i - 1
  end
  st[i + 1] = b

  -- Bounds: x0, y0, z0 ([1..3]) the least of the parts', x1, y1, z1 ([4..6]) the greatest; then the sphere round
  -- them: cx, cy, cz ([7..9]) and rad ([10])
  local first = #st == PARTS
  for k = 1, 3 do
    if first or b[k] < st[k] then
      st[k] = b[k]
    end
    if first or b[k + 3] > st[k + 3] then
      st[k + 3] = b[k + 3]
    end
  end
  local bw, bh, bd = st[4] - st[1], st[5] - st[2], st[6] - st[3]
  st[7], st[8], st[9] = st[1] + bw / 2, st[2] + bh / 2, st[3] + bd / 2
  st[10] = math.sqrt(bw * bw + bh * bh + bd * bd) / 2
  return b
end

local STRUCTURE =
  { __index = { add = addPart, draw = drawStructure, collides = structureCollides, near = structureNear } }

function Scene.newStructure()
  return setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, STRUCTURE)
end

-- Scene: objects drawn back to front, culled to the view, with collision.
-- Each object is laid out as a box (slots 1..11). Buildings are boxes; custom objects carry draw(obj, fogged) and
-- optionally collides(obj, x, y, z) instead, returning the box it hit, true for a hit with no box, or false,
-- and near(obj, x, y, z, d2), true when a surface is closer than the square root of d2.
function Scene.new()
  local objects = {}
  local frame = 0
  local scene = { objects = objects }

  -- Building: centre x, centre z, width (x), depth (z), height, standing on the ground or at y0
  function scene.addBox(x, z, w, d, h, y0)
    local b = newBox(x, z, w, d, h, y0 or 0)
    objects[#objects + 1] = b
    return b
  end

  -- Custom object: needs its bounds and sphere in slots 1..10 and draw(obj, fogged); fogged is set beyond the
  -- full-detail distance
  function scene.addObject(obj)
    -- dist
    obj[11] = 0
    objects[#objects + 1] = obj
    return obj
  end

  -- Structure (see Scene.newStructure)
  function scene.addStructure()
    return scene.addObject(Scene.newStructure())
  end

  function scene.draw(quality)
    local ox, _, oz = R.cameraPos()
    local maxDist = DRAW_DIST[quality]
    for i = 1, #objects do
      local b = objects[i]
      -- dist from cx, cz
      local dx = b[7] - ox
      local dz = b[9] - oz
      b[11] = dx * dx + dz * dz
    end
    frame = frame + 1
    if frame % SORT_EVERY == 0 then
      -- Insertion sort: the order barely changes between frames, and B&W radios have no table lib
      sortRange(objects, 1, #objects)
    end
    local outlineDist = maxDist * OUTLINE_FACTOR
    outlineDist = outlineDist * outlineDist
    maxDist = maxDist * maxDist

    for i = 1, #objects do
      local b = objects[i]
      -- dist; cx, cy, cz, rad
      local dist = b[11]
      if dist < outlineDist and R.sphereVisible(b[7], b[8], b[9], b[10]) then
        local draw = b.draw
        if draw then
          draw(b, dist >= maxDist)
        else
          drawBox(b, dist >= maxDist)
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
      elseif touches(b, x, y, z) then
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

-- The quad q has moved into box b from ox, oy, oz. The surface normal points from the closest point on the box to
-- where the quad first touched it: a face head-on, slanting round an edge or corner it clipped. Moves it back out
-- along the normal to RADIUS from that point and hands the contact to q:contact; returns true on a crash.
function Scene.collide(b, q, ox, oy, oz, dt)
  local x, y, z = ox, oy, oz
  local r2 = RADIUS * RADIUS
  if boxDistance2(b, ox, oy, oz) >= r2 then
    -- Where it first touched, between where it came from (t0 = 0) and where it is (t1 = 1), to 1/16 of the step:
    -- under 2 cm at 30 m/s, so never inside the box
    local dx, dy, dz = q.px - ox, q.py - oy, q.pz - oz
    local t0, t1 = 0, 1
    for _ = 1, 4 do
      local t = (t0 + t1) / 2
      if boxDistance2(b, ox + dx * t, oy + dy * t, oz + dz * t) < r2 then
        t1 = t
      else
        t0 = t
      end
    end
    x, y, z = ox + dx * t1, oy + dy * t1, oz + dz * t1
  end
  -- Closest point cx, cy, cz; b[1..6]: x0, y0, z0, x1, y1, z1
  local cx, cy, cz = x, y, z
  if x < b[1] then
    cx = b[1]
  elseif x > b[4] then
    cx = b[4]
  end
  if y < b[2] then
    cy = b[2]
  elseif y > b[5] then
    cy = b[5]
  end
  if z < b[3] then
    cz = b[3]
  elseif z > b[6] then
    cz = b[6]
  end
  local nx, ny, nz = x - cx, y - cy, z - cz
  local d = math.sqrt(nx * nx + ny * ny + nz * nz)
  if d < 1e-6 then
    -- Was inside the box already: out the top
    nx, ny, nz, d = 0, 1, 0, 1
  end
  nx, ny, nz = nx / d, ny / d, nz / d
  local push = RADIUS - ((q.px - cx) * nx + (q.py - cy) * ny + (q.pz - cz) * nz)
  if push > 0 then
    q.px, q.py, q.pz = q.px + nx * push, q.py + ny * push, q.pz + nz * push
  end
  return q:contact(nx, ny, nz, dt)
end

return Scene
