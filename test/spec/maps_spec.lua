-- Maps of the catalogue: each loads and draws, and leaves every opening and gap clear to fly through.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Ground = assert(loadfile(SRC .. "world/ground.lua"))(R)
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Gap = assert(loadfile(SRC .. "world/gap.lua"))()
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())
local Racing = assert(loadfile(SRC .. "modes/racing.lua"))(Gap)

-- Each racing map's way through its gates in course order: N(orth) +z, S -z, E +x, W -x, U(p) +y, D(own) -y
local WAYS = {
  gates = "NNESSW",
  slalom = "NNNNESSSSENNNWWSSE",
  tech = "NNSNSNDSEEESW",
  super8 = "NESWSE",
  field = "NNNEENNWSWSSE",
  momentum = "NNNNNWSSSSSE",
  halo = "SENESSWWNES",
  freefall = "NNEDWWNEEWWESNSNSSSSWW",
  flatout = "NNNNNEEESSSSSWW",
  apex = "NNESSEESSSSWWN",
  razor = "NNNNNESSSNNSSW",
}
local WAY = { "WE", "DU", "SN" }

-- As the tool's loader: a module by name under the tool's folder
local function load(name, ...)
  return assert(loadfile(SRC .. name .. ".lua"))(...)
end

-- A gap spans u0..u1 ([3], [4]) and v0..v1 ([5], [6]) in its plane at ([2]); axis ([1]) 1, 2, 3: the x, y, z plane
local function gapCentre(g)
  local u, v = (g[3] + g[4]) / 2, (g[5] + g[6]) / 2
  if g[1] == 1 then
    return g[2], u, v
  elseif g[1] == 2 then
    return u, g[2], v
  end
  return u, v, g[2]
end

-- Bounds a and b ([1..6]: x0, y0, z0, x1, y1, z1) overlap
local function overlap(a, b)
  return a[1] < b[4] and b[1] < a[4] and a[2] < b[5] and b[2] < a[5] and a[3] < b[6] and b[3] < a[6]
end

R.setSink(assert(loadfile(SRC .. "gfx/bw.lua"))())
R.setView(0, 0, 128, 64, 95, 45)

local MODES = { "racing", "freestyle" }

describe("maps", function()
  -- Bests are kept by id alone
  it("have ids unique across modes", function()
    local seen = {}
    for _, mode in ipairs(MODES) do
      for _, entry in ipairs(load("maps/" .. mode .. "/list")) do
        assert.is_nil(seen[entry.id], entry.id)
        seen[entry.id] = true
      end
    end
  end)

  for _, mode in ipairs(MODES) do
    for _, entry in ipairs(load("maps/" .. mode .. "/list")) do
      describe(entry.name, function()
        local Map = load("maps/" .. mode .. "/" .. entry.id, Ground, Scene, Gap, R, load)

        it("has three info lines", function()
          assert.equal(3, #entry.info)
        end)

        it("draws from the spawn", function()
          local s = Map.spawn
          local q = Quad.new()
          q:reset(s.x, 1.5, s.z, s.heading)
          R.setCamera(q)
          for quality = 1, 3 do
            Map.draw(quality)
          end
        end)

        if mode == "racing" then
          it("leaves each opening's marker centre clear", function()
            assert.is_true(#Map.gates > 1)
            for i, g in ipairs(Map.gates) do
              -- cx, cy, cz
              assert.is_falsy(Map.collides(g[9], g[10], g[11]), "opening " .. i)
            end
          end)
          it("goes through each opening its own way", function()
            Racing.new(Map)
            local ways = ""
            for _, g in ipairs(Map.gates) do
              -- axis, dir
              local k = g[15] > 0 and 2 or 1
              ways = ways .. WAY[g[1]]:sub(k, k)
            end
            assert.equal(WAYS[entry.id], ways)
          end)
        end

        if Map.gaps then
          it("leaves each gap's centre clear", function()
            for _, g in ipairs(Map.gaps) do
              -- name
              assert.is_falsy(Map.collides(gapCentre(g)), g[7])
            end
          end)
        end

        it("keeps what moves clear of the rest for a minute", function()
          local objects, gaps = Map.scene.objects, Map.gaps or {}
          local x0, u0 = {}, {}
          for _, o in ipairs(objects) do
            x0[o] = o[1]
          end
          for _, g in ipairs(gaps) do
            u0[g] = g[3]
          end
          local q = Quad.new()
          q:reset(Map.spawn.x, 1.5, Map.spawn.z, Map.spawn.heading)
          R.setCamera(q)
          for step = 1, 600 do
            Map.update(0.1, q)
            if step % 20 == 0 then
              Map.draw(3)
            end
            for _, m in ipairs(objects) do
              if m[1] ~= x0[m] then
                for _, o in ipairs(objects) do
                  -- Boxes, and the parts of structures
                  if not o.draw then
                    assert.is_false(overlap(m, o), "moved into a box at step " .. step)
                  elseif o.add then
                    for i = 12, #o do
                      assert.is_false(overlap(m, o[i]), "moved into a structure at step " .. step)
                    end
                  end
                end
              end
            end
            for _, g in ipairs(gaps) do
              if g[3] ~= u0[g] then
                assert.is_falsy(Map.collides(gapCentre(g)), g[7] .. " at step " .. step)
              end
            end
          end
        end)
      end)
    end
  end
end)
