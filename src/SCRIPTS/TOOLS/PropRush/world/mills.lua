-- Mill kit: an old tower mill with a gallery and four lattice sails turning slowly, drawn through the current camera
-- (render3d). Only the old mill map loads it.

local R, Scene = ...

local sqrt, sin, cos = math.sqrt, math.sin, math.cos
local touches, distance2 = Scene.touches, Scene.distance2
local SHADE, EDGE, FAR_SHADE, FAR_EDGE = Scene.SHADE, Scene.EDGE, Scene.FAR_SHADE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15

local Kit = {}

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }
local function setBox(x0, y0, z0, x1, y1, z1)
  BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] = x0, y0, z0, x1, y1, z1
  return BOX
end

-- Scene object slots [1..11] round x0, y0, z0 .. x1, y1, z1: bounds, then the sphere's centre and radius
local function bound(o, x0, y0, z0, x1, y1, z1)
  o[1], o[2], o[3], o[4], o[5], o[6] = x0, y0, z0, x1, y1, z1
  local w, h, d = x1 - x0, y1 - y0, z1 - z0
  o[7], o[8], o[9], o[10], o[11] = x0 + w / 2, y0 + h / 2, z0 + d / 2, sqrt(w * w + h * h + d * d) / 2, 0
end

-- Sails: four, turning in the plane z facing south, the hub's box behind them. Arrays: [1..11] as a box's; [12] x,
-- [13] the plane's z, [14] hub height, [15] sail length, [16] the sails' angle offset. Each is a stock from the hub
-- to the tip with a lattice LATTICE wide on one side from SAIL0 out, STOCK and SAIL_T half thick.
local HUB, HUB_D, SAIL0, LATTICE, STOCK, SAIL_T = 0.5, 1.3, 2, 2, 0.2, 0.25
-- Lattice bars across between the ends, drawn within LATTICE_DIST (camera depth); beyond it the ends only
local BARS, LATTICE_DIST = 3, 40
-- About 5 rpm
local SPIN, TURN, QUARTER = 0.5, 2 * math.pi, math.pi / 2
local angle = 0

function Kit.turn(dt)
  angle = (angle + SPIN * dt) % TURN
end

local function hubBox(s)
  local x, z, h = s[12], s[13], s[14]
  return setBox(x - HUB, h - HUB, z - SAIL_T, x + HUB, h + HUB, z + HUB_D)
end

local function drawHub(s, shade, edge)
  local b = hubBox(s)
  R.box(b[1], b[2], b[3], b[4], b[5], b[6], shade, edge)
end

-- Stocks and lattices, or fogged the stocks, worked out in camera space from the hub along the sails' plane
local function drawSails(s, edge, fogged)
  local l = s[15]
  local hx, hy, hz = R.toCamera(s[12], s[14], s[13])
  local ax, ay, az = R.camVector(1, 0, 0)
  local bx, by, bz = R.camVector(0, 1, 0)
  for k = 0, 3 do
    local a = angle + s[16] + k * QUARTER
    local c, n = cos(a), sin(a)
    -- Along the sail and across it
    local ux, uy, uz = ax * c + bx * n, ay * c + by * n, az * c + bz * n
    local vx, vy, vz = (bx * c - ax * n) * LATTICE, (by * c - ay * n) * LATTICE, (bz * c - az * n) * LATTICE
    local tx, ty, tz = hx + ux * l, hy + uy * l, hz + uz * l
    R.camLine(hx, hy, hz, tx, ty, tz, edge)
    if not fogged then
      local rx, ry, rz = hx + ux * SAIL0, hy + uy * SAIL0, hz + uz * SAIL0
      R.camLine(rx + vx, ry + vy, rz + vz, tx + vx, ty + vy, tz + vz, edge)
      local bars = hz < LATTICE_DIST and BARS + 1 or 1
      local step = (l - SAIL0) / bars
      for i = 0, bars do
        local d = SAIL0 + i * step
        local px, py, pz = hx + ux * d, hy + uy * d, hz + uz * d
        R.camLine(px, py, pz, px + vx, py + vy, pz + vz, edge)
      end
    end
  end
end

-- The hub is behind the sails from the south
local function drawSailsObject(s, fogged)
  local shade, edge = fogged and FAR_SHADE or SHADE, fogged and FAR_EDGE or EDGE
  local _, _, oz = R.cameraPos()
  if oz < s[13] then
    drawHub(s, shade, edge)
    drawSails(s, edge, fogged)
  else
    drawSails(s, edge, fogged)
    drawHub(s, shade, edge)
  end
end

-- A sail is a crash, stock or lattice
local function sailsCollides(s, x, y, z)
  if not touches(s, x, y, z) then
    return false
  end
  local b = hubBox(s)
  if touches(b, x, y, z) then
    return b
  end
  local dz = z - s[13]
  if dz > SAIL_T + RADIUS or dz < -SAIL_T - RADIUS then
    return false
  end
  local dx, dy, l = x - s[12], y - s[14], s[15]
  for k = 0, 3 do
    local a = angle + s[16] + k * QUARTER
    local c, n = cos(a), sin(a)
    local along = dx * c + dy * n
    if along > -RADIUS and along < l + RADIUS then
      local across = dy * c - dx * n
      local w = along > SAIL0 - RADIUS and LATTICE or STOCK
      if across < w + RADIUS and across > -STOCK - RADIUS then
        return true
      end
    end
  end
  return false
end

-- Near the hub or the disc the sails sweep
local function sailsNear(s, x, y, z, d2)
  if distance2(s, x, y, z) >= d2 then
    return false
  end
  if distance2(hubBox(s), x, y, z) < d2 then
    return true
  end
  local dz = z - s[13]
  dz = (dz < 0 and -dz or dz) - SAIL_T
  local dx, dy = x - s[12], y - s[14]
  local r = sqrt(dx * dx + dy * dy) - s[15]
  dz, r = dz > 0 and dz or 0, r > 0 and r or 0
  return dz * dz + r * r < d2
end

local SAILS = { __index = { draw = drawSailsObject, collides = sailsCollides, near = sailsNear } }

-- Sails in the plane z, the hub h up, l long, turned by phase (radians); the hub reaches HUB_D north to the mill
local function addSails(scene, x, z, h, l, phase)
  local s = setmetatable({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, x, z, h, l, phase }, SAILS)
  bound(s, x - l, h - l, z - SAIL_T, x + l, h + l, z + HUB_D)
  return scene.addObject(s)
end

-- Tower mill: a body narrowing in three stages under a turning cap, a gallery round it on posts at GALLERY, the
-- sails' plane FACE south of the centre. Stages as half width, base, top.
-- stylua: ignore
local STAGES = { 4, 0, 6, 3.5, 6, 12, 3, 12, 17 }
local GALLERY, DECK, POST = 6, 0.3, 6.3
local CAP, CAP_TOP = 17, 19.2
local FACE = 4.9
-- Hub height and sail length
local TOWER_HUB, TOWER_SAIL = 18.2, 11
Kit.TOWER_HUB, Kit.TOWER_SAIL, Kit.TOWER_FACE, Kit.GALLERY, Kit.POST = TOWER_HUB, TOWER_SAIL, FACE, GALLERY, POST

function Kit.addTowerMill(scene, x, z, phase)
  local st = scene.addStructure()
  for i = 1, #STAGES, 3 do
    local w, y0 = 2 * STAGES[i], STAGES[i + 1]
    st:add(x, z, w, w, STAGES[i + 2] - y0, y0)
  end
  -- Gallery: decks south and north the full width, east and west between them; posts at its corners
  local out, inner = POST + 0.2, STAGES[4]
  local span = out - inner
  st:add(x, z - inner - span / 2, 2 * out, span, DECK, GALLERY)
  st:add(x, z + inner + span / 2, 2 * out, span, DECK, GALLERY)
  st:add(x - inner - span / 2, z, span, 2 * inner, DECK, GALLERY)
  st:add(x + inner + span / 2, z, span, 2 * inner, DECK, GALLERY)
  for i = -1, 1, 2 do
    for j = -1, 1, 2 do
      st:add(x + i * POST, z + j * POST, 0.3, 0.3, GALLERY, 0)
    end
  end
  -- Cap, overhanging south to the hub, and its ridge
  st:add(x, z - 0.2, 6.4, 7, CAP_TOP - CAP, CAP)
  st:add(x, z - 0.2, 3, 6, 1, CAP_TOP)
  addSails(scene, x, z - FACE, TOWER_HUB, TOWER_SAIL, phase)
  return st
end

return Kit
