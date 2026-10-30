-- Race kit: gates, ladders, side-by-side gates, cubes and flags, with their openings (world/gap). Only racing maps
-- load it.

local R, Scene, Gap = ...

local Course = {}

-- Race kit pieces are frames of square bars between joints (R.frame), colliding as one box per bar. Gate bars are
-- BAR thick.
local BAR = 0.3
local HALF = BAR / 2

-- Frames are arrays, as named fields cost a 16-node hash each on the radio: [1..11] as a scene object's bounds,
-- sphere and dist; [12] the bars' half thickness; [13..15] joint x, y, z lists; [16] bars as joint index pairs;
-- [17] how many bars are drawn, the rest only collide. Their methods come from a shared metatable.
local touches, distance2 = Scene.touches, Scene.distance2

local function drawFrame(f, fogged)
  if fogged then
    R.frame(f[13], f[14], f[15], f[16], f[12], f[17], Scene.FAR_EDGE)
  else
    R.frame(f[13], f[14], f[15], f[16], f[12], f[17], Scene.EDGE, 0)
  end
end

-- Bar i's box into BOX: its joints' bounds grown by the half thickness
local BOX = {}
local function barBox(f, i)
  local jx, jy, jz, bars, h = f[13], f[14], f[15], f[16], f[12]
  local a, b = bars[2 * i - 1], bars[2 * i]
  local ax, ay, az, bx, by, bz = jx[a], jy[a], jz[a], jx[b], jy[b], jz[b]
  BOX[1], BOX[4] = (ax < bx and ax or bx) - h, (ax < bx and bx or ax) + h
  BOX[2], BOX[5] = (ay < by and ay or by) - h, (ay < by and by or ay) + h
  BOX[3], BOX[6] = (az < bz and az or bz) - h, (az < bz and bz or az) + h
  return BOX
end

-- The bar's box at x, y, z, valid until the next call, or false
local function frameCollides(f, x, y, z)
  if not touches(f, x, y, z) then
    return false
  end
  for i = 1, #f[16] // 2 do
    if touches(barBox(f, i), x, y, z) then
      return BOX
    end
  end
  return false
end

local function frameNear(f, x, y, z, d2)
  if distance2(f, x, y, z) >= d2 then
    return false
  end
  for i = 1, #f[16] // 2 do
    if distance2(barBox(f, i), x, y, z) < d2 then
      return true
    end
  end
  return false
end

local FRAME = { __index = { draw = drawFrame, collides = frameCollides, near = frameNear } }

-- Joint at x, y, z, shared with an earlier one there: its index
local function joint(f, x, y, z)
  local jx, jy, jz = f[13], f[14], f[15]
  local n = #jx
  for i = 1, n do
    if jx[i] == x and jy[i] == y and jz[i] == z then
      return i
    end
  end
  jx[n + 1], jy[n + 1], jz[n + 1] = x, y, z
  return n + 1
end

-- Bar from x0, y0, z0 to x1, y1, z1; drawn unless hidden. Grows the frame's bounds ([1..6]) and sphere ([7..10]).
local function link(f, x0, y0, z0, x1, y1, z1, hidden)
  local bars = f[16]
  local n = #bars
  bars[n + 1], bars[n + 2] = joint(f, x0, y0, z0), joint(f, x1, y1, z1)
  if not hidden then
    f[17] = f[17] + 1
  end
  local b = barBox(f, n // 2 + 1)
  for k = 1, 3 do
    if n == 0 or b[k] < f[k] then
      f[k] = b[k]
    end
    if n == 0 or b[k + 3] > f[k + 3] then
      f[k + 3] = b[k + 3]
    end
  end
  local w, h, d = f[4] - f[1], f[5] - f[2], f[6] - f[3]
  f[7], f[8], f[9] = f[1] + w / 2, f[2] + h / 2, f[3] + d / 2
  f[10] = math.sqrt(w * w + h * h + d * d) / 2
end

-- half: the bars' half thickness
local function newFrame(scene, half, meta)
  -- stylua: ignore
  local f = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, half, {}, {}, {}, {}, 0 }
  return scene.addObject(setmetatable(f, meta or FRAME))
end

-- Opening flown through for racing: g as Gap.new, plus the marker's anchor: centre cx, cy, cz ([9..11]) and top
-- ([12]). piece ([13]): the frame when it has several openings, so racing previews the next when two of it follow
-- each other, else false. A way round (Course.around) adds [14], its side.
local function opening(g, cx, cy, cz, top, piece)
  g[9], g[10], g[11], g[12], g[13] = cx, cy, cz, top, piece or false
  return g
end

-- Gate frame of cols x rows openings, each w wide and h tall, centred on x, z with the lowest opening's bottom y0
-- up. alongX: the frame stands along x (flown through northwards or back); else along z. Posts run from the ground
-- to the top bar and the bars across all of them; a frame on the ground (y0 within a bar) has no bottom bar.
-- Returns a gap per opening, bottom row first and each row towards +x or +z, linked as one piece when there are
-- several (see opening).
function Course.addFrame(scene, x, z, w, h, y0, alongX, cols, rows)
  local f = newFrame(scene, HALF)
  local ux, uz = alongX and 1 or 0, alongX and 0 or 1
  -- Centre lines: the outer posts' offset, the top bar's height
  local outer = (cols * w + (cols - 1) * BAR) / 2 + HALF
  local top = y0 + rows * (h + BAR) - HALF
  for k = 0, cols do
    local u = -outer + k * (w + BAR)
    link(f, x + ux * u, HALF, z + uz * u, x + ux * u, top, z + uz * u)
  end
  for k = y0 > BAR and 0 or 1, rows do
    local y = y0 - HALF + k * (h + BAR)
    link(f, x - ux * outer, y, z - uz * outer, x + ux * outer, y, z + uz * outer)
  end
  local gaps, piece = {}, cols * rows > 1 and f or nil
  for k = 0, rows - 1 do
    local yb = y0 + k * (h + BAR)
    for c = 0, cols - 1 do
      -- Opening centre along the frame
      local u = -outer + c * (w + BAR) + (w + BAR) / 2
      local ox, oz = x + ux * u, z + uz * u
      local g = Gap.new("GATE", 0, ox - ux * w / 2, yb, oz - uz * w / 2, ox + ux * w / 2, yb + h, oz + uz * w / 2)
      -- Several openings: the marker sits in the middle of its own, not on the bar shared with the next row
      local mid = yb + h / 2
      gaps[#gaps + 1] = opening(g, ox, mid, oz, piece and mid or yb + h, piece)
    end
  end
  return gaps
end

-- Single gate w x h (see Course.addFrame); returns its opening
function Course.addGate(scene, x, z, w, h, y0, alongX)
  return Course.addFrame(scene, x, z, w, h, y0, alongX, 1, 1)[1]
end

-- Open cube frame round a space s on a side, centred on x, z, its floor y0 up: legs at the corners carry it when
-- y0 is above a bar. Returns its faces' openings as top, n, s, e, w (towards +z, -z, +x, -x).
function Course.addCube(scene, x, z, s, y0)
  local f = newFrame(scene, HALF)
  local e = (s + BAR) / 2
  local yb, yt = y0 > BAR and y0 - HALF or HALF, y0 + s + HALF
  -- Corners round the square: x and z signs
  local sx, sz = { -1, 1, 1, -1 }, { -1, -1, 1, 1 }
  for i = 1, 4 do
    local j = i % 4 + 1
    local ax, az, bx, bz = x + sx[i] * e, z + sz[i] * e, x + sx[j] * e, z + sz[j] * e
    link(f, ax, HALF, az, ax, yt, az)
    link(f, ax, yb, az, bx, yb, bz)
    link(f, ax, yt, az, bx, yt, bz)
  end
  -- Side markers sit in the middle of the face, where they stay in view from inside after the dive
  local y1, mid, hs = y0 + s, y0 + s / 2, s / 2
  return {
    top = opening(Gap.new("CUBE", 0, x - hs, y1, z - hs, x + hs, y1, z + hs), x, y1, z, y1 + BAR, f),
    n = opening(Gap.new("CUBE", 0, x - hs, y0, z + e, x + hs, y1, z + e), x, mid, z + e, mid, f),
    s = opening(Gap.new("CUBE", 0, x - hs, y0, z - e, x + hs, y1, z - e), x, mid, z - e, mid, f),
    e = opening(Gap.new("CUBE", 0, x + e, y0, z - hs, x + e, y1, z + hs), x + e, mid, z, mid, f),
    w = opening(Gap.new("CUBE", 0, x - e, y0, z - hs, x - e, y1, z + hs), x - e, mid, z, mid, f),
  }
end

-- Flag: a pole with a banner, passed on one side. The banner hangs off the pole away from that side.
local POLE_H, POLE_HALF = 3.2, 0.03
-- Banner outline as {distance from the pole, height below the pole top}, convex
-- stylua: ignore
local BANNER = { 0, 0, 0.45, 0.1, 0.8, 0.6, 0.8, 2.4, 0, 2.6 }
-- The pass is scored crossing the line from the pole out to FLAG_REACH on its side, up to FLAG_TOP
local FLAG_REACH, FLAG_TOP = 25, 25
local BX, BY, BZ = {}, {}, {}

local function drawFlag(f, fogged)
  local edge = fogged and Scene.FAR_EDGE or Scene.EDGE
  drawFrame(f, fogged)
  -- Pole foot x, z; pass side dx, dz
  local x, z, dx, dz = f[13][1], f[15][1], f[18], f[19]
  for i = 1, #BANNER // 2 do
    local u = -BANNER[2 * i - 1]
    BX[i], BY[i], BZ[i] = x + dx * u, POLE_H - BANNER[2 * i], z + dz * u
  end
  R.poly(BX, BY, BZ, #BANNER // 2, edge, true)
end

local FLAG = { __index = { draw = drawFlag, collides = frameCollides, near = frameNear } }

-- Flag at x, z passed on the side dx, dz points to (one of them 1 or -1, the other 0). Returns its pass line.
function Course.addFlag(scene, x, z, dx, dz)
  local f = newFrame(scene, POLE_HALF, FLAG)
  link(f, x, POLE_HALF, z, x, POLE_H, z)
  -- Banner: collides as a hidden bar across it, away from the pass side
  local w, h = BANNER[7], BANNER[10]
  link(f, x, POLE_H - h, z, x - dx * w, POLE_H, z - dz * w, true)
  -- pass side dx, dz
  f[18], f[19] = dx, dz
  local ex, ez = x + dx * FLAG_REACH, z + dz * FLAG_REACH
  local g = Gap.new("FLAG", 0, math.min(x, ex), 0, math.min(z, ez), math.max(x, ex), FLAG_TOP, math.max(z, ez))
  return opening(g, x + dx * 1.5, 1.5, z + dz * 1.5, POLE_H)
end

-- Way round frame opening g to the next: crossing the frame's plane beyond its post on the side towards +u (side 1)
-- or -u (-1), out to FLAG_REACH and up to FLAG_TOP, as between ladder rungs. Its marker stands SIDE_OUT beyond the
-- post at the opening's top, and its side in [14]: racing marks it with an arrow pointing back in.
local SIDE_OUT = 2.5
function Course.around(g, side)
  -- u0, u1 run along the frame: x for a frame across z (axis 3), else z; v1 is the opening's top
  -- u1, u0
  local edge = side > 0 and g[4] + BAR or g[3] - BAR
  local far, mark = edge + side * FLAG_REACH, edge + side * SIDE_OUT
  local u0, u1 = math.min(edge, far), math.max(edge, far)
  local r
  -- axis, at, v1
  local at, v1 = g[2], g[6]
  if g[1] == 3 then
    r = opening(Gap.new("ROUND", 0, u0, 0, at, u1, FLAG_TOP, at), mark, v1, at, v1)
  else
    r = opening(Gap.new("ROUND", 0, at, 0, u0, at, FLAG_TOP, u1), at, v1, mark, v1)
  end
  -- side
  r[14] = side
  return r
end

return Course
