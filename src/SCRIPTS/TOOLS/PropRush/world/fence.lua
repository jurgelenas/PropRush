-- Post-and-rail fences along a line of points, drawn through the current camera (render3d). Only the maps with
-- fences load it.

local R, Scene = ...

local sqrt = math.sqrt
local touches, distance2 = Scene.touches, Scene.distance2
local EDGE, FAR_EDGE = Scene.EDGE, Scene.FAR_EDGE
-- The quad's collision radius, as the scene's
local RADIUS = 0.15

local Fence = {}

-- Box handed back by collides, valid until the next call
local BOX = { 0, 0, 0, 0, 0, 0 }

-- Fences are arrays: [1..11] as a box's; [12], [13] the points' x and z.
local RAIL_LO, RAIL_HI, POST_H = 0.55, 1.1, 1.3
-- Posts every POST_STEP, drawn within POST_DIST; fogged, the top rail alone
local POST_STEP, POST_DIST = 4, 25
local POST_HALF = 0.06

local function drawFence(f, fogged)
  local xs, zs = f[12], f[13]
  local edge = fogged and FAR_EDGE or EDGE
  local ox, _, oz = R.cameraPos()
  local near2 = POST_DIST * POST_DIST
  for i = 1, #xs - 1 do
    local ax, az, bx, bz = xs[i], zs[i], xs[i + 1], zs[i + 1]
    local dx, dz = bx - ax, bz - az
    local len = sqrt(dx * dx + dz * dz)
    if R.sphereVisible(ax + dx / 2, POST_H / 2, az + dz / 2, len / 2 + POST_H) then
      R.line(ax, RAIL_HI, az, bx, RAIL_HI, bz, edge)
      if not fogged then
        R.line(ax, RAIL_LO, az, bx, RAIL_LO, bz, edge)
        local n = math.ceil(len / POST_STEP)
        for k = 0, n do
          local px, pz = ax + dx * k / n, az + dz * k / n
          local ex, ez = px - ox, pz - oz
          if ex * ex + ez * ez < near2 then
            R.line(px, 0, pz, px, POST_H, pz, edge)
          end
        end
      end
    end
  end
end

-- Closest point to x, z on fence f's segment i: its x, z and the squared distance
local function closest(f, i, x, z)
  local xs, zs = f[12], f[13]
  local ax, az = xs[i], zs[i]
  local dx, dz = xs[i + 1] - ax, zs[i + 1] - az
  local t = ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)
  t = t < 0 and 0 or t > 1 and 1 or t
  local px, pz = ax + dx * t, az + dz * t
  return px, pz, (x - px) * (x - px) + (z - pz) * (z - pz)
end

local function fenceCollides(f, x, y, z)
  if not touches(f, x, y, z) then
    return false
  end
  local reach = POST_HALF + RADIUS
  for i = 1, #f[12] - 1 do
    local px, pz, d2 = closest(f, i, x, z)
    if d2 < reach * reach then
      BOX[1], BOX[2], BOX[3], BOX[4], BOX[5], BOX[6] =
        px - POST_HALF, 0, pz - POST_HALF, px + POST_HALF, POST_H, pz + POST_HALF
      return BOX
    end
  end
  return false
end

local function fenceNear(f, x, y, z, d2)
  if distance2(f, x, y, z) >= d2 then
    return false
  end
  local v = y > POST_H and y - POST_H or 0
  for i = 1, #f[12] - 1 do
    local _, _, h2 = closest(f, i, x, z)
    if h2 + v * v < d2 then
      return true
    end
  end
  return false
end

local FENCE = { __index = { draw = drawFence, collides = fenceCollides, near = fenceNear } }

-- Fence along points, a flat x, z list
function Fence.add(scene, points)
  local xs, zs = {}, {}
  local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, #points, 2 do
    local x, z = points[i], points[i + 1]
    xs[#xs + 1], zs[#zs + 1] = x, z
    x0, x1, z0, z1 = math.min(x0, x), math.max(x1, x), math.min(z0, z), math.max(z1, z)
  end
  x0, z0, x1, z1 = x0 - POST_HALF, z0 - POST_HALF, x1 + POST_HALF, z1 + POST_HALF
  local w, d = x1 - x0, z1 - z0
  -- stylua: ignore
  local f = setmetatable({
    x0, 0, z0, x1, POST_H, z1,
    x0 + w / 2, POST_H / 2, z0 + d / 2, sqrt(w * w + POST_H * POST_H + d * d) / 2, 0,
    xs, zs,
  }, FENCE)
  return scene.addObject(f)
end

return Fence
