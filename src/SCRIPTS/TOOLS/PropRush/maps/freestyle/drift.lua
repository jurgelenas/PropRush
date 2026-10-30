-- Drift: a car drifting laps of a small kerbed circuit, through a fast sweeper, a hairpin and a chicane, under a
-- start gantry, an advertising arch and through a tunnel, past a pit building and a grandstand. Chase it.

local Ground, Scene, Gap, R = ...

local sin, cos, sqrt, abs = math.sin, math.cos, math.sqrt, math.abs
local RAD = math.pi / 180
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15

local Map = {
  spawn = { x = 1.7, y = 0, z = 43.3, heading = 150 },
}

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Circuit, clockwise from the sweeper's start at 0, 20 heading north. Four numbers a segment: a straight's length,
-- 0, 0, 0; or an arc's radius, turn in degrees (+ right), the car's speed (m/s) and drift angle (degrees) on it.
-- The start straight's length closes the lap.
-- stylua: ignore
local TRACK = {
  25, 90, 17, 18, -- sweeper
  12, 0, 0, 0,
  9, 180, 8, 35, -- hairpin
  4, 0, 0, 0,
  10, -90, 9.5, 28,
  14, 0, 0, 0, -- back straight, through the tunnel
  12, -35, 12, 15, -- chicane
  12, 70, 12, 20,
  12, -35, 12, 15,
  6, 0, 0, 0,
  10, 90, 10, 25,
  3, 0, 0, 0,
  10, 90, 10, 25,
  0, 0, 0, 0, -- start straight
}
-- Road half width
local HALF = 4
-- Arcs' road edges in pieces of at most PIECE degrees
local PIECE = 30

-- From x, z heading h (radians) d metres along a segment of curvature k (1 / radius, + right)
local function along(x, z, h, k, d)
  if k == 0 then
    return x + d * sin(h), z + d * cos(h), h
  end
  local e = h + k * d
  return x + (cos(h) - cos(e)) / k, z + (sin(e) - sin(h)) / k, e
end

-- Segments, 8 numbers each from offset i: [i + 1] start distance, [i + 2..4] start x, z, heading, [i + 5] length,
-- [i + 6] curvature, [i + 7] speed on an arc (0 on a straight), [i + 8] drift angle (radians, signed as the turn)
local SEG = {}
-- Road edges as sections across it: left x, z, right x, z, the last one joined back to the first
local EDGE_PTS = {}
local LAP
do
  local x, z, h, s = 0, 20, 0, 0
  local function section()
    local c, n, e = cos(h), sin(h), #EDGE_PTS
    EDGE_PTS[e + 1], EDGE_PTS[e + 2], EDGE_PTS[e + 3], EDGE_PTS[e + 4] =
      x - HALF * c, z + HALF * n, x + HALF * c, z - HALF * n
  end
  for t = 1, #TRACK, 4 do
    local a, deg = TRACK[t], TRACK[t + 1]
    local len, k, pieces = a, 0, 1
    if deg ~= 0 then
      len, k, pieces = a * abs(deg) * RAD, (deg > 0 and 1 or -1) / a, math.ceil(abs(deg) / PIECE)
    elseif a == 0 then
      len = 20 - z
    end
    local i = #SEG
    SEG[i + 1], SEG[i + 2], SEG[i + 3], SEG[i + 4] = s, x, z, h
    SEG[i + 5], SEG[i + 6], SEG[i + 7], SEG[i + 8] = len, k, TRACK[t + 2], TRACK[t + 3] * RAD * (deg < 0 and -1 or 1)
    local x0, z0, h0 = x, z, h
    for p = 1, pieces do
      section()
      x, z, h = along(x0, z0, h0, k, len * p / pieces)
    end
    s = s + len
  end
  LAP = s
end

-- Car speed along straights: accelerating out of the last arc at ACCEL, braking for the next at BRAKE (m/s/s), at
-- most TOP m/s. The drift angle eases towards the segment's at SETTLE per second, so it builds in and unwinds.
local ACCEL, BRAKE, TOP, SETTLE = 7, 12, 24, 2.5

-- Speed d metres into the segment at offset i
local function speed(i, d)
  local v = SEG[i + 7]
  if v > 0 then
    return v
  end
  local n = #SEG
  local a, b = SEG[(i - 8) % n + 7], SEG[(i + 8) % n + 7]
  a, b = sqrt(a * a + 2 * ACCEL * d), sqrt(b * b + 2 * BRAKE * (SEG[i + 5] - d))
  v = a < b and a or b
  return v < TOP and v or TOP
end

-- Car: a low body HL x HW half length and width, BODY tall, under a cabin set back from the nose. Arrays: [1..11]
-- as a box's; [12], [13] x, z, [14], [15] sine and cosine of the body's yaw, [16] the travel heading, [17] the
-- drift angle.
local HL, HW, BODY = 2.25, 0.95, 0.8
-- Cabin: footprint at its base and its roof as front and rear (along the car) and half width, then the roof height
-- stylua: ignore
local CABIN = { 0.6, -1.5, 0.85, -0.1, -1, 0.7, 1.35 }
local H = CABIN[7]
-- Wheels: dark blocks WHEEL tall on the body's sides, centred AXLE along; on its ends WHEEL_W wide at the corners
local WHEEL, AXLE, WHEEL_L, WHEEL_W = 0.5, 1.4, 0.35, 0.4
-- Rear wing: a plate across the car WING_A along it, from WING_Y0 to WING_Y1 high
local WING_A, WING_Y0, WING_Y1 = -2.1, 0.95, 1.15
-- Drawn in full within SOLID metres (camera depth), else as a black silhouette
local SOLID = 30
-- Tyre smoke from the rear wheels, while drifting over SMOKE radians
local SMOKE, PUFF = 12 * RAD, 2.5

-- The car being drawn: centre, yaw; the camera along and across it, and its height
local cx, cz, sb, cb, ca, cc, cy
-- Corners of a solid in world x, z, base 1..4, top 5..8, round it from front right: front right, rear right, rear
-- left, front left; side i runs from corner i to the next: right, rear, left, front. In camera space QX, QY, QZ.
local PX, PZ = {}, {}
local QX, QY, QZ = {}, {}, {}
for i = 1, 8 do
  PX[i], PZ[i], QX[i], QY[i], QZ[i] = 0, 0, 0, 0, 0
end
local SIDE = { false, false, false, false }
local WX, WY, WZ = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

-- Point a along the car and c across it (+ right) to world x, z
local function world(a, c)
  return cx + a * sb + c * cb, cz + a * cb - c * sb
end

-- Upright dark plate on the car from a0, c0 to a1, c1 (local), y0 to y1 high
local function plate(a0, c0, a1, c1, y0, y1)
  local x0, z0 = world(a0, c0)
  local x1, z1 = world(a1, c1)
  WX[1], WY[1], WZ[1], WX[2], WY[2], WZ[2] = x0, y0, z0, x1, y0, z1
  WX[3], WY[3], WZ[3], WX[4], WY[4], WZ[4] = x1, y1, z1, x0, y1, z0
  R.poly(WX, WY, WZ, 4, 4, true)
end

-- Solid from y0 to y1, its base front, rear, half width f0, r0, w0 and top f1, r1, w1 (local); its faces seen filled
-- with shade fill (false: none), then their edges (edge nil: none)
local function hull(f0, r0, w0, f1, r1, w1, y0, y1, fill, edge)
  for i = 1, 4 do
    local front, right = i == 1 or i == 4, i <= 2
    local x, z = world(front and f0 or r0, right and w0 or -w0)
    PX[i], PZ[i] = x, z
    QX[i], QY[i], QZ[i] = R.toCamera(x, y0, z)
    x, z = world(front and f1 or r1, right and w1 or -w1)
    PX[i + 4], PZ[i + 4] = x, z
    QX[i + 4], QY[i + 4], QZ[i + 4] = R.toCamera(x, y1, z)
  end
  -- A side faces the camera when it lies beyond the side's plane: its slope from the plane's base edge (along the
  -- car for the ends, across it for the sides) against the camera's
  local h = y1 - y0
  SIDE[1] = (cc - w0) * h > (w1 - w0) * (cy - y0)
  SIDE[3] = (-cc - w0) * h > (w1 - w0) * (cy - y0)
  SIDE[2] = (-ca + r0) * h > (r0 - r1) * (cy - y0)
  SIDE[4] = (ca - f0) * h > (f1 - f0) * (cy - y0)
  local top = cy > y1
  if fill then
    for i = 1, 4 do
      if SIDE[i] then
        local j = i % 4 + 1
        WX[1], WY[1], WZ[1] = PX[i], y0, PZ[i]
        WX[2], WY[2], WZ[2] = PX[j], y0, PZ[j]
        WX[3], WY[3], WZ[3] = PX[j + 4], y1, PZ[j + 4]
        WX[4], WY[4], WZ[4] = PX[i + 4], y1, PZ[i + 4]
        R.poly(WX, WY, WZ, 4, fill, true)
      end
    end
    if top then
      for i = 1, 4 do
        WX[i], WY[i], WZ[i] = PX[i + 4], y1, PZ[i + 4]
      end
      R.poly(WX, WY, WZ, 4, fill, true)
    end
  end
  if not edge then
    return
  end
  local camLine = R.camLine
  for i = 1, 4 do
    local j, p = i % 4 + 1, (i + 2) % 4 + 1
    if SIDE[i] then
      camLine(QX[i], QY[i], QZ[i], QX[j], QY[j], QZ[j], edge)
    end
    if SIDE[i] or top then
      camLine(QX[i + 4], QY[i + 4], QZ[i + 4], QX[j + 4], QY[j + 4], QZ[j + 4], edge)
    end
    if SIDE[i] or SIDE[p] then
      camLine(QX[i], QY[i], QZ[i], QX[i + 4], QY[i + 4], QZ[i + 4], edge)
    end
  end
end

-- Wheels on the body's sides seen, drawn just outside them
local function wheels()
  local w, l, d = HW + 0.02, HL + 0.02, WHEEL_W / 2
  for k = -1, 1, 2 do
    local a, c = k * AXLE, k * (HW - d)
    if SIDE[1] then
      plate(a - WHEEL_L, w, a + WHEEL_L, w, 0, WHEEL)
    end
    if SIDE[3] then
      plate(a - WHEEL_L, -w, a + WHEEL_L, -w, 0, WHEEL)
    end
    if SIDE[2] then
      plate(-l, c - d, -l, c + d, 0, WHEEL)
    end
    if SIDE[4] then
      plate(l, c - d, l, c + d, 0, WHEEL)
    end
  end
end

local function wing()
  plate(WING_A, -HW, WING_A, HW, WING_Y0, WING_Y1)
end

local function drawSmoke(o)
  local bx, bz = -PUFF * sin(o[16]), -PUFF * cos(o[16])
  for k = -1, 1, 2 do
    local wx, wz = world(-AXLE, k * HW)
    R.line(wx, 0.2, wz, wx + bx, 1, wz + bz, FAR_EDGE)
  end
end

-- Body, its wheels, then the cabin and wing in the order they hide each other from the camera
local function drawCar(o, fogged)
  cx, cz, sb, cb = o[12], o[13], o[14], o[15]
  local ox, oy, oz = R.cameraPos()
  local dx, dz = ox - cx, oz - cz
  ca, cc, cy = dx * sb + dz * cb, dx * cb - dz * sb, oy
  local _, _, depth = R.toCamera(cx, 0, cz)
  if fogged then
    hull(HL, -HL, HW, HL, -HL, HW, 0, BODY, false, FAR_EDGE)
    return
  elseif depth > SOLID then
    -- A few pixels across: solid black, so it stands out from the road's lines; its outline keeps it when under a pixel
    hull(HL, -HL, HW, HL, -HL, HW, 0, BODY, 4, EDGE)
    hull(CABIN[1], CABIN[2], CABIN[3], CABIN[4], CABIN[5], CABIN[6], BODY, H, 4)
    return
  end
  local smoky = abs(o[17]) > SMOKE
  if smoky and ca > 0 then
    drawSmoke(o)
  end
  hull(HL, -HL, HW, HL, -HL, HW, 0, BODY, SHADE, EDGE)
  wheels()
  if ca > 0 then
    wing()
  end
  hull(CABIN[1], CABIN[2], CABIN[3], CABIN[4], CABIN[5], CABIN[6], BODY, H, SHADE, EDGE)
  if ca <= 0 then
    wing()
    if smoky then
      drawSmoke(o)
    end
  end
end

-- x, z in the car's frame: along it and across it, from its faces (negative inside)
local function local2(o, x, z)
  local dx, dz = x - o[12], z - o[13]
  local sb, cb = o[14], o[15]
  return abs(dx * sb + dz * cb) - HL, abs(dx * cb - dz * sb) - HW
end

-- A crash anywhere on the body
local function carCollides(o, x, y, z)
  if not touches(o, x, y, z) or y > H + RADIUS then
    return false
  end
  local a, c = local2(o, x, z)
  return a < RADIUS and c < RADIUS
end

local function carNear(o, x, y, z, d2)
  if distance2(o, x, y, z) >= d2 then
    return false
  end
  local a, c = local2(o, x, z)
  local dy = y - H
  a, c, dy = a > 0 and a or 0, c > 0 and c or 0, dy > 0 and dy or 0
  return a * a + c * c + dy * dy < d2
end

-- stylua: ignore
local car = scene.addObject(setmetatable({ 0, 0, 0, 0, H, 0, 0, H / 2, 0, sqrt(4 * HL * HL + 4 * HW * HW + H * H) / 2,
  0, 0, 0, 0, 1, 0, 0 }, { __index = { draw = drawCar, collides = carCollides, near = carNear } }))

-- Where the car is: segment offset, distance round the lap, drift angle. It starts 25 m up the start straight, in
-- view of the spawn and into the sweeper past it in two seconds.
local seg = #SEG - 8
local at, drift = SEG[seg + 1] + 25, 0

-- Moves the car to its place: position, yaw and bounds ([1], [3], [4], [6]) and sphere centre ([7], [9])
local function place()
  local x, z, h = along(SEG[seg + 2], SEG[seg + 3], SEG[seg + 4], SEG[seg + 6], at - SEG[seg + 1])
  local b = h + drift
  local sb, cb = sin(b), cos(b)
  local as, ac = abs(sb), abs(cb)
  local ex, ez = HL * as + HW * ac, HL * ac + HW * as
  car[1], car[3], car[4], car[6], car[7], car[9] = x - ex, z - ez, x + ex, z + ez, x, z
  car[12], car[13], car[14], car[15], car[16], car[17] = x, z, sb, cb, h, drift
end
place()

-- Start gantry low over the start straight
local GZ, LOW = 0, 3.5
local gantry = scene.addStructure()
gantry:add(-6, GZ, 0.6, 0.6, LOW, 0)
gantry:add(6, GZ, 0.6, 0.6, LOW, 0)
gantry:add(0, GZ, 12.6, 1.2, 0.8, LOW)
gaps[#gaps + 1] = Gap.new("GANTRY", 15, -5.7, 0, GZ, 5.7, LOW - 0.1, GZ)

-- Tunnel over the back straight, flown into from the north as the car goes
local TX, TZ, TL, ROOF = 23, 10, 10, 4.5
local tunnel = scene.addStructure()
tunnel:add(TX - 5.3, TZ, 0.6, TL, ROOF, 0)
tunnel:add(TX + 5.3, TZ, 0.6, TL, ROOF, 0)
tunnel:add(TX, TZ, 11.2, TL, 0.8, ROOF)
gaps[#gaps + 1] = Gap.new("TUNNEL", 20, TX - 5, 0, TZ + TL / 2, TX + 5, ROOF - 0.1, TZ + TL / 2)

-- Advertising board on two posts over the straight into the hairpin
local AX, AZ, BOARD = 31, 45, 4.5
local arch = scene.addStructure()
arch:add(AX, AZ - 5.6, 0.4, 0.4, BOARD, 0)
arch:add(AX, AZ + 5.6, 0.4, 0.4, BOARD, 0)
arch:add(AX, AZ, 0.3, 11.6, 1.6, BOARD)
gaps[#gaps + 1] = Gap.new("BOARD", 10, AX, 0, AZ - 5.3, AX, BOARD - 0.1, AZ + 5.3)

-- Pit building by the start straight, a garage open through it from the pit lane
local PITX, PITZ = -10, -5
local pit = scene.addStructure()
pit:add(PITX, PITZ - 6, 6, 8, 4, 0)
pit:add(PITX, PITZ + 6, 6, 8, 4, 0)
pit:add(PITX, PITZ, 6, 4, 1, 3)
gaps[#gaps + 1] = Gap.new("GARAGE", 15, PITX, 0, PITZ - 1.9, PITX, 2.9, PITZ + 1.9)

-- Grandstand stepping up behind the hairpin
scene.addBox(54, 36, 4, 20, 2.5)
scene.addBox(58, 36, 4, 20, 5)

-- Trees round the circuit
local TREES = Ground.newRing({ 1, 1.5, 2, 1, 1.5, 2.5, 1, 1, 2, 1.5, 1, 2, 3, 1.5, 1, 1.5 })

-- Road edges within ROAD_DIST of the camera, a piece at a time, and the start line under the gantry
local ROAD_DIST = { 80, 110, 140 }
local function drawRoad(quality)
  local ox, _, oz = R.cameraPos()
  local far = ROAD_DIST[quality]
  local n = #EDGE_PTS
  local plx, plz, prx, prz = EDGE_PTS[n - 3], EDGE_PTS[n - 2], EDGE_PTS[n - 1], EDGE_PTS[n]
  for i = 1, n, 4 do
    local lx, lz, rx, rz = EDGE_PTS[i], EDGE_PTS[i + 1], EDGE_PTS[i + 2], EDGE_PTS[i + 3]
    local mx, mz = (lx + rx + plx + prx) / 4, (lz + rz + plz + prz) / 4
    local dx, dz = (lx + rx - plx - prx) / 2, (lz + rz - plz - prz) / 2
    -- Half the centre line's length and the half width, and a metre for the outer edge's longer chord
    local r = sqrt(dx * dx + dz * dz) / 2 + HALF + 1
    dx, dz = mx - ox, mz - oz
    if dx * dx + dz * dz < (far + r) * (far + r) and R.sphereVisible(mx, 0, mz, r) then
      R.line(plx, 0, plz, lx, 0, lz, 4)
      R.line(prx, 0, prz, rx, 0, rz, 4)
    end
    plx, plz, prx, prz = lx, lz, rx, rz
  end
  R.line(-HALF, 0, GZ, HALF, 0, GZ, 4)
end

-- The scene sorts only every few frames and the car moves fast: it is put in its place among the rest (far to near,
-- by their distances last frame) every frame, so a building it has passed in front of never covers it
local objects = scene.objects
local function placeCar()
  local ox, _, oz = R.cameraPos()
  local dx, dz = car[7] - ox, car[9] - oz
  local d = dx * dx + dz * dz
  local i = 1
  while objects[i] ~= car do
    i = i + 1
  end
  while i > 1 and objects[i - 1][11] < d do
    objects[i], i = objects[i - 1], i - 1
  end
  while i < #objects and objects[i + 1][11] > d do
    objects[i], i = objects[i + 1], i + 1
  end
  objects[i] = car
end

function Map.draw(quality)
  Ground.drawRing(TREES, Ground.horizon(quality))
  drawRoad(quality)
  Ground.drawPad(Map.spawn.x, Map.spawn.z)
  placeCar()
  scene.draw(quality)
end

function Map.update(dt, _)
  at = at + speed(seg, at - SEG[seg + 1]) * dt
  while at >= SEG[seg + 1] + SEG[seg + 5] do
    seg = seg + 8
    if seg >= #SEG then
      seg, at = 0, at - LAP
    end
  end
  local target = SEG[seg + 6] ~= 0 and SEG[seg + 8] or 0
  local k = SETTLE * dt
  drift = drift + (target - drift) * (k < 1 and k or 1)
  place()
end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 90 m of the circuit's middle (the grandstand is 50 m out), lost at 180 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 23, 2, 90, 180)
end

return Map
