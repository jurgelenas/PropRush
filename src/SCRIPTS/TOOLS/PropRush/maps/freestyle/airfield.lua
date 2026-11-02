-- Airfield: a country airstrip. A runway across the field with a taxiway behind it, a hangar open at both ends with a
-- plane inside, a control tower with an open cab, light planes parked on the apron and a windsock. One plane taxis
-- out, takes off, flies a circuit over the field, lands and taxis back.

local Ground, Scene, Gap, R = ...

local sin, cos, abs = math.sin, math.cos, math.abs
local RAD = math.pi / 180
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Runway along x, RWY_W either side of RWY_Z out to RWY_X; the taxiway along TAXI_Z, joined to it by half circles
-- round TURN_E and TURN_W
local RWY_Z, RWY_W, RWY_X, TAXI_Z, TURN_E, TURN_W = 25, 7, 90, 45, 40, -80

-- High-wing light plane: parts as a0, a1 along it (+ forward), c0, c1 across it (+ right), y0, y1, from its centre
-- stylua: ignore
local PARTS = {
  -3.75, 3.75, -0.55, 0.55, 0.6, 1.9, -- fuselage
  0.65, 2.25, -5.5, 5.5, 1.9, 2.05, -- wing
  -3.75, -2.85, -1.7, 1.7, 1.9, 2, -- tailplane
  -3.75, -2.75, -0.08, 0.08, 1.9, 3, -- fin
}
-- Under a wing: from the fuselage's side to the tip, up to the wing; WING_A its chord's middle
local IN, OUT, UNDER, WING_A = 0.7, 5.35, 1.85, 1.45

-- Plane parked facing south, scoring under each wing
local function parked(x, z)
  local st = scene.addStructure()
  for i = 1, #PARTS, 6 do
    local a0, a1, c0, c1, y0, y1 = PARTS[i], PARTS[i + 1], PARTS[i + 2], PARTS[i + 3], PARTS[i + 4], PARTS[i + 5]
    st:add(x - (c0 + c1) / 2, z - (a0 + a1) / 2, c1 - c0, a1 - a0, y1 - y0, y0)
  end
  local wz = z - WING_A
  gaps[#gaps + 1] = Gap.new("WING", 10, x - OUT, 0, wz, x - IN, UNDER, wz)
  gaps[#gaps + 1] = Gap.new("WING", 10, x + IN, 0, wz, x + OUT, UNDER, wz)
end

-- Hangar 18 x 22 m, open at both ends, under a stepped roof, with a plane inside
local HX, HZ, HW, HL, EAVE = -35, 66, 18, 22, 7
local hangar = scene.addStructure()
hangar:add(HX - HW / 2 + 0.2, HZ, 0.4, HL, EAVE, 0)
hangar:add(HX + HW / 2 - 0.2, HZ, 0.4, HL, EAVE, 0)
hangar:add(HX, HZ, HW, HL, 0.6, EAVE)
hangar:add(HX, HZ, HW - 8, HL, 0.8, EAVE + 0.6)
gaps[#gaps + 1] = Gap.new("HANGAR", 10, HX - HW / 2 + 0.4, 0, HZ - HL / 2, HX + HW / 2 - 0.4, EAVE - 0.1, HZ - HL / 2)
parked(HX, HZ + 2)

-- Control tower: a 10 m shaft, the cab open between four corner posts, a mast on its roof
local TX, TZ, CAB = -10, 64, 10
local tower = scene.addStructure()
tower:add(TX, TZ, 4, 4, CAB, 0)
tower:add(TX, TZ, 6.4, 6.4, 0.3, CAB)
for _, dx in ipairs({ -3, 3 }) do
  tower:add(TX + dx, TZ - 3, 0.3, 0.3, 2.4, CAB + 0.3)
  tower:add(TX + dx, TZ + 3, 0.3, 0.3, 2.4, CAB + 0.3)
end
tower:add(TX, TZ, 7, 7, 0.4, CAB + 2.7)
tower:add(TX, TZ, 0.2, 0.2, 4, CAB + 3.1)
gaps[#gaps + 1] = Gap.new("CAB", 15, TX - 2.85, CAB + 0.3, TZ, TX + 2.85, CAB + 2.7, TZ)

-- Apron: three planes in a row, wingtips 3 m apart
for _, x in ipairs({ 8, 22, 36 }) do
  parked(x, 59.75)
end

-- Windsock on a pole by the runway, swinging and filling with the gusts: L long, MOUTH half wide
local SX, SZ, POLE, L, MOUTH = 8, 13, 6, 3, 0.35
local WIND = 15 * RAD
scene.addBox(SX, SZ, 0.15, 0.15, POLE)
local gust = 0
-- Ring at the mouth then the tip, in camera space
local QX, QY, QZ = { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0 }

local function drawSock(_, fogged)
  local edge = fogged and FAR_EDGE or EDGE
  local d, f = WIND + 0.4 * sin(gust * 0.5) + 0.1 * sin(gust * 1.7), 0.8 + 0.2 * sin(gust * 0.9)
  local ux, uz = cos(d), sin(d)
  local px, pz = -uz * MOUTH, ux * MOUTH
  for k = 1, 4 do
    local s, up = k <= 2 and 1 or -1, (k == 1 or k == 4) and MOUTH or -MOUTH
    QX[k], QY[k], QZ[k] = R.toCamera(SX + s * px, POLE + up, SZ + s * pz)
  end
  QX[5], QY[5], QZ[5] = R.toCamera(SX + ux * L * f, POLE - L * (1 - f), SZ + uz * L * f)
  for k = 1, 4 do
    local j = k % 4 + 1
    R.camLine(QX[k], QY[k], QZ[k], QX[j], QY[j], QZ[j], edge)
    R.camLine(QX[k], QY[k], QZ[k], QX[5], QY[5], QZ[5], edge)
  end
end

-- stylua: ignore
scene.addObject(setmetatable({ SX - L, POLE - L, SZ - L, SX + L, POLE + MOUTH, SZ + L, SX, POLE, SZ, L + 1, 0 },
  { __index = { draw = drawSock } }))

-- Seconds the plane holds at the runway's west end before each take-off
local HOLD = 3

-- From x, z heading h (radians) d metres along a segment of curvature k (1 / radius, + right)
local function along(x, z, h, k, d)
  if k == 0 then
    return x + d * sin(h), z + d * cos(h), h
  end
  local e = h + k * d
  return x + (cos(h) - cos(e)) / k, z + (sin(e) - sin(h)) / k, e
end

-- Segments, 10 numbers each from offset i: [i + 1] start distance, [i + 2..4] start x, z, heading, [i + 5] length,
-- [i + 6] curvature, [i + 7], [i + 8] height and [i + 9], [i + 10] speed at its start and end
local SEG = {}
local LAP
do
  -- The plane's lap from the hold heading east. Six numbers a segment: a straight's length, 0, or an arc's radius,
  -- turn in degrees (+ right); then its height and speed (m/s) at the start and the end.
  -- stylua: ignore
  local PATH = {
    70, 0, 0, 0, 6, 24, -- take-off run
    90, 0, 0, 15, 24, 24, -- climb out
    35, 180, 15, 25, 24, 24,
    160, 0, 25, 25, 24, 24, -- downwind, behind the spawn
    35, 180, 25, 4, 24, 20,
    20, 0, 4, 0, 20, 18, -- touch down
    100, 0, 0, 0, 18, 10,
    10, -180, 0, 0, 10, 10,
    120, 0, 0, 0, 10, 10, -- taxiway
    10, -180, 0, 0, 10, 10,
  }
  local x, z, h, s = TURN_W, RWY_Z, 90 * RAD, 0
  for p = 1, #PATH, 6 do
    local a, deg = PATH[p], PATH[p + 1]
    local len, k = a, 0
    if deg ~= 0 then
      len, k = a * abs(deg) * RAD, (deg > 0 and 1 or -1) / a
    end
    local i = #SEG
    SEG[i + 1], SEG[i + 2], SEG[i + 3], SEG[i + 4], SEG[i + 5], SEG[i + 6] = s, x, z, h, len, k
    SEG[i + 7], SEG[i + 8], SEG[i + 9], SEG[i + 10] = PATH[p + 2], PATH[p + 3], PATH[p + 4], PATH[p + 5]
    x, z, h = along(x, z, h, k, len)
    s = s + len
  end
  LAP = s
end

-- Draws as outlined faces within SOLID metres (camera depth), else fuselage and wing only, black on B&W
local SOLID = 40
-- Faces of a part this thin are left out
local THIN = 0.3
-- Half length, half span; its height round the centre, and the bounding sphere's radius
local HALF_L, HALF_S, MID = 3.75, 5.5, 1.8
local SPHERE = math.sqrt(HALF_L * HALF_L + HALF_S * HALF_S + 1.2 * 1.2)

-- The plane being drawn: centre, sine and cosine of its heading, height; the camera along and across it, its height
local px, pz, ps, pc, py, ca, cc, cy
local WX, WY, WZ = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

local function corner(k, a, c, y)
  WX[k], WY[k], WZ[k] = px + a * ps + c * pc, y, pz + a * pc - c * ps
end

local function face(fill, edge)
  R.poly(WX, WY, WZ, 4, fill, true)
  if edge then
    for k = 1, 4 do
      local j = k % 4 + 1
      R.line(WX[k], WY[k], WZ[k], WX[j], WY[j], WZ[j], edge)
    end
  end
end

-- Faces of the part at offset i turned to the camera; on colour the sides a shade darker than the top
local function part(i, fill, edge)
  local a0, a1, c0, c1 = PARTS[i], PARTS[i + 1], PARTS[i + 2], PARTS[i + 3]
  local y0, y1 = py + PARTS[i + 4], py + PARTS[i + 5]
  local la, lc, ly = a1 - a0 > THIN, c1 - c0 > THIN, y1 - y0 > THIN
  local side = R.solid and fill == SHADE and 1 or fill
  if la and lc and (cy > y1 or cy < y0) then
    local y = cy > y1 and y1 or y0
    corner(1, a0, c0, y)
    corner(2, a1, c0, y)
    corner(3, a1, c1, y)
    corner(4, a0, c1, y)
    face(fill, edge)
  end
  if lc and ly and (ca > a1 or ca < a0) then
    local a = ca > a1 and a1 or a0
    corner(1, a, c0, y0)
    corner(2, a, c1, y0)
    corner(3, a, c1, y1)
    corner(4, a, c0, y1)
    face(side, edge)
  end
  if la and ly and (cc > c1 or cc < c0) then
    local c = cc > c1 and c1 or c0
    corner(1, a0, c, y0)
    corner(2, a1, c, y0)
    corner(3, a1, c, y1)
    corner(4, a0, c, y1)
    face(side, edge)
  end
end

-- Parts in the order they hide each other: from above the wing and fin over the fuselage, from below the other way.
-- Arrays: [1..11] as a box's; [12], [13] x, z, [14], [15] sine and cosine of the heading, [16] height.
local function drawPlane(o, fogged)
  px, pz, ps, pc, py = o[12], o[13], o[14], o[15], o[16]
  local ox, oy, oz = R.cameraPos()
  local dx, dz = ox - px, oz - pz
  ca, cc, cy = dx * ps + dz * pc, dx * pc - dz * ps, oy
  local _, _, depth = R.toCamera(px, py + MID, pz)
  if fogged or depth > SOLID then
    local fill = R.solid and SHADE or 4
    part(1, fill)
    part(7, fill)
    return
  end
  local edge = not R.solid and EDGE
  if cy > py + 1.9 then
    part(1, SHADE, edge)
    part(13, SHADE, edge)
    if ca > WING_A then
      part(19, SHADE, edge)
      part(7, SHADE, edge)
    else
      part(7, SHADE, edge)
      part(19, SHADE, edge)
    end
  else
    part(19, SHADE, edge)
    part(7, SHADE, edge)
    part(13, SHADE, edge)
    part(1, SHADE, edge)
  end
end

-- Squared distance from x, y, z to the plane's nearest part
local function planeDistance2(o, x, y, z)
  local dx, dz = x - o[12], z - o[13]
  local s, c = o[14], o[15]
  local a, r, h = dx * s + dz * c, dx * c - dz * s, y - o[16]
  local best = 1e9
  for i = 1, #PARTS, 6 do
    local da = a < PARTS[i] and PARTS[i] - a or (a > PARTS[i + 1] and a - PARTS[i + 1] or 0)
    local dc = r < PARTS[i + 2] and PARTS[i + 2] - r or (r > PARTS[i + 3] and r - PARTS[i + 3] or 0)
    local dy = h < PARTS[i + 4] and PARTS[i + 4] - h or (h > PARTS[i + 5] and h - PARTS[i + 5] or 0)
    local d = da * da + dc * dc + dy * dy
    if d < best then
      best = d
    end
  end
  return best
end

-- Any part is a crash
local function planeCollides(o, x, y, z)
  return touches(o, x, y, z) and planeDistance2(o, x, y, z) < RADIUS * RADIUS
end

local function planeNear(o, x, y, z, d2)
  return distance2(o, x, y, z) < d2 and planeDistance2(o, x, y, z) < d2
end

-- stylua: ignore
local plane = scene.addObject(setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, SPHERE, 0, 0, 0, 1, 0, 0 },
  { __index = { draw = drawPlane, collides = planeCollides, near = planeNear } }))
-- Under its wings on the straights, moving with it; parked below the ground in the turns
local left = Gap.new("PLANE", 20, 0, 0, 0, 0, 1, 1)
local right = Gap.new("PLANE", 20, 0, 0, 0, 0, 1, 1)
gaps[#gaps + 1] = left
gaps[#gaps + 1] = right

-- Where the plane is: segment offset, distance round the lap, time left holding. It starts taxiing west in front of
-- the spawn, to hold and take off past it.
local seg = 80
local at, hold = SEG[seg + 1] + 40, 0

-- Moves the plane to its place: bounds ([1..6]), sphere centre ([7..9]), position, heading and height; and its gaps
local function place()
  local d = at - SEG[seg + 1]
  local x, z, h = along(SEG[seg + 2], SEG[seg + 3], SEG[seg + 4], SEG[seg + 6], d)
  local y = SEG[seg + 7] + (SEG[seg + 8] - SEG[seg + 7]) * d / SEG[seg + 5]
  local s, c = sin(h), cos(h)
  local ex, ez = HALF_L * abs(s) + HALF_S * abs(c), HALF_L * abs(c) + HALF_S * abs(s)
  plane[1], plane[2], plane[3], plane[4], plane[5], plane[6] = x - ex, y + 0.6, z - ez, x + ex, y + 3, z + ez
  plane[7], plane[8], plane[9] = x, y + MID, z
  plane[12], plane[13], plane[14], plane[15], plane[16] = x, z, s, c, y
  -- at, u0, u1 (y), v0, v1 (z): heading east or west, so the wings lie along z
  local gx, y0 = x + WING_A * s, y
  if SEG[seg + 6] ~= 0 then
    y0 = -50
  end
  left[2], left[3], left[4], left[5], left[6] = gx, y0, y0 + UNDER, z - OUT, z - IN
  right[2], right[3], right[4], right[5], right[6] = gx, y0, y0 + UNDER, z + IN, z + OUT
end
place()

-- Low trees and hedges round the field
local TREES = Ground.newRing({ 1, 1.5, 1, 2, 1.5, 1, 1, 2.5, 1.5, 1, 2, 1, 1.5, 1, 2, 1.5 })

-- Taxiway turns: a half circle of radius 10 in four chords, as x, z from the turn's centre
-- stylua: ignore
local ARC = { 0, -10, 7.07, -7.07, 10, 0, 7.07, 7.07, 0, 10 }
local MID_Z = (RWY_Z + TAXI_Z) / 2
local RX, RY, RZ =
  { -RWY_X, RWY_X, RWY_X, -RWY_X }, { 0, 0, 0, 0 }, { RWY_Z - RWY_W, RWY_Z - RWY_W, RWY_Z + RWY_W, RWY_Z + RWY_W }

-- Runway edges, ends and centre dashes (on colour over its tarmac), the taxiway's centre line
local function drawMarkings()
  local z0, z1 = RWY_Z - RWY_W, RWY_Z + RWY_W
  if R.solid then
    R.poly(RX, RY, RZ, 4, 3, true)
  end
  R.line(-RWY_X, 0, z0, RWY_X, 0, z0, 4)
  R.line(-RWY_X, 0, z1, RWY_X, 0, z1, 4)
  R.line(-RWY_X, 0, z0, -RWY_X, 0, z1, 4)
  R.line(RWY_X, 0, z0, RWY_X, 0, z1, 4)
  for x = 10 - RWY_X, RWY_X - 20, 20 do
    R.line(x, 0, RWY_Z, x + 8, 0, RWY_Z, 4)
  end
  R.line(TURN_W, 0, TAXI_Z, TURN_E, 0, TAXI_Z, 4)
  for i = 1, #ARC - 2, 2 do
    R.line(TURN_E + ARC[i], 0, MID_Z + ARC[i + 1], TURN_E + ARC[i + 2], 0, MID_Z + ARC[i + 3], 4)
    R.line(TURN_W - ARC[i], 0, MID_Z + ARC[i + 1], TURN_W - ARC[i + 2], 0, MID_Z + ARC[i + 3], 4)
  end
end

-- The scene sorts only every few frames and the plane moves fast: it is put in its place among the rest (far to
-- near, by their distances last frame) every frame
local objects = scene.objects
local function placePlane()
  local ox, _, oz = R.cameraPos()
  local dx, dz = plane[7] - ox, plane[9] - oz
  local d = dx * dx + dz * dz
  local i = 1
  while objects[i] ~= plane do
    i = i + 1
  end
  while i > 1 and objects[i - 1][11] < d do
    objects[i], i = objects[i - 1], i - 1
  end
  while i < #objects and objects[i + 1][11] > d do
    objects[i], i = objects[i + 1], i + 1
  end
  objects[i] = plane
end

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(TREES, Ground.horizon(quality))
  drawMarkings()
  Ground.drawPad(0, 0)
  placePlane()
  scene.draw(quality)
end

function Map.update(dt, _)
  gust = gust + dt
  if hold > 0 then
    hold = hold - dt
    return
  end
  at = at + (SEG[seg + 9] + (SEG[seg + 10] - SEG[seg + 9]) * (at - SEG[seg + 1]) / SEG[seg + 5]) * dt
  while at >= SEG[seg + 1] + SEG[seg + 5] do
    seg = seg + 10
    if seg >= #SEG then
      seg, at, hold = 0, 0, HOLD
    end
  end
  place()
end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 100 m of the apron (the runway ends 95 m out), lost at 190 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, -5, 35, 100, 190)
end

return Map
