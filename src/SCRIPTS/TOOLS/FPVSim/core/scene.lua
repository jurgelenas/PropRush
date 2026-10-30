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
-- Edge shades for custom objects drawn to match the boxes
Scene.EDGE, Scene.FAR_EDGE = BOX_EDGE, FAR_EDGE
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

-- b[1..6]: x0, y0, z0, x1, y1, z1
local function insideBox(b, x, y, z)
  return x > b[1] - RADIUS
    and x < b[4] + RADIUS
    and z > b[3] - RADIUS
    and z < b[6] + RADIUS
    and y > b[2] - RADIUS
    and y < b[5] + RADIUS
end

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

-- Insertion sort on distance ([11] dist), farthest first: the order barely changes between frames, and B&W radios have no
-- table lib
local function sortByDistance(list)
  for i = 2, #list do
    local b = list[i]
    local d = b[11]
    local j = i - 1
    while j > 0 and list[j][11] < d do
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
    -- dist from cx, cz
    local dx, dz = b[7] - ox, b[9] - oz
    b[11] = dx * dx + dz * dz
  end
  sortByDistance(parts)
  for i = 1, #parts do
    local b = parts[i]
    -- cx, cy, cz, rad
    if R.sphereVisible(b[7], b[8], b[9], b[10]) then
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
  if not insideBox(st, x, y, z) then
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
  if boxDistance2(st, x, y, z) >= d2 then
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

-- Structure: one building made of boxes, such as floors on columns or a wall with openings, sorted as a
-- whole against the rest of the scene. Its parts are grouped into levels by base height and drawn level
-- by level, so floors and the columns between them overlap correctly from inside and out. A part must
-- stay below the next level's base: columns are split at every floor. Its slots 1..10 are its bounds and sphere.
-- st:add(x, z, w, d, h, y0) takes a part as addBox does, standing at height y0.
local function addPart(st, x, z, w, d, h, y0)
  local b = newBox(x, z, w, d, h, y0)
  local parts, levels, bases = st.parts, st.levels, st.bases
  parts[#parts + 1] = b
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

  -- Bounds: x0, y0, z0 ([1..3]) the least of the parts', x1, y1, z1 ([4..6]) the greatest; then the sphere round
  -- them: cx, cy, cz ([7..9]) and rad ([10])
  for k = 1, 3 do
    if #parts == 1 or b[k] < st[k] then
      st[k] = b[k]
    end
    if #parts == 1 or b[k + 3] > st[k + 3] then
      st[k + 3] = b[k + 3]
    end
  end
  local bw, bh, bd = st[4] - st[1], st[5] - st[2], st[6] - st[3]
  st[7], st[8], st[9] = st[1] + bw / 2, st[2] + bh / 2, st[3] + bd / 2
  st[10] = math.sqrt(bw * bw + bh * bh + bd * bd) / 2
  return b
end

function Scene.newStructure()
  return {
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    levels = {},
    bases = {},
    parts = {},
    add = addPart,
    draw = drawStructure,
    collides = structureCollides,
    near = structureNear,
  }
end

-- Scene: objects drawn back to front, culled to the view, with collision.
-- Each object is laid out as a box (slots 1..11). Buildings are boxes; custom objects carry draw(obj, fogged) and
-- optionally collides(obj, x, y, z) instead, returning the box it hit, true for a hit with no box, or false,
-- and near(obj, x, y, z, d2), true when a surface is closer than the square root of d2.
function Scene.new()
  local objects = {}
  local frame = 0
  local scene = { objects = objects }

  -- Building standing on the ground: centre x, centre z, width (x), depth (z), height
  function scene.addBox(x, z, w, d, h)
    local b = newBox(x, z, w, d, h, 0)
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
      sortByDistance(objects)
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

-- The quad q has moved into box b from ox, oy, oz: it came through the top (a roof to land on) or the bottom if
-- it was above or below the box, else through the nearest side. Moves it back onto that face and hands the contact
-- to q:contact; returns true on a crash.
function Scene.collide(b, q, ox, oy, oz, dt)
  -- b[1..6]: x0, y0, z0, x1, y1, z1
  local y0, y1 = b[2] - RADIUS, b[5] + RADIUS
  if oy >= y1 then
    q.py = y1
    return q:contact(0, 1, 0, dt)
  elseif oy <= y0 then
    q.py = y0
    return q:contact(0, -1, 0, dt)
  end
  local x0, x1, z0, z1 = b[1] - RADIUS, b[4] + RADIUS, b[3] - RADIUS, b[6] + RADIUS
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

return Scene
