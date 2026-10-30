-- Course pieces: gaps (openings that score in freestyle), the test for flying through one, and the race kit: gates,
-- ladders, side-by-side gates, cubes and flags.

local R, Scene = ...

local Course = {}

-- Gap for freestyle scoring: a flat rectangle x0, y0, z0 .. x1, y1, z1, flat along one axis (x0 == x1: a
-- window in a wall along z; y0 == y1: a hole in a roof), worth points flown through.
function Course.gap(name, points, x0, y0, z0, x1, y1, z1)
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

-- True when the path from ox, oy, oz to px, py, pz crosses gap g, either way
function Course.through(g, ox, oy, oz, px, py, pz)
  local a, b, u, u1, v, v1
  local axis = g.axis
  if axis == 1 then
    a, b, u, u1, v, v1 = ox, px, oy, py, oz, pz
  elseif axis == 2 then
    a, b, u, u1, v, v1 = oy, py, ox, px, oz, pz
  else
    a, b, u, u1, v, v1 = oz, pz, ox, px, oy, py
  end
  local at = g.at
  if (a < at) == (b < at) then
    return false
  end
  local t = (at - a) / (b - a)
  u, v = u + (u1 - u) * t, v + (v1 - v) * t
  return u > g.u0 and u < g.u1 and v > g.v0 and v < g.v1
end

-- Race kit pieces are frames of square bars between joints (R.frame), colliding as one box per bar. Gate bars are
-- BAR thick.
local BAR = 0.3
local HALF = BAR / 2

local function drawFrame(f, fogged)
  if fogged then
    R.frame(f.jx, f.jy, f.jz, f.bars, f.half, Scene.FAR_EDGE)
  else
    R.frame(f.jx, f.jy, f.jz, f.bars, f.half, Scene.EDGE, 0)
  end
end

-- New frame: f:joint(x, y, z) adds a joint and returns its index, f:link(a, b) a bar between two joints
local function joint(f, x, y, z)
  local jx, jy, jz = f.jx, f.jy, f.jz
  local n = #jx + 1
  jx[n], jy[n], jz[n] = x, y, z
  return n
end

local function link(f, a, b)
  local bars, jx, jy, jz, h = f.bars, f.jx, f.jy, f.jz, f.half
  bars[#bars + 1], bars[#bars + 2] = a, b
  local x0, y0, z0 = math.min(jx[a], jx[b]), math.min(jy[a], jy[b]), math.min(jz[a], jz[b])
  local x1, y1, z1 = math.max(jx[a], jx[b]), math.max(jy[a], jy[b]), math.max(jz[a], jz[b])
  f:add((x0 + x1) / 2, (z0 + z1) / 2, x1 - x0 + 2 * h, z1 - z0 + 2 * h, y1 - y0 + 2 * h, y0 - h)
end

-- half: the bars' half thickness
local function newFrame(scene, half)
  local f = Scene.newStructure()
  f.jx, f.jy, f.jz, f.bars, f.half = {}, {}, {}, {}, half
  f.joint, f.link, f.draw = joint, link, drawFrame
  return scene.addObject(f)
end

-- Opening flown through for racing: g as Course.gap, plus the marker's anchor: centre cx, cy, cz and top
local function opening(g, cx, cy, cz, top)
  g.cx, g.cy, g.cz, g.top = cx, cy, cz, top
  return g
end

-- Gate frame of cols x rows openings, each w wide and h tall, centred on x, z with the lowest opening's bottom y0
-- up. alongX: the frame stands along x (flown through northwards or back); else along z. Posts run from the ground
-- to the top bar and the bars across all of them; a frame on the ground (y0 within a bar) has no bottom bar.
-- Returns a gap per row of openings, bottom first, spanning the row: a post in the way is a crash anyway.
function Course.addFrame(scene, x, z, w, h, y0, alongX, cols, rows)
  local f = newFrame(scene, HALF)
  local ux, uz = alongX and 1 or 0, alongX and 0 or 1
  -- Centre lines: the outer posts' offset, the top bar's height
  local outer = (cols * w + (cols - 1) * BAR) / 2 + HALF
  local top = y0 + rows * (h + BAR) - HALF
  for k = 0, cols do
    local u = -outer + k * (w + BAR)
    f:link(f:joint(x + ux * u, HALF, z + uz * u), f:joint(x + ux * u, top, z + uz * u))
  end
  for k = y0 > BAR and 0 or 1, rows do
    local y = y0 - HALF + k * (h + BAR)
    f:link(f:joint(x - ux * outer, y, z - uz * outer), f:joint(x + ux * outer, y, z + uz * outer))
  end
  local gaps, half = {}, outer - HALF
  for k = 0, rows - 1 do
    local yb = y0 + k * (h + BAR)
    local g = Course.gap("GATE", 0, x - ux * half, yb, z - uz * half, x + ux * half, yb + h, z + uz * half)
    gaps[k + 1] = opening(g, x, yb + h / 2, z, yb + h)
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
  local floor, roof = {}, {}
  -- Corners round the square: x and z signs
  local sx, sz = { -1, 1, 1, -1 }, { -1, -1, 1, 1 }
  for i = 1, 4 do
    local cx, cz = x + sx[i] * e, z + sz[i] * e
    local foot = f:joint(cx, HALF, cz)
    roof[i] = f:joint(cx, yt, cz)
    f:link(foot, roof[i])
    floor[i] = yb > HALF and f:joint(cx, yb, cz) or foot
  end
  for i = 1, 4 do
    local j = i % 4 + 1
    f:link(floor[i], floor[j])
    f:link(roof[i], roof[j])
  end
  local y1, mid, hs = y0 + s, y0 + s / 2, s / 2
  return {
    top = opening(Course.gap("CUBE", 0, x - hs, y1, z - hs, x + hs, y1, z + hs), x, y1, z, y1 + BAR),
    n = opening(Course.gap("CUBE", 0, x - hs, y0, z + e, x + hs, y1, z + e), x, mid, z + e, y1),
    s = opening(Course.gap("CUBE", 0, x - hs, y0, z - e, x + hs, y1, z - e), x, mid, z - e, y1),
    e = opening(Course.gap("CUBE", 0, x + e, y0, z - hs, x + e, y1, z + hs), x + e, mid, z, y1),
    w = opening(Course.gap("CUBE", 0, x - e, y0, z - hs, x - e, y1, z + hs), x - e, mid, z, y1),
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
  local x, z, dx, dz = f.jx[1], f.jz[1], f.dx, f.dz
  for i = 1, #BANNER // 2 do
    local u = -BANNER[2 * i - 1]
    BX[i], BY[i], BZ[i] = x + dx * u, POLE_H - BANNER[2 * i], z + dz * u
  end
  R.poly(BX, BY, BZ, #BANNER // 2, edge, true)
end

-- Flag at x, z passed on the side dx, dz points to (one of them 1 or -1, the other 0). Returns its pass line.
function Course.addFlag(scene, x, z, dx, dz)
  local f = newFrame(scene, POLE_HALF)
  f:link(f:joint(x, POLE_HALF, z), f:joint(x, POLE_H, z))
  -- Banner: a thin box away from the pass side
  local w, h = BANNER[7], BANNER[10]
  f:add(x - dx * w / 2, z - dz * w / 2, dx ~= 0 and w or 0.05, dz ~= 0 and w or 0.05, h, POLE_H - h)
  f.draw, f.dx, f.dz = drawFlag, dx, dz
  local ex, ez = x + dx * FLAG_REACH, z + dz * FLAG_REACH
  local g = Course.gap("FLAG", 0, math.min(x, ex), 0, math.min(z, ez), math.max(x, ex), FLAG_TOP, math.max(z, ez))
  return opening(g, x + dx * 1.5, 1.5, z + dz * 1.5, POLE_H)
end

return Course
