-- Gaps: flat rectangles flown through, scoring in freestyle and making up race openings, and the test for flying
-- through one.

local Gap = {}

-- Gap for freestyle scoring: a flat rectangle x0, y0, z0 .. x1, y1, z1, flat along one axis (x0 == x1: a
-- window in a wall along z; y0 == y1: a hole in a roof), worth points flown through.
function Gap.new(name, points, x0, y0, z0, x1, y1, z1)
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
function Gap.through(g, ox, oy, oz, px, py, pz)
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

return Gap
