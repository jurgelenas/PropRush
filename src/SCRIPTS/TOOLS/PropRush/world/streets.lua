-- Streets: kerbed roads with zebra crossings on a grid of blocks, drawn on the ground through the current camera
-- (render3d). Only the maps with a town load it.

local R = ...

local Streets = {}

-- Roads 2 * KERB wide down the lines of a grid of blocks, each block's kerb drawn round it and zebra crossings
-- at the inner crossroads. Picking the ground grid's spacing for the block pitch, with the corner on a grid line,
-- makes the grid the roads' centre lines. Kerbs reach as far as the kerbs across a road stay KERB_GAP_PX apart on
-- screen, as the ground grid does, at least KERB_NEAR and at most KERB_DIST; crossings at most ZEBRA_DIST.
local KERB, KERB_GAP_PX = 6, 3
local KERB_NEAR, KERB_DIST = 40, { 90, 120, 150 }
local ZEBRA_DIST = 50
-- Zebra stripes: STRIPES across the road, STRIPE apart, from just off the crossroads out to ZEBRA_END
local STRIPES, STRIPE, ZEBRA_END = 4, 3, KERB + 4

-- cols x rows blocks pitch metres square, their south-west corner at x0, z0
function Streets.draw(quality, x0, z0, cols, rows, pitch)
  local ox, oy, oz = R.cameraPos()
  local half = pitch / 2
  local r = half * 1.42
  local far = math.sqrt(R.focal() * oy * 2 * KERB / KERB_GAP_PX)
  if far < KERB_NEAR then
    far = KERB_NEAR
  elseif far > KERB_DIST[quality] then
    far = KERB_DIST[quality]
  end
  local zebra = far < ZEBRA_DIST and far or ZEBRA_DIST
  local reach = far + r
  reach = reach * reach
  local e = half - KERB
  for i = 0, cols - 1 do
    local cx = x0 + (i + 0.5) * pitch
    for j = 0, rows - 1 do
      local cz = z0 + (j + 0.5) * pitch
      local dx, dz = cx - ox, cz - oz
      if dx * dx + dz * dz < reach and R.sphereVisible(cx, 0, cz, r) then
        R.line(cx - e, 0, cz - e, cx + e, 0, cz - e, 4)
        R.line(cx + e, 0, cz - e, cx + e, 0, cz + e, 4)
        R.line(cx + e, 0, cz + e, cx - e, 0, cz + e, 4)
        R.line(cx - e, 0, cz + e, cx - e, 0, cz - e, 4)
      end
    end
  end
  local u0 = -(STRIPES - 1) * STRIPE / 2
  for i = 1, cols - 1 do
    local x = x0 + i * pitch
    for j = 1, rows - 1 do
      local z = z0 + j * pitch
      local dx, dz = x - ox, z - oz
      if dx * dx + dz * dz < zebra * zebra and R.sphereVisible(x, 0, z, ZEBRA_END * 1.42) then
        for s = -1, 1, 2 do
          local a, b = s * (KERB + 1), s * ZEBRA_END
          for k = 0, STRIPES - 1 do
            local u = u0 + k * STRIPE
            R.line(x + u, 0, z + a, x + u, 0, z + b, 4)
            R.line(x + a, 0, z + u, x + b, 0, z + u, 4)
          end
        end
      end
    end
  end
end

return Streets
