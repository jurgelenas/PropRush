-- Farm kit: groves of trees, buildings under pitched or barn roofs and a dirt lane, drawn through the current camera
-- (render3d). Only the farm map loads it.

local R, Scene = ...

local sqrt, byte, char = math.sqrt, string.byte, string.char
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_SHADE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_SHADE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15

local Farm = {}

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }
local function setBox(x0, y0, z0, x1, y1, z1)
  BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] = x0, y0, z0, x1, y1, z1
  return BOX
end

-- Box w by d by h from its base centre x, y0, z: x0, y0, z0, x1, y1, z1
local function box(x, z, w, d, h, y0)
  return { x - w / 2, y0, z - d / 2, x + w / 2, y0 + h, z + d / 2 }
end

-- Scene object slots [1..10] round x0, y0, z0 .. x1, y1, z1: bounds, then the sphere's centre and radius
local function bound(o, x0, y0, z0, x1, y1, z1)
  o[1], o[2], o[3], o[4], o[5], o[6] = x0, y0, z0, x1, y1, z1
  local w, h, d = x1 - x0, y1 - y0, z1 - z0
  o[7], o[8], o[9], o[10], o[11] = x0 + w / 2, y0 + h / 2, z0 + d / 2, sqrt(w * w + h * h + d * d) / 2, 0
end

-- Groves: trees, each a trunk under a canopy drawn as the outline of a cone seen from the camera, a triangle, or
-- two stacked for a fir. A grove is one scene object, [1..11] as a box's, [12] its trees packed in a string, six
-- bytes a tree: x + 128 and z + 128 in metres, canopy base and top in half metres, canopy radius in tenths, tiers
-- (1 or 2). A number in a table costs 16 bytes on the radio, in a string one.
local TREE = 6

-- Tree at t[i..]: x, z, canopy base, top, canopy radius, tiers
local function tree(t, i)
  local x, z, base, top, r, tiers = byte(t, i, i + 5)
  return x - 128, z - 128, base / 2, top / 2, r / 10, tiers
end
-- Two tiers: the upper one's base TIER of the way up the canopy, UPPER of the radius wide, over the lower one LOWER
-- wide there. Outline points across (radii) and up (fractions of the canopy), base left round to base right.
local TIER, UPPER, LOWER = 0.45, 0.7, 0.4
local U1, V1 = { -1, 0, 1 }, { 0, 1, 0 }
local U2, V2 = { -1, -LOWER, -UPPER, 0, UPPER, LOWER, 1 }, { 0, TIER, TIER, 1, TIER, TIER, 0 }
-- Trunks: TRUNK half thick; within TRUNK_DIST an outline up to TRUNK_PX wide on screen and a box beyond, else one
-- line, and none beyond BARE_DIST, where it is a pixel or two under the canopy. Two tiers only within TIER_DIST:
-- further out they are a few pixels apart.
local TRUNK, TRUNK_PX, TRUNK_DIST, BARE_DIST, TIER_DIST = 0.15, 6, 20, 70, 30
local PX, PY, PZ = {}, {}, {}

local function drawTree(x, z, base, top, r, tiers, edge)
  local ox, _, oz = R.cameraPos()
  local dx, dz = x - ox, z - oz
  local len = sqrt(dx * dx + dz * dz)
  if len < 0.5 then
    return
  end
  if len > BARE_DIST then
    -- no trunk
  elseif len > TRUNK_DIST then
    R.line(x, 0, z, x, base, z, edge)
  elseif not R.bar(x, z, 0, base, TRUNK, TRUNK_PX, edge) then
    R.box(x - TRUNK, 0, z - TRUNK, x + TRUNK, base, z + TRUNK, SHADE, edge)
  end
  -- Across the line of sight, r long
  local sx, sz = -dz / len * r, dx / len * r
  local us, vs = U1, V1
  if tiers == 2 and len < TIER_DIST then
    us, vs = U2, V2
  end
  local n, h = #us, top - base
  for i = 1, n do
    local u = us[i]
    PX[i], PY[i], PZ[i] = R.toCamera(x + sx * u, base + h * vs[i], z + sz * u)
  end
  for i = 1, n - 1 do
    R.camLine(PX[i], PY[i], PZ[i], PX[i + 1], PY[i + 1], PZ[i + 1], edge)
  end
  R.camLine(PX[n], PY[n], PZ[n], PX[1], PY[1], PZ[1], edge)
end

-- trees [12]
local function drawGrove(g, fogged)
  local t = g[12]
  local edge = fogged and FAR_EDGE or EDGE
  for i = 1, #t, TREE do
    local x, z, base, top, r, tiers = tree(t, i)
    if R.sphereVisible(x, top / 2, z, top / 2 + r) then
      drawTree(x, z, base, top, r, tiers, edge)
    end
  end
end

-- Solid radius at height y of a tree: the trunk below the canopy, the cone in it, nil above
local function treeRadius(base, top, r, y)
  if y < base then
    return TRUNK
  elseif y < top then
    return r * (top - y) / (top - base)
  end
end

local function groveCollides(g, x, y, z)
  if not touches(g, x, y, z) then
    return false
  end
  local t = g[12]
  for i = 1, #t, TREE do
    local tx, tz, base, top, r = tree(t, i)
    local rad = treeRadius(base, top, r, y)
    if rad then
      local dx, dz, reach = x - tx, z - tz, rad + RADIUS
      if dx * dx + dz * dz < reach * reach then
        if y < base then
          return setBox(tx - TRUNK, 0, tz - TRUNK, tx + TRUNK, base, tz + TRUNK)
        end
        return setBox(tx - rad, y - RADIUS, tz - rad, tx + rad, y + RADIUS, tz + rad)
      end
    end
  end
  return false
end

local function groveNear(g, x, y, z, d2)
  if distance2(g, x, y, z) >= d2 then
    return false
  end
  local t = g[12]
  for i = 1, #t, TREE do
    local tx, tz, base, top, r = tree(t, i)
    local dx, dz = x - tx, z - tz
    local h = sqrt(dx * dx + dz * dz) - (treeRadius(base, top, r, y) or 0)
    local v = y > top and y - top or 0
    h = h > 0 and h or 0
    if h * h + v * v < d2 then
      return true
    end
  end
  return false
end

local GROVE = { __index = { draw = drawGrove, collides = groveCollides, near = groveNear } }

-- Grove of trees: a flat list of x, z (whole metres), canopy base height, top height (half metres), canopy radius
-- (tenths) and tiers (1 or 2) per tree. Keep a grove's trees close together: it is sorted against the rest of the
-- scene as one.
function Farm.addGrove(scene, trees)
  local x0, z0, x1, z1, y1 = math.huge, math.huge, -math.huge, -math.huge, 0
  local t = ""
  for i = 1, #trees, TREE do
    local x, z, base, top, r, tiers = trees[i], trees[i + 1], trees[i + 2], trees[i + 3], trees[i + 4], trees[i + 5]
    x0, x1 = math.min(x0, x - r), math.max(x1, x + r)
    z0, z1 = math.min(z0, z - r), math.max(z1, z + r)
    y1 = math.max(y1, top)
    t = t .. char(x + 128, z + 128, base * 2 // 1, top * 2 // 1, (r * 10 + 0.5) // 1, tiers)
  end
  local g = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, t }, GROVE)
  bound(g, x0, 0, z0, x1, y1, z1)
  return scene.addObject(g)
end

-- Buildings: walls under a roof of any convex cross-section (pitched, barn), with dormers on one slope. Arrays:
-- [1..11] as a box's; [12] true when the ridge runs along x; [13], [14] the roof's ends along the ridge; [15] the
-- cross-section, eave over to eave, four numbers a point: across the ridge (world z, or x), up, and the outward unit
-- normal across and up of the side from it to the next point, the last side the underside; [16] eave height; [17]
-- the wall boxes; [18] true when the ends are open (the underside shows); [19] dormer boxes; [20] the side of the
-- ridge they are on (1: towards +z, or +x), [21] the ridge's position across.
-- Roof faces in world space for R.poly, and which sides face the camera
local WX, WY, WZ, FACING = {}, {}, {}, {}

local function point(b, i, a, u, y)
  if b[12] then
    WX[i], WY[i], WZ[i] = a, y, u
  else
    WX[i], WY[i], WZ[i] = u, y, a
  end
end

-- Faces towards the camera at ca along the ridge, cu across, cy up: filled, then their edges
local function drawRoof(b, shade, edge, ca, cu, cy)
  -- a0, a1; cross-section
  local a0, a1, p = b[13], b[14], b[15]
  local n = #p // 4
  local last = b[18] and n or n - 1
  for i = 1, n do
    local k = 4 * i
    FACING[i] = i <= last and (cu - p[k - 3]) * p[k - 1] + (cy - p[k - 2]) * p[k] > 0
  end
  local cap = ca < a0 and a0 or ca > a1 and a1
  if cap then
    for i = 1, n do
      point(b, i, cap, p[4 * i - 3], p[4 * i - 2])
    end
    R.poly(WX, WY, WZ, n, shade, true)
  end
  for i = 1, last do
    if FACING[i] then
      local k, m = 4 * i - 3, 4 * (i % n) + 1
      point(b, 1, a0, p[k], p[k + 1])
      point(b, 2, a1, p[k], p[k + 1])
      point(b, 3, a1, p[m], p[m + 1])
      point(b, 4, a0, p[m], p[m + 1])
      R.poly(WX, WY, WZ, 4, shade, true)
    end
  end
  for i = 1, n do
    local k, m = 4 * i - 3, 4 * (i % n) + 1
    local u, y, v, w = p[k], p[k + 1], p[m], p[m + 1]
    for k = 0, 1 do
      local a = k == 0 and a0 or a1
      if FACING[i] or cap == a then
        point(b, 1, a, u, y)
        point(b, 2, a, v, w)
        R.line(WX[1], WY[1], WZ[1], WX[2], WY[2], WZ[2], edge)
      end
    end
    if FACING[i] or FACING[i == 1 and n or i - 1] then
      point(b, 1, a0, u, y)
      point(b, 2, a1, u, y)
      R.line(WX[1], WY[1], WZ[1], WX[2], WY[2], WZ[2], edge)
    end
  end
end

-- Far one first: two that overlap on screen are a shed's walls; dormers never do
local function drawBoxes(list, ox, oy, oz, shade, edge)
  local n = #list
  local back = n == 2 and distance2(list[1], ox, oy, oz) < distance2(list[2], ox, oy, oz)
  for k = 1, n do
    local b = list[back and n + 1 - k or k]
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
  end
end

-- From below the eaves the walls are in front of the roof, from above behind it
local function drawBuilding(b, fogged)
  local shade, edge = fogged and FAR_SHADE or SHADE, fogged and FAR_EDGE or EDGE
  local ox, oy, oz = R.cameraPos()
  local ca, cu = oz, ox
  if b[12] then
    ca, cu = ox, oz
  end
  -- eave
  local below = oy < b[16]
  if below then
    drawRoof(b, shade, edge, ca, cu, oy)
  end
  -- walls
  drawBoxes(b[17], ox, oy, oz, shade, edge)
  if not below then
    drawRoof(b, shade, edge, ca, cu, oy)
  end
  -- ridge across, dormer side, dormers
  if (cu - b[21]) * b[20] > 0 then
    drawBoxes(b[19], ox, oy, oz, shade, edge)
  end
end

-- Inside the roof: within each side's plane, grown by the quad's radius
local function inRoof(b, x, y, z)
  local a, u = z, x
  if b[12] then
    a, u = x, z
  end
  -- eave, a0, a1
  if y < b[16] - RADIUS or a < b[13] - RADIUS or a > b[14] + RADIUS then
    return false
  end
  local p = b[15]
  for k = 1, #p, 4 do
    if (u - p[k]) * p[k + 2] + (y - p[k + 1]) * p[k + 3] > RADIUS then
      return false
    end
  end
  return true
end

-- The roof's box: the bounds above the eaves
local function roofBox(b)
  return setBox(b[1], b[16], b[3], b[4], b[5], b[6])
end

local function buildingCollides(b, x, y, z)
  if not touches(b, x, y, z) then
    return false
  end
  -- walls, dormers
  for k = 17, 19, 2 do
    local list = b[k]
    for i = 1, #list do
      if touches(list[i], x, y, z) then
        return list[i]
      end
    end
  end
  return inRoof(b, x, y, z) and roofBox(b)
end

local function buildingNear(b, x, y, z, d2)
  if distance2(b, x, y, z) >= d2 then
    return false
  end
  -- walls, dormers
  for k = 17, 19, 2 do
    local list = b[k]
    for i = 1, #list do
      if distance2(list[i], x, y, z) < d2 then
        return true
      end
    end
  end
  return distance2(roofBox(b), x, y, z) < d2
end

local BUILDING = { __index = { draw = drawBuilding, collides = buildingCollides, near = buildingNear } }

-- Thickness of a shed's walls
local WALL = 0.25

-- Building centred on x, z, w by d (along x by along z), walls eave high, under a roof whose cross-section across
-- the ridge is roof: a flat list of across, up pairs from one eave over to the other, across from the centre.
-- alongX: the ridge runs along x. open: walls only along the ridge, the ends open to fly through.
function Farm.addBuilding(scene, x, z, w, d, eave, roof, alongX, open)
  local a0, a1, uc = z - d / 2, z + d / 2, x
  local across = w
  if alongX then
    a0, a1, uc, across = x - w / 2, x + w / 2, z, d
  end
  local n = #roof // 2
  local umin, umax, ytop, mu, my = math.huge, -math.huge, eave, 0, 0
  for i = 1, n do
    local u, y = uc + roof[2 * i - 1], roof[2 * i]
    umin, umax, ytop = math.min(umin, u), math.max(umax, u), math.max(ytop, y)
    mu, my = mu + u / n, my + y / n
  end
  -- Outward normals: away from the cross-section's middle mu, my
  local p = {}
  for i = 1, n do
    local j = i % n + 1
    local u, y = uc + roof[2 * i - 1], roof[2 * i]
    local du, dy = roof[2 * j - 1] - roof[2 * i - 1], roof[2 * j] - y
    local len = sqrt(du * du + dy * dy)
    local a, c = dy / len, -du / len
    if (u - mu) * a + (y - my) * c < 0 then
      a, c = -a, -c
    end
    p[4 * i - 3], p[4 * i - 2], p[4 * i - 1], p[4 * i] = u, y, a, c
  end
  local walls
  if not open then
    walls = { box(x, z, w, d, eave, 0) }
  elseif alongX then
    walls = { box(x, z - (d - WALL) / 2, w, WALL, eave, 0), box(x, z + (d - WALL) / 2, w, WALL, eave, 0) }
  else
    walls = { box(x - (w - WALL) / 2, z, WALL, d, eave, 0), box(x + (w - WALL) / 2, z, WALL, d, eave, 0) }
  end
  -- stylua: ignore
  local b = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, alongX, a0, a1, p, eave, walls, open, {}, 1, uc }, BUILDING)
  -- Across: the walls or the eaves, whichever reach further
  local u0, u1 = math.min(umin, uc - across / 2), math.max(umax, uc + across / 2)
  if alongX then
    bound(b, a0, 0, u0, a1, ytop, u1)
  else
    bound(b, u0, 0, a0, u1, ytop, a1)
  end
  return scene.addObject(b)
end

-- Dormer box on building b's roof, centred on x, z, w by d, h tall from y0, on the side of the ridge side points to
-- (1: towards +z, or +x for a ridge along z). It shows from that side only.
function Farm.addDormer(b, x, z, w, d, h, y0, side)
  -- dormers, their side
  local list = b[19]
  list[#list + 1] = box(x, z, w, d, h, y0)
  b[20] = side
end

-- Lanes: a track between two edge lines on the ground. Arrays: [1], [2] the left edge's x and z, [3], [4] the
-- right's. Segments are drawn within LANE_DIST.
local LANE_DIST = { 80, 110, 140 }

-- Lane along points, a flat x, z list down its middle, half wide
function Farm.newLane(points, half)
  local lx, lz, rx, rz = {}, {}, {}, {}
  local n = #points // 2
  for i = 1, n do
    -- Along the lane at point i: from the point before to the one after
    local p, q = i > 1 and i - 1 or 1, i < n and i + 1 or n
    local dx, dz = points[2 * q - 1] - points[2 * p - 1], points[2 * q] - points[2 * p]
    local len = sqrt(dx * dx + dz * dz)
    local sx, sz = -dz / len * half, dx / len * half
    local x, z = points[2 * i - 1], points[2 * i]
    lx[i], lz[i], rx[i], rz[i] = x + sx, z + sz, x - sx, z - sz
  end
  return { lx, lz, rx, rz }
end

function Farm.drawLane(lane, quality)
  local lx, lz, rx, rz = lane[1], lane[2], lane[3], lane[4]
  local ox, _, oz = R.cameraPos()
  local far = LANE_DIST[quality]
  far = far * far
  for i = 1, #lx - 1 do
    local mx, mz = (lx[i] + rx[i + 1]) / 2, (lz[i] + rz[i + 1]) / 2
    local dx, dz = mx - ox, mz - oz
    if dx * dx + dz * dz < far then
      local ex, ez = lx[i] - rx[i + 1], lz[i] - rz[i + 1]
      if R.sphereVisible(mx, 0, mz, sqrt(ex * ex + ez * ez) / 2) then
        R.line(lx[i], 0, lz[i], lx[i + 1], 0, lz[i + 1], 4)
        R.line(rx[i], 0, rz[i], rx[i + 1], 0, rz[i + 1], 4)
      end
    end
  end
end

return Farm
