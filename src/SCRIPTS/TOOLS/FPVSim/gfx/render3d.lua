-- Projects world-space geometry through the FPV camera and emits screen-space primitives to a sink:
--   sink.fill(xs, ys, n, shade, opaque)   convex polygon, coordinates in pixels (floats)
--   sink.line(x1, y1, x2, y2, shade)
-- Shades: 0 white .. 4 black.

local sin, cos, tan = math.sin, math.cos, math.tan

local RAD = math.pi / 180
local NEAR = 0.2
local MAX_VERTS = 12
-- Boxes shorter or narrower than this on screen get their silhouette outline only: fill rows and inner edges are
-- invisible there
local DETAIL_PX = 6
local THIN_PX = 4
-- Below this height the edges between faces are too short to read, so only the outline is drawn
local EDGES_PX = 16

local R = {}

local sink
local ox, oy, oz
local rx, ry, rz, ux, uy, uz, fx, fy, fz
local focal, cx, cy
-- Camera uptilt
local tiltSin, tiltCos
-- View cone slopes: |x| <= z * tanX and |y| <= z * tanY are on screen
local tanX, tanY
-- Angle between the view direction and the screen corners, in radians
local cornerAngle

local CX, CY, CZ = {}, {}, {}
local KX, KY, KZ = {}, {}, {}
local SX, SY = {}, {}
for i = 1, MAX_VERTS do
  CX[i], CY[i], CZ[i], KX[i], KY[i], KZ[i], SX[i], SY[i] = 0, 0, 0, 0, 0, 0, 0, 0
end

function R.setSink(s)
  sink = s
end

-- Viewport, lens and camera uptilt, fixed for a flight: vx, vy, vw, vh in pixels, fovDeg the diagonal field of
-- view (as FPV cameras are specified), camDeg the tilt up about the body right axis
function R.setView(vx, vy, vw, vh, fovDeg, camDeg)
  focal = math.sqrt(vw * vw + vh * vh) / 2 / tan(fovDeg * RAD / 2)
  cx = vx + vw / 2
  cy = vy + vh / 2
  tanX = (vw / 2) / focal
  tanY = (vh / 2) / focal
  cornerAngle = math.atan(math.sqrt(tanX * tanX + tanY * tanY))
  tiltSin, tiltCos = sin(camDeg * RAD), cos(camDeg * RAD)
end

-- Camera at the quad q, tilted as set by setView
function R.setCamera(q)
  local s, c = tiltSin, tiltCos
  ox, oy, oz = q.px, q.py + 0.05, q.pz
  rx, ry, rz = q.rx, q.ry, q.rz
  fx, fy, fz = q.fx * c + q.ux * s, q.fy * c + q.uy * s, q.fz * c + q.uz * s
  ux, uy, uz = q.ux * c - q.fx * s, q.uy * c - q.fy * s, q.uz * c - q.fz * s
end

-- Conservative test for a bounding sphere: false only when it is entirely off screen.
-- The cone is widened by the radius divided by the cosine of its half-angle, approximated by (1 + tan).
function R.sphereVisible(x, y, z, radius)
  x, y, z = x - ox, y - oy, z - oz
  local cxs, cys, czs = x * rx + y * ry + z * rz, x * ux + y * uy + z * uz, x * fx + y * fy + z * fz
  if czs < NEAR - radius then
    return
  end
  if cxs < 0 then
    cxs = -cxs
  end
  if cys < 0 then
    cys = -cys
  end
  return cxs <= czs * tanX + radius * (1 + tanX) and cys <= czs * tanY + radius * (1 + tanY)
end

function R.focal()
  return focal
end

-- Largest angle off the view direction that is still on screen (the corners), in radians
function R.cornerAngle()
  return cornerAngle
end

-- Camera forward direction in world space
function R.forward()
  return fx, fy, fz
end

-- World direction (no translation) to camera space
function R.camVector(x, y, z)
  return x * rx + y * ry + z * rz, x * ux + y * uy + z * uz, x * fx + y * fy + z * fz
end

function R.cameraPos()
  return ox, oy, oz
end

-- World point to camera space (x right, y up, z depth)
function R.toCamera(x, y, z)
  x, y, z = x - ox, y - oy, z - oz
  return x * rx + y * ry + z * rz, x * ux + y * uy + z * uz, x * fx + y * fy + z * fz
end

local toCamera = R.toCamera

-- Line given in camera space
function R.camLine(ax, ay, az, bx, by, bz, shade)
  if az < NEAR then
    if bz < NEAR then
      return
    end
    local t = (NEAR - az) / (bz - az)
    ax, ay, az = ax + (bx - ax) * t, ay + (by - ay) * t, NEAR
  elseif bz < NEAR then
    local t = (NEAR - bz) / (az - bz)
    bx, by, bz = bx + (ax - bx) * t, by + (ay - by) * t, NEAR
  end
  sink.line(cx + ax * focal / az, cy - ay * focal / az, cx + bx * focal / bz, cy - by * focal / bz, shade)
end

-- Line given in world space
function R.line(ax, ay, az, bx, by, bz, shade)
  ax, ay, az = toCamera(ax, ay, az)
  bx, by, bz = toCamera(bx, by, bz)
  R.camLine(ax, ay, az, bx, by, bz, shade)
end

-- Upright bar of width 2 * half from (x, y0, z) to (x, y1, z) as its outline only: two sides at its projected width
-- and the caps between them. Returns false, drawing nothing, when it is wider than maxPx on screen, seen nearly
-- end-on or crosses the near plane: those need a box.
function R.bar(x, z, y0, y1, half, maxPx, shade)
  local ax, ay, az = toCamera(x, y0, z)
  local bx, by, bz = toCamera(x, y1, z)
  if az < NEAR or bz < NEAR then
    return false
  end
  local ha, hb = half * focal / az, half * focal / bz
  if 2 * (ha > hb and ha or hb) > maxPx then
    return false
  end
  ax, ay = cx + ax * focal / az, cy - ay * focal / az
  bx, by = cx + bx * focal / bz, cy - by * focal / bz
  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx * dx + dy * dy)
  if len < maxPx then
    return false
  end
  local nx, ny = -dy / len, dx / len
  local a1x, a1y, a2x, a2y = ax + nx * ha, ay + ny * ha, ax - nx * ha, ay - ny * ha
  local b1x, b1y, b2x, b2y = bx + nx * hb, by + ny * hb, bx - nx * hb, by - ny * hb
  sink.line(a1x, a1y, b1x, b1y, shade)
  sink.line(a2x, a2y, b2x, b2y, shade)
  sink.line(a1x, a1y, a2x, a2y, shade)
  sink.line(b1x, b1y, b2x, b2y, shade)
  return true
end

-- Clips CX/CY/CZ[1..n] against the near plane, projects into SX/SY, fills.
local function clipProjectFill(n, shade, opaque)
  local m = 0
  local px, py, pz = CX[n], CY[n], CZ[n]
  for i = 1, n do
    local qx, qy, qz = CX[i], CY[i], CZ[i]
    local pIn, qIn = pz >= NEAR, qz >= NEAR
    if pIn ~= qIn then
      local t = (NEAR - pz) / (qz - pz)
      m = m + 1
      KX[m], KY[m], KZ[m] = px + (qx - px) * t, py + (qy - py) * t, NEAR
    end
    if qIn then
      m = m + 1
      KX[m], KY[m], KZ[m] = qx, qy, qz
    end
    px, py, pz = qx, qy, qz
  end
  if m < 3 then
    return
  end
  for i = 1, m do
    local z = KZ[i]
    SX[i] = cx + KX[i] * focal / z
    SY[i] = cy - KY[i] * focal / z
  end
  sink.fill(SX, SY, m, shade, opaque)
end

-- Convex world polygon given as parallel coordinate arrays
function R.poly(wx, wy, wz, n, shade, opaque)
  local inFront = 0
  for i = 1, n do
    local x, y, z = toCamera(wx[i], wy[i], wz[i])
    CX[i], CY[i], CZ[i] = x, y, z
    if z >= NEAR then
      inFront = inFront + 1
    end
  end
  if inFront == n then
    for i = 1, n do
      local z = CZ[i]
      SX[i] = cx + CX[i] * focal / z
      SY[i] = cy - CY[i] * focal / z
    end
    sink.fill(SX, SY, n, shade, opaque)
  elseif inFront > 0 then
    clipProjectFill(n, shade, opaque)
  end
end

-- Box corners: index = 1 + (x1 ? 1 : 0) + (y1 ? 2 : 0) + (z1 ? 4 : 0)
local BX, BY, BZ, BSX, BSY = {}, {}, {}, {}, {}
for i = 1, 8 do
  BX[i], BY[i], BZ[i], BSX[i], BSY[i] = 0, 0, 0, 0, 0
end

-- Per camera region: silhouette corner loop and the inner edges between visible faces (corner pairs), each packed
-- into an integer a corner per 4 bits, first in the lowest: a table per list costs ten times the memory.
-- Key: (sx + 1) + 3 * (sz + 1) + 9 * (sy + 1), with sx/sy/sz in -1..1 (camera before/within/after the box).
local SILHOUETTE, INNER = {}, {}
-- The current box's loop, unpacked
local LOOP = {}

local function pack(list)
  local code = 0
  for i = #list, 1, -1 do
    code = code * 16 + list[i]
  end
  return code
end

local function buildSilhouettes()
  -- Faces with outward-facing vertex order, so an edge shared by two faces runs in opposite directions.
  local FACE_NX, FACE_PX = { 1, 5, 7, 3 }, { 2, 4, 8, 6 }
  local FACE_NZ, FACE_PZ = { 1, 3, 4, 2 }, { 5, 6, 8, 7 }
  local FACE_TOP, FACE_BOTTOM = { 3, 7, 8, 4 }, { 1, 2, 6, 5 }
  for sy = -1, 1 do
    for sz = -1, 1 do
      for sx = -1, 1 do
        local faces = {}
        if sx < 0 then
          faces[#faces + 1] = FACE_NX
        elseif sx > 0 then
          faces[#faces + 1] = FACE_PX
        end
        if sz < 0 then
          faces[#faces + 1] = FACE_NZ
        elseif sz > 0 then
          faces[#faces + 1] = FACE_PZ
        end
        if sy > 0 then
          faces[#faces + 1] = FACE_TOP
        elseif sy < 0 then
          faces[#faces + 1] = FACE_BOTTOM
        end
        -- Directed edges keyed a * 16 + b; a shared edge cancels against its reverse
        local edges, inner = {}, {}
        for _, f in ipairs(faces) do
          for i = 1, 4 do
            local a, b = f[i], f[i % 4 + 1]
            if edges[b * 16 + a] then
              edges[b * 16 + a] = nil
              inner[#inner + 1] = a
              inner[#inner + 1] = b
            else
              edges[a * 16 + b] = true
            end
          end
        end
        local nextOf = {}
        for e in pairs(edges) do
          nextOf[e // 16] = e % 16
        end
        local loop = {}
        local start = next(nextOf)
        local v = start
        while v do
          loop[#loop + 1] = v
          v = nextOf[v]
          if v == start then
            break
          end
        end
        local key = (sx + 1) + 3 * (sz + 1) + 9 * (sy + 1)
        SILHOUETTE[key], INNER[key] = pack(loop), pack(inner)
      end
    end
  end
end
buildSilhouettes()

-- Axis-aligned box drawn as one filled silhouette, outlined, plus lines on the edges between its faces.
-- edgeShade: line shade for outline and edges (0 draws white lines, for solid black boxes).
-- shade nil: outline only, for distant boxes.
function R.box(x0, y0, z0, x1, y1, z1, shade, edgeShade)
  local sx = ox < x0 and -1 or (ox > x1 and 1 or 0)
  local sz = oz < z0 and -1 or (oz > z1 and 1 or 0)
  local sy = oy < y0 and -1 or (oy > y1 and 1 or 0)
  local key = (sx + 1) + 3 * (sz + 1) + 9 * (sy + 1)
  local code = SILHOUETTE[key]
  if code == 0 then
    return
  end
  -- Corners, 4 bits each (see SILHOUETTE)
  local loop, n = LOOP, 0
  while code > 0 do
    n = n + 1
    loop[n] = code % 16
    code = code // 16
  end

  local ax, ay, az = toCamera(x0, y0, z0)
  local w, h, d = x1 - x0, y1 - y0, z1 - z0
  local wx, wy, wz = w * rx, w * ux, w * fx
  local hx, hy, hz = h * ry, h * uy, h * fy
  local dx, dy, dz = d * rz, d * uz, d * fz

  BX[1], BY[1], BZ[1] = ax, ay, az
  BX[2], BY[2], BZ[2] = ax + wx, ay + wy, az + wz
  BX[3], BY[3], BZ[3] = ax + hx, ay + hy, az + hz
  BX[4], BY[4], BZ[4] = BX[2] + hx, BY[2] + hy, BZ[2] + hz
  for i = 1, 4 do
    BX[i + 4], BY[i + 4], BZ[i + 4] = BX[i] + dx, BY[i] + dy, BZ[i] + dz
  end

  local inFront = 0
  for i = 1, 8 do
    local z = BZ[i]
    if z >= NEAR then
      inFront = inFront + 1
      BSX[i] = cx + BX[i] * focal / z
      BSY[i] = cy - BY[i] * focal / z
    end
  end
  if inFront == 0 then
    return
  end

  local inner = INNER[key]
  if inFront == 8 then
    local xmin, xmax, ymin, ymax = 1e9, -1e9, 1e9, -1e9
    for i = 1, n do
      local c = loop[i]
      local x, y = BSX[c], BSY[c]
      SX[i], SY[i] = x, y
      if x < xmin then
        xmin = x
      end
      if x > xmax then
        xmax = x
      end
      if y < ymin then
        ymin = y
      end
      if y > ymax then
        ymax = y
      end
    end
    if not shade or ymax - ymin < DETAIL_PX or xmax - xmin < THIN_PX then
      local px, py = SX[n], SY[n]
      for i = 1, n do
        sink.line(px, py, SX[i], SY[i], edgeShade)
        px, py = SX[i], SY[i]
      end
      return
    end
    sink.fill(SX, SY, n, shade, shade < 4)
    if shade ~= edgeShade then
      local px, py = SX[n], SY[n]
      for i = 1, n do
        sink.line(px, py, SX[i], SY[i], edgeShade)
        px, py = SX[i], SY[i]
      end
    end
    if ymax - ymin >= EDGES_PX then
      -- Corner pairs, 4 bits a corner (see SILHOUETTE)
      while inner > 0 do
        local a, b = inner % 16, inner // 16 % 16
        inner = inner // 256
        sink.line(BSX[a], BSY[a], BSX[b], BSY[b], edgeShade)
      end
    end
  else
    for i = 1, n do
      local c = loop[i]
      CX[i], CY[i], CZ[i] = BX[c], BY[c], BZ[c]
    end
    if shade then
      clipProjectFill(n, shade, shade < 4)
    end
    if shade ~= edgeShade then
      for i = 1, n do
        local a, b = loop[i], loop[i % n + 1]
        R.camLine(BX[a], BY[a], BZ[a], BX[b], BY[b], BZ[b], edgeShade)
      end
    end
    -- Corner pairs, 4 bits a corner (see SILHOUETTE)
    while shade and inner > 0 do
      local a, b = inner % 16, inner // 16 % 16
      inner = inner // 256
      R.camLine(BX[a], BY[a], BZ[a], BX[b], BY[b], BZ[b], edgeShade)
    end
  end
end

return R
