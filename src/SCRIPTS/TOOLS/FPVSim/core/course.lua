-- Course pieces: gaps (openings that score in freestyle), the test for flying through one, and race gates.

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

-- Race gate frame: posts and bars GATE_BAR thick round an opening w wide and h tall, its bottom y0 up, centred on
-- x, z. alongX: the frame stands along x (flown through northwards or back); else along z. Returns the opening as
-- a gap carrying its centre cx, cy, cz and top.
-- The frame collides as boxes but draws as boxes only near the camera: further out the bars are a pixel or two wide,
-- so the frame's outer and inner edges as lines are the same picture at a fraction of the cost. GATE_PX: bar width
-- on screen below which the lines take over.
local GATE_BAR, GATE_PX = 0.3, 2.5

-- Edges in the gate's plane: horizontal offset from the centre, height
local function gateLine(g, a, ay, b, by, shade)
  local x, z, ux, uz = g.cx, g.cz, g.ux, g.uz
  R.line(x + ux * a, ay, z + uz * a, x + ux * b, by, z + uz * b, shade)
end

local function drawGate(g, fogged)
  -- Ground distance within which the bars are GATE_PX or wider; dist is to the centre, so plus the half width
  local near = GATE_BAR * R.focal() / GATE_PX + g.half + GATE_BAR
  if g.dist < near * near then
    g.drawBoxes(g, fogged)
    return
  end
  local shade = fogged and Scene.FAR_EDGE or Scene.EDGE
  -- Outer and inner half widths and edges, the outer bottom on the ground when it has no bottom bar
  local o, i = g.half + GATE_BAR, g.half
  local ob, ib, it, ot = g.base, g.y0, g.y1, g.y1 + GATE_BAR
  gateLine(g, -o, ob, -o, ot, shade)
  gateLine(g, -o, ot, o, ot, shade)
  gateLine(g, o, ot, o, ob, shade)
  gateLine(g, -i, ib, -i, it, shade)
  gateLine(g, -i, it, i, it, shade)
  gateLine(g, i, it, i, ib, shade)
  if ob > 0 then
    gateLine(g, -o, ob, o, ob, shade)
    gateLine(g, -i, ib, i, ib, shade)
    -- Legs down the posts' middles
    local m = g.half + GATE_BAR / 2
    gateLine(g, -m, 0, -m, ob, shade)
    gateLine(g, m, 0, m, ob, shade)
  end
end

function Course.addGate(scene, x, z, w, h, y0, alongX)
  local st = Scene.newStructure()
  local T = GATE_BAR
  local px, pz, pw, pd, bw, bd
  if alongX then
    px, pz, pw, pd, bw, bd = (w + T) / 2, 0, T, T, w + 2 * T, T
  else
    px, pz, pw, pd, bw, bd = 0, (w + T) / 2, T, T, T, w + 2 * T
  end
  -- Posts are split at the bottom bar, which starts a level
  local base = 0
  if y0 > T then
    base = y0 - T
    st.add(x - px, z - pz, pw, pd, base, 0)
    st.add(x + px, z + pz, pw, pd, base, 0)
    st.add(x, z, bw, bd, T, base)
  end
  st.add(x - px, z - pz, pw, pd, y0 + h - base, base)
  st.add(x + px, z + pz, pw, pd, y0 + h - base, base)
  st.add(x, z, bw, bd, T, y0 + h)
  st.drawBoxes, st.draw = st.draw, drawGate
  st.half, st.base, st.y0, st.y1 = w / 2, base, y0, y0 + h
  st.ux, st.uz = alongX and 1 or 0, alongX and 0 or 1
  scene.addObject(st)
  local g
  if alongX then
    g = Course.gap("GATE", 0, x - w / 2, y0, z, x + w / 2, y0 + h, z)
  else
    g = Course.gap("GATE", 0, x, y0, z - w / 2, x, y0 + h, z + w / 2)
  end
  g.cx, g.cy, g.cz, g.top = x, y0 + h / 2, z, y0 + h
  return g
end

return Course
