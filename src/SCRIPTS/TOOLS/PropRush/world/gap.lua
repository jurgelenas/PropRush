-- Gaps: flat rectangles flown through, scoring in freestyle and making up race openings, and the test for flying
-- through one.

local Gap = {}

-- Gap for freestyle scoring: a flat rectangle x0, y0, z0 .. x1, y1, z1, flat along one axis (x0 == x1: a
-- window in a wall along z; y0 == y1: a hole in a roof), worth points flown through.
-- Gaps are arrays, as named fields cost a 16-node hash each on the radio: [1] axis (1, 2, 3: flat in x, y, z), [2]
-- where on it, [3], [4] the span u0..u1 and [5], [6] v0..v1 across it (y, z for axis 1; x, z for 2; x, y for 3), [7]
-- name, [8] points. Race openings add their marker from [9] on (world/course).
function Gap.new(name, points, x0, y0, z0, x1, y1, z1)
  if x0 == x1 then
    return { 1, x0, y0, y1, z0, z1, name, points }
  elseif y0 == y1 then
    return { 2, y0, x0, x1, z0, z1, name, points }
  end
  assert(z0 == z1, "gap is not flat")
  return { 3, z0, x0, x1, y0, y1, name, points }
end

-- True when the path from ox, oy, oz to px, py, pz crosses gap g, either way
function Gap.through(g, ox, oy, oz, px, py, pz)
  local a, b, u, u1, v, v1
  -- axis
  local axis = g[1]
  if axis == 1 then
    a, b, u, u1, v, v1 = ox, px, oy, py, oz, pz
  elseif axis == 2 then
    a, b, u, u1, v, v1 = oy, py, ox, px, oz, pz
  else
    a, b, u, u1, v, v1 = oz, pz, ox, px, oy, py
  end
  -- at
  local at = g[2]
  if (a < at) == (b < at) then
    return false
  end
  local t = (at - a) / (b - a)
  u, v = u + (u1 - u) * t, v + (v1 - v) * t
  -- u0, u1, v0, v1
  return u > g[3] and u < g[4] and v > g[5] and v < g[6]
end

return Gap
