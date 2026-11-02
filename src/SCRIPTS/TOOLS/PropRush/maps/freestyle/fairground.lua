-- Fairground: a travelling fair behind an entrance arch. Stalls down the midway, a carousel, a big top with a king
-- pole between its doors, a big wheel turning slowly at the end of the midway, a drop tower, and a lattice roller
-- coaster along the east side with a lift hill, a loop, a camelback and a spike.

local Ground, Scene, Gap, R = ...

local sqrt, sin, cos = math.sqrt, math.sin, math.cos
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_SHADE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_SHADE, Scene.FAR_EDGE
local camLine, toCamera, camVector = R.camLine, R.toCamera, R.camVector
-- The quad's collision radius, as the scene's
local RADIUS = 0.15
local BAR_PX = 3
local TURN = 2 * math.pi

local Map = {
  spawn = { x = 0, y = 0, z = 0, heading = 0 },
}

local GRID = 60

local scene = Scene.new()
Map.scene = scene
-- Openings that score in freestyle
local gaps = {}
Map.gaps = gaps

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }
local function setBox(x0, y0, z0, x1, y1, z1)
  BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] = x0, y0, z0, x1, y1, z1
  return BOX
end

-- Scene object slots [1..11] round x0, y0, z0 .. x1, y1, z1: bounds, then the sphere's centre and radius
local function newObject(x0, y0, z0, x1, y1, z1, methods)
  local w, h, d = x1 - x0, y1 - y0, z1 - z0
  return scene.addObject(setmetatable({
    x0,
    y0,
    z0,
    x1,
    y1,
    z1,
    x0 + w / 2,
    y0 + h / 2,
    z0 + d / 2,
    sqrt(w * w + h * h + d * d) / 2,
    0,
  }, methods))
end

-- Squared distance from px, py to the segment a..b, and its closest point
local function segment2(px, py, ax, ay, bx, by)
  local sx, sy = bx - ax, by - ay
  local t = ((px - ax) * sx + (py - ay) * sy) / (sx * sx + sy * sy)
  t = t < 0 and 0 or t > 1 and 1 or t
  local cx, cy = ax + sx * t, ay + sy * t
  return (px - cx) * (px - cx) + (py - cy) * (py - cy), cx, cy
end

-- Entrance arch over the midway
local arch = scene.addStructure()
arch:add(-4.5, 20, 1, 1, 6, 0)
arch:add(4.5, 20, 1, 1, 6, 0)
arch:add(0, 20, 11, 1, 2, 6)
gaps[#gaps + 1] = Gap.new("ENTRANCE", 10, -4, 0, 20, 4, 6, 20)

-- Stalls: two west of the midway with a 2.4 m slot between them, one east of it
scene.addBox(-9, 31.8, 4, 4, 2.6)
scene.addBox(-9, 38.2, 4, 4, 2.6)
gaps[#gaps + 1] = Gap.new("STALLS", 15, -11, 0, 35, -7, 2.6, 35)
scene.addBox(9, 34, 3, 8, 2.6)

-- Carousel: a canopy on its centre pole over the platform, flown under either side of the pole
local CX, CZ, CAN = -12, 56, 3.5
local carousel = scene.addStructure()
carousel:add(CX, CZ, 8, 8, 0.4, 0)
carousel:add(CX, CZ, 0.6, 0.6, CAN - 0.4, 0.4)
carousel:add(CX, CZ, 8.4, 8.4, 0.5, CAN)
carousel:add(CX, CZ, 3, 3, 1.5, CAN + 0.5)
gaps[#gaps + 1] = Gap.new("CAROUSEL", 10, CX + 0.5, 0.4, CZ, CX + 4, CAN, CZ)
gaps[#gaps + 1] = Gap.new("CAROUSEL", 10, CX - 4, 0.4, CZ, CX - 0.5, CAN, CZ)

-- Big top 18 m square: walls with a 4 m door south and north, the king pole between the doors, the roof stepping in
-- to the mast
local TX, TZ, HALF, DOOR, WALL_H = -34, 45, 9, 2, 5
local tent = scene.addStructure()
for s = -1, 1, 2 do
  local z = TZ + s * HALF
  tent:add(TX - (HALF + DOOR) / 2, z, HALF - DOOR, 0.4, WALL_H, 0)
  tent:add(TX + (HALF + DOOR) / 2, z, HALF - DOOR, 0.4, WALL_H, 0)
  tent:add(TX + s * HALF, TZ, 0.4, 2 * HALF, WALL_H, 0)
  gaps[#gaps + 1] = Gap.new("BIG TOP", 10, TX - DOOR + 0.1, 0, z, TX + DOOR - 0.1, WALL_H, z)
end
tent:add(TX, TZ, 0.6, 0.6, WALL_H, 0)
tent:add(TX, TZ, 2 * HALF + 1, 2 * HALF + 1, 1.5, WALL_H)
tent:add(TX, TZ, 13, 13, 2, WALL_H + 1.5)
tent:add(TX, TZ, 7, 7, 1.5, WALL_H + 3.5)
tent:add(TX, TZ, 0.3, 0.3, 4, WALL_H + 5)

-- Big wheel facing south: six spokes and a rim turning between two A-frames, a gondola hanging from the rim at each
-- spoke. The disc scores above and below the hub, through rectangles inside it.
local WX, WZ, HUB, RIM, SPOKES = 0, 75, 15, 11, 6
-- A-frame legs LEG_X out either side at the ground, LEG_Z in front of and behind the disc, LEG_T half thick
local LEG_X, LEG_Z, LEG_T, AXLE = 6, 1.6, 0.2, 0.8
-- Disc half thick, gondola half size; rim chords, fewer and no gondolas beyond DISC_DIST (camera depth)
local DISC_T, GON, RIM_SEG, DISC_DIST = 0.25, 0.7, 18, 40
-- About 1.4 rpm
local SPIN, STEP = 0.15, TURN / SPOKES
local angle = 0
scene.addBox(WX, WZ, 5, 3, 0.8)
local u, v = 0.6 * RIM, 0.75 * RIM
gaps[#gaps + 1] = Gap.new("WHEEL", 20, WX - u, HUB - v, WZ, WX + u, HUB - 1.5, WZ)
gaps[#gaps + 1] = Gap.new("WHEEL", 20, WX - u, HUB + 1.5, WZ, WX + u, HUB + v, WZ)

-- Leg joints: feet south, feet north, then the axle ends south and north, and a brace across each A-frame 4 m up
local BRACE = LEG_X * (1 - 4 / HUB)
-- stylua: ignore
local LX = { WX - LEG_X, WX + LEG_X, WX - LEG_X, WX + LEG_X, WX, WX, WX - BRACE, WX + BRACE, WX - BRACE, WX + BRACE }
local LY = { 0, 0, 0, 0, HUB, HUB, 4, 4, 4, 4 }
-- stylua: ignore
local LZ = { WZ - LEG_Z, WZ - LEG_Z, WZ + LEG_Z, WZ + LEG_Z, WZ - LEG_Z, WZ + LEG_Z,
  WZ - LEG_Z, WZ - LEG_Z, WZ + LEG_Z, WZ + LEG_Z }
local SOUTH_LEGS, NORTH_LEGS = { 1, 5, 2, 5, 7, 8 }, { 3, 6, 4, 6, 9, 10 }

local function hubBox()
  return setBox(WX - AXLE, HUB - AXLE, WZ - LEG_Z - 0.2, WX + AXLE, HUB + AXLE, WZ + LEG_Z + 0.2)
end

-- Gondola k into BOX, hanging under its pin on the rim
local function gondola(k)
  local a = angle + k * STEP
  local px, py = WX + RIM * cos(a), HUB + RIM * sin(a)
  return setBox(px - GON, py - 2 * GON, WZ - GON, px + GON, py, WZ + GON)
end

-- Rim and spokes in camera space from the hub along the disc's plane, the gondolas as boxes
local function drawDisc(edge, shade)
  local hx, hy, hz = toCamera(WX, HUB, WZ)
  local ax, ay, az = camVector(1, 0, 0)
  local bx, by, bz = camVector(0, 1, 0)
  local near = hz < DISC_DIST
  local seg = near and RIM_SEG or RIM_SEG * 2 // 3
  local px, py, pz
  for k = 0, seg do
    local a = angle + k * TURN / seg
    local c, s = RIM * cos(a), RIM * sin(a)
    local x, y, z = hx + ax * c + bx * s, hy + ay * c + by * s, hz + az * c + bz * s
    if k > 0 then
      camLine(px, py, pz, x, y, z, edge)
    end
    if k % (seg // SPOKES) == 0 and k < seg then
      camLine(hx, hy, hz, x, y, z, edge)
    end
    px, py, pz = x, y, z
  end
  if near then
    for k = 0, SPOKES - 1 do
      local b = gondola(k)
      R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
    end
  end
end

-- The A-frame on the camera's side last
local function drawWheel(_, fogged)
  local shade, edge = fogged and FAR_SHADE or SHADE, fogged and FAR_EDGE or EDGE
  local _, _, oz = R.cameraPos()
  local south = oz < WZ
  R.frame(LX, LY, LZ, south and NORTH_LEGS or SOUTH_LEGS, LEG_T, 3, edge)
  local b = hubBox()
  R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
  drawDisc(edge, shade)
  R.frame(LX, LY, LZ, south and SOUTH_LEGS or NORTH_LEGS, LEG_T, 3, edge)
end

-- Legs and hub as boxes; rim, spokes and gondolas are a crash, as they move
local function wheelCollides(o, x, y, z)
  if not touches(o, x, y, z) then
    return false
  end
  local b = hubBox()
  if touches(b, x, y, z) then
    return b
  end
  local reach = LEG_T + RADIUS
  for s = -1, 1, 2 do
    local zl = WZ + s * LEG_Z
    if z > zl - reach and z < zl + reach then
      for k = -1, 1, 2 do
        local d2, cx, cy = segment2(x, y, WX + k * LEG_X, 0, WX, HUB)
        if d2 < reach * reach then
          return setBox(cx - LEG_T, cy - LEG_T, zl - LEG_T, cx + LEG_T, cy + LEG_T, zl + LEG_T)
        end
      end
    end
  end
  local dz = z - WZ
  if dz > GON + RADIUS or dz < -GON - RADIUS then
    return false
  end
  for k = 0, SPOKES - 1 do
    if touches(gondola(k), x, y, z) then
      return true
    end
  end
  if dz > DISC_T + RADIUS or dz < -DISC_T - RADIUS then
    return false
  end
  local dx, dy = x - WX, y - HUB
  local r = sqrt(dx * dx + dy * dy) - RIM
  if r < DISC_T + RADIUS and r > -DISC_T - RADIUS then
    return true
  end
  for k = 0, SPOKES - 1 do
    local a = angle + k * STEP
    local c, s = cos(a), sin(a)
    local along, across = dx * c + dy * s, dy * c - dx * s
    if along > 0 and along < RIM and across < DISC_T + RADIUS and across > -DISC_T - RADIUS then
      return true
    end
  end
  return false
end

-- Near the hub, a leg, or the disc the gondolas sweep
local function wheelNear(o, x, y, z, d2)
  if distance2(o, x, y, z) >= d2 then
    return false
  end
  if distance2(hubBox(), x, y, z) < d2 then
    return true
  end
  for s = -1, 1, 2 do
    local dz = z - WZ - s * LEG_Z
    for k = -1, 1, 2 do
      if segment2(x, y, WX + k * LEG_X, 0, WX, HUB) + dz * dz < d2 then
        return true
      end
    end
  end
  local dz = z - WZ
  dz = (dz < 0 and -dz or dz) - GON
  local dx, dy = x - WX, y - HUB
  local r = sqrt(dx * dx + dy * dy) - RIM
  dz, r = dz > 0 and dz or 0, r > 0 and r or 0
  return dz * dz + r * r < d2
end

newObject(
  WX - RIM - GON,
  0,
  WZ - LEG_Z - LEG_T,
  WX + RIM + GON,
  HUB + RIM + DISC_T,
  WZ + LEG_Z + LEG_T,
  { __index = { draw = drawWheel, collides = wheelCollides, near = wheelNear } }
)

-- Drop tower: a car round the mast climbs slowly, holds at the top, falls free and brakes near the ground
local DX, DZ, MAST, MAST_W, CAR_W, CAR_H = -22, 86, 30, 0.8, 2.2, 1.2
local LOW, HIGH, BRAKE, CLIMB, G = 1, 26, 9, 2.5, 9.8
local T_CLIMB = (HIGH - LOW) / CLIMB
local T_HOLD = T_CLIMB + 3
local T_FALL = T_HOLD + sqrt(2 * (HIGH - BRAKE) / G)
local V_FALL = G * (T_FALL - T_HOLD)
local T_BRAKE = T_FALL + 2 * (BRAKE - LOW) / V_FALL
local CYCLE = T_BRAKE + 5
local drop, carY = 0, LOW

local function carBox()
  return setBox(DX - CAR_W, carY, DZ - CAR_W, DX + CAR_W, carY + CAR_H, DZ + CAR_W)
end

local function capBox()
  return setBox(DX - 1.4, MAST, DZ - 1.4, DX + 1.4, MAST + 1.2, DZ + 1.4)
end

local function drawMast(y0, y1, shade, edge)
  if not R.bar(DX, DZ, y0, y1, MAST_W, BAR_PX, edge) then
    R.box(DX - MAST_W, y0, DZ - MAST_W, DX + MAST_W, y1, DZ + MAST_W, shade, edge)
  end
end

-- The mast in two parts either side of the car, the part on the camera's side last
local function drawTower(_, fogged)
  local shade, edge = fogged and FAR_SHADE or SHADE, fogged and FAR_EDGE or EDGE
  local _, oy = R.cameraPos()
  local b
  if oy > carY then
    drawMast(0, carY, shade, edge)
    b = carBox()
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
    drawMast(carY + CAR_H, MAST, shade, edge)
    b = capBox()
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
  else
    b = capBox()
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
    drawMast(carY + CAR_H, MAST, shade, edge)
    b = carBox()
    R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
    drawMast(0, carY, shade, edge)
  end
end

local function towerCollides(o, x, y, z)
  if not touches(o, x, y, z) then
    return false
  end
  local b = carBox()
  if touches(b, x, y, z) then
    return b
  end
  b = capBox()
  if touches(b, x, y, z) then
    return b
  end
  b = setBox(DX - MAST_W, 0, DZ - MAST_W, DX + MAST_W, MAST, DZ + MAST_W)
  return touches(b, x, y, z) and b
end

local function towerNear(o, x, y, z, d2)
  return distance2(o, x, y, z) < d2
    and (
      distance2(carBox(), x, y, z) < d2
      or distance2(capBox(), x, y, z) < d2
      or distance2(setBox(DX - MAST_W, 0, DZ - MAST_W, DX + MAST_W, MAST, DZ + MAST_W), x, y, z) < d2
    )
end

newObject(
  DX - CAR_W,
  0,
  DZ - CAR_W,
  DX + CAR_W,
  MAST + 1.2,
  DZ + CAR_W,
  { __index = { draw = drawTower, collides = towerCollides, near = towerNear } }
)

-- Roller coaster along z at x = KX: the track's centreline through points z, y, rails RAIL either side, the spine
-- SPINE under it (outside the loop), drawn as a lattice within LATTICE_DIST (camera depth), as one line beyond
-- RAILS_DIST. Station, lift hill,
-- crest, drop, the loop, a camelback and a spike the train runs back from.
local KX, RAIL, SPINE, TUBE, LATTICE_DIST, RAILS_DIST = 28, 0.6, 0.6, 0.65, 25, 60
local LOOP_Z, LOOP_Y, LOOP_R, LOOP_SEG = 62, 7.2, 6, 12
local KZ, KY = {}, {}
local function point(z, y)
  KZ[#KZ + 1], KY[#KY + 1] = z, y
end
-- stylua: ignore
local RUN = { 8, 1.2, 18, 1.2, 34, 16, 36.5, 17, 39.5, 17, 42, 16, 52, 3, 55, 1.5, 58, 1.2 }
for i = 1, #RUN, 2 do
  point(RUN[i], RUN[i + 1])
end
for k = 0, LOOP_SEG do
  local a = -math.pi / 2 + k * TURN / LOOP_SEG
  point(LOOP_Z + LOOP_R * cos(a), LOOP_Y + LOOP_R * sin(a))
end
-- stylua: ignore
RUN = { 66, 1.2, 73, 7.5, 76, 8.5, 79, 8.5, 82, 7.5, 88, 1.5, 91, 1.2, 101, 21 }
for i = 1, #RUN, 2 do
  point(RUN[i], RUN[i + 1])
end
-- Lattice towers under the track as z, top: legs LEG_BASE (half) apart on the ground
local LEG_BASE = 1.4
local POSTS = { 30, 0, 44, 0, 77.5, 0, 96, 0, 101, 0 }
for i = 1, #POSTS, 2 do
  local z = POSTS[i]
  for k = 1, #KZ - 1 do
    if KZ[k] <= z and KZ[k + 1] >= z and POSTS[i + 1] == 0 then
      POSTS[i + 1] = KY[k] + (KY[k + 1] - KY[k]) * (z - KZ[k]) / (KZ[k + 1] - KZ[k]) - SPINE
    end
  end
end
gaps[#gaps + 1] = Gap.new("LOOP", 25, KX, LOOP_Y - 3.6, LOOP_Z - 3.6, KX, LOOP_Y + 3.6, LOOP_Z + 3.6)
gaps[#gaps + 1] = Gap.new("HILL", 10, KX, 0, 31, KX, 10, 43)

-- Half width of tower i's legs at height y
local function postHalf(i, y)
  return LEG_BASE + (RAIL - LEG_BASE) * y / POSTS[i + 1]
end

local function drawPosts(edge, lattice)
  for i = 1, #POSTS, 2 do
    local z, top = POSTS[i], POSTS[i + 1]
    R.line(KX - LEG_BASE, 0, z, KX - RAIL, top, z, edge)
    R.line(KX + LEG_BASE, 0, z, KX + RAIL, top, z, edge)
    if lattice then
      for y = 4, top - 1, 4 do
        local w = postHalf(i, y)
        R.line(KX - w, y, z, KX + w, y, z, edge)
      end
    end
  end
end

-- Rails, one line far off; near the camera ties across and the spine under them, braced to the rails at every
-- other point
local function drawCoaster(_, fogged)
  local edge = fogged and FAR_EDGE or EDGE
  local sx, sy, sz = camVector(RAIL, 0, 0)
  local n = #KZ
  local mx, my, mz, lx, ly, lz, rx, ry, rz, px, py, pz
  for i = 1, n do
    local cx, cy, cz = toCamera(KX, KY[i], KZ[i])
    local ax, ay, az, bx, by, bz = cx - sx, cy - sy, cz - sz, cx + sx, cy + sy, cz + sz
    if i > 1 then
      if fogged or cz > RAILS_DIST and mz > RAILS_DIST then
        camLine(mx, my, mz, cx, cy, cz, edge)
      else
        camLine(lx, ly, lz, ax, ay, az, edge)
        camLine(rx, ry, rz, bx, by, bz, edge)
      end
    end
    if not fogged and cz < LATTICE_DIST then
      local i0, i1 = i > 1 and i - 1 or i, i < n and i + 1 or i
      local tz, ty = KZ[i1] - KZ[i0], KY[i1] - KY[i0]
      local f = SPINE / sqrt(tz * tz + ty * ty)
      local dx, dy, dz = camVector(0, -tz * f, ty * f)
      dx, dy, dz = cx + dx, cy + dy, cz + dz
      camLine(ax, ay, az, bx, by, bz, edge)
      if i % 2 == 0 then
        camLine(ax, ay, az, dx, dy, dz, edge)
        camLine(bx, by, bz, dx, dy, dz, edge)
      end
      if px then
        camLine(px, py, pz, dx, dy, dz, edge)
      end
      px, py, pz = dx, dy, dz
    else
      px = nil
    end
    mx, my, mz, lx, ly, lz, rx, ry, rz = cx, cy, cz, ax, ay, az, bx, by, bz
  end
  drawPosts(edge, not fogged)
end

-- The track as a tube round its centreline, the towers as solid
local function coasterCollides(o, x, y, z)
  if not touches(o, x, y, z) then
    return false
  end
  local dx = x - KX
  for i = 1, #POSTS, 2 do
    local pz, top = POSTS[i], POSTS[i + 1]
    if z > pz - 0.3 - RADIUS and z < pz + 0.3 + RADIUS and y < top + RADIUS then
      local w = postHalf(i, y < top and y or top)
      if dx < w + RADIUS and dx > -w - RADIUS then
        return setBox(KX - w, 0, pz - 0.3, KX + w, top, pz + 0.3)
      end
    end
  end
  if dx > RAIL + RADIUS or dx < -RAIL - RADIUS then
    return false
  end
  local reach = (TUBE + RADIUS) * (TUBE + RADIUS)
  for i = 1, #KZ - 1 do
    local d2, cz, cy = segment2(z, y, KZ[i], KY[i], KZ[i + 1], KY[i + 1])
    if d2 < reach then
      return setBox(KX - RAIL, cy - TUBE, cz - TUBE, KX + RAIL, cy + TUBE, cz + TUBE)
    end
  end
  return false
end

local function coasterNear(o, x, y, z, d2)
  if distance2(o, x, y, z) >= d2 then
    return false
  end
  local dx = x - KX
  dx = (dx < 0 and -dx or dx) - RAIL
  dx = dx > 0 and dx * dx or 0
  for i = 1, #KZ - 1 do
    local r = sqrt(segment2(z, y, KZ[i], KY[i], KZ[i + 1], KY[i + 1])) - TUBE
    if dx + (r > 0 and r * r or 0) < d2 then
      return true
    end
  end
  for i = 1, #POSTS, 2 do
    if
      distance2(setBox(KX - LEG_BASE, 0, POSTS[i] - 0.3, KX + LEG_BASE, POSTS[i + 1], POSTS[i] + 0.3), x, y, z) < d2
    then
      return true
    end
  end
  return false
end

newObject(
  KX - LEG_BASE,
  0,
  KZ[1],
  KX + LEG_BASE,
  21 + TUBE,
  KZ[#KZ] + TUBE,
  { __index = { draw = drawCoaster, collides = coasterCollides, near = coasterNear } }
)
-- Station booth at the start of the track
scene.addBox(KX + 3, 12, 3, 4, 3)

-- Town roofs and trees round the fair
local SKYLINE = Ground.newRing({ 1, 1.5, 2, 1, 1.5, 1, 2.5, 1.5, 1, 2, 1, 1.5, 2, 1, 1.5, 2.5 })

function Map.draw(quality)
  Ground.drawGrid(quality, GRID)
  Ground.drawRing(SKYLINE, Ground.horizon(quality))
  Ground.drawPad(0, 0)
  scene.draw(quality)
end

function Map.update(dt, _)
  angle = (angle + SPIN * dt) % TURN
  drop = (drop + dt) % CYCLE
  local t = drop
  if t < T_CLIMB then
    carY = LOW + CLIMB * t
  elseif t < T_HOLD then
    carY = HIGH
  elseif t < T_FALL then
    t = t - T_HOLD
    carY = HIGH - G * t * t / 2
  elseif t < T_BRAKE then
    t = T_BRAKE - t
    carY = LOW + V_FALL * t * t / (2 * (T_BRAKE - T_FALL))
  else
    carY = LOW
  end
end

function Map.collides(x, y, z)
  return scene.collides(x, y, z)
end

Map.near = scene.near

-- Video link: clean within 100 m of the middle of the fair (the coaster's spike is 101 m north), lost at 190 m
function Map.signalLoss(x, y, z)
  return Ground.rangeLoss(x, y, z, 5, 55, 100, 190)
end

return Map
