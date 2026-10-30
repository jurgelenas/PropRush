-- Circuit: a road circuit painted on the ground, its edges with kerbs inside the turns and a start line with the
-- grid behind it, drawn through the current camera (render3d). Only the maps with a road circuit load it.

local R = ...

local Circuit = {}

local sqrt, sin, cos, rad, ceil = math.sqrt, math.sin, math.cos, math.rad, math.ceil

-- Road HALF wide each side of its centre line
local HALF = 4.5
Circuit.HALF = HALF
-- Straights are cut in pieces up to PIECE long and turns in steps up to STEP degrees, each culled alone within SEG_R
local PIECE, STEP, SEG_R = 14, 22.5, 8

-- Edges reach as far as the two across the road stay GAP_PX apart on screen, at least NEAR and at most DIST; kerbs
-- and the start markings at most KERB_DIST
local GAP_PX, NEAR, DIST, KERB_DIST = 3, 40, { 90, 120, 150 }, 40
-- Kerbs on the inside of each turn's middle half: blocks BLOCK long, every other one drawn, KERB wide
local BLOCK, KERB = 1.5, 1.2
-- Grid: SLOTS boxes behind the start line, SLOT apart, staggered STAGGER left and right
local SLOTS, SLOT, STAGGER = 4, 3, 2.6

-- Kerb blocks along the edge from a to b, reaching nx, nz onto the road
local function kerb(ax, az, bx, bz, nx, nz)
  local dx, dz = bx - ax, bz - az
  local n = ceil(sqrt(dx * dx + dz * dz) / BLOCK)
  dx, dz = dx / n, dz / n
  for j = 0, n - 1, 2 do
    local x0, z0 = ax + dx * j, az + dz * j
    local x1, z1 = x0 + dx, z0 + dz
    R.line(x0, 0, z0, x0 + nx, 0, z0 + nz, 4)
    R.line(x0 + nx, 0, z0 + nz, x1 + nx, 0, z1 + nz, 4)
    R.line(x1 + nx, 0, z1 + nz, x1, 0, z1, 4)
  end
end

-- Road laid as a turtle from x, z heading degrees (0 north, right positive). layout: pairs, a straight's length
-- and 0, or a turn's radius and degrees. Walked every frame: arrays of its joints would cost more heap than the walk
-- costs time. start: the start line that far along the first straight, or nil.
function Circuit.draw(quality, layout, x, z, heading, start)
  local ox, oy, oz = R.cameraPos()
  local far = sqrt(R.focal() * oy * 2 * HALF / GAP_PX)
  if far < NEAR then
    far = NEAR
  elseif far > DIST[quality] then
    far = DIST[quality]
  end
  local near = far < KERB_DIST and far or KERB_DIST
  far, near = far * far, near * near
  local f = KERB / (2 * HALF)
  heading = rad(heading)
  local hx, hz = sin(heading), cos(heading)
  if start then
    -- Start line across the road at sx, sz, the first grid box on the left; the grid's middle 7 behind it
    local sx, sz = x + start * hx, z + start * hz
    local dx, dz = sx - ox, sz - oz
    if dx * dx + dz * dz < near and R.sphereVisible(sx - 7 * hx, 0, sz - 7 * hz, 10) then
      local ax, az = HALF * hz, -HALF * hx
      R.line(sx - ax, 0, sz - az, sx + ax, 0, sz + az, 4)
      R.line(sx - ax + 0.6 * hx, 0, sz - az + 0.6 * hz, sx + ax + 0.6 * hx, 0, sz + az + 0.6 * hz, 4)
      local side, bx, bz = -STAGGER, 1.5 * hx, 1.5 * hz
      for k = 1, SLOTS do
        local cx, cz = sx - SLOT * k * hx + side * hz, sz - SLOT * k * hz - side * hx
        local lx, lz, rx, rz = cx - hz, cz + hx, cx + hz, cz - hx
        R.line(lx - bx, 0, lz - bz, lx, 0, lz, 4)
        R.line(lx, 0, lz, rx, 0, rz, 4)
        R.line(rx, 0, rz, rx - bx, 0, rz - bz, 4)
        side = -side
      end
    end
  end
  -- Centre x, z, heading's unit vector hx, hz, and the left (lx, lz) and right (rx, rz) edges there
  local lx, lz, rx, rz = x - HALF * hz, z + HALF * hx, x + HALF * hz, z - HALF * hx
  for i = 1, #layout, 2 do
    local a, d = layout[i], layout[i + 1]
    -- Steps, each turning by c, s (cos, sin) and moving len along the heading turned by half that (c2, s2)
    local n, c, s, c2, s2, len = ceil(a / PIECE), 1, 0, 1, 0, 0
    if d == 0 then
      len = a / n
    else
      n = ceil((d < 0 and -d or d) / STEP)
      local t = rad(d / n)
      c, s, c2, s2 = cos(t), sin(t), cos(t / 2), sin(t / 2)
      len = 2 * a * (s2 < 0 and -s2 or s2)
    end
    for j = 1, n do
      x, z = x + len * (hx * c2 + hz * s2), z + len * (hz * c2 - hx * s2)
      hx, hz = hx * c + hz * s, hz * c - hx * s
      local px, pz, qx, qz = lx, lz, rx, rz
      lx, lz, rx, rz = x - HALF * hz, z + HALF * hx, x + HALF * hz, z - HALF * hx
      -- Across the piece's diagonal: its middle
      local mx, mz = (px + rx) / 2, (pz + rz) / 2
      local dx, dz = mx - ox, mz - oz
      local d2 = dx * dx + dz * dz
      if d2 < far and R.sphereVisible(mx, 0, mz, SEG_R) then
        R.line(px, 0, pz, lx, 0, lz, 4)
        R.line(qx, 0, qz, rx, 0, rz, 4)
        if d ~= 0 and d2 < near and j > n // 4 and j <= n - n // 4 then
          if d > 0 then
            kerb(qx, qz, rx, rz, (px - qx) * f, (pz - qz) * f)
          else
            kerb(px, pz, lx, lz, (qx - px) * f, (qz - pz) * f)
          end
        end
      end
    end
  end
end

return Circuit
