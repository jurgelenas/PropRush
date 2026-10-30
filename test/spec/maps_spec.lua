-- Maps of the catalogue: each loads and draws, and leaves every opening and gap clear to fly through.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Ground = assert(loadfile(SRC .. "world/ground.lua"))(R)
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Gap = assert(loadfile(SRC .. "world/gap.lua"))()
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())
local list = assert(loadfile(SRC .. "maps/list.lua"))()
local Racing = assert(loadfile(SRC .. "modes/racing.lua"))(Gap)

-- Each racing map's way through its gates in course order: N(orth) +z, S -z, E +x, W -x, U(p) +y, D(own) -y
local WAYS = {
  gates = "NNESSW",
  slalom = "NNNNNESSSSW",
  tech = "NNSNSNDSEWESW",
  super8 = "NESWSE",
}
local WAY = { "WE", "DU", "SN" }

-- As the tool's loader: a module by name under the tool's folder
local function load(name, ...)
  return assert(loadfile(SRC .. name .. ".lua"))(...)
end

R.setSink(assert(loadfile(SRC .. "gfx/bw.lua"))())
R.setView(0, 0, 128, 64, 95, 45)

describe("maps", function()
  for _, entry in ipairs(list) do
    describe(entry.name, function()
      local Map = assert(loadfile(SRC .. "maps/" .. entry.id .. ".lua"))(Ground, Scene, Gap, R, load)

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

      if entry.mode == "racing" then
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
            -- A gap spans u0..u1 ([3], [4]) and v0..v1 ([5], [6]) in its plane at ([2]); axis ([1]) 1, 2, 3: the
            -- x, y, z plane
            local u, v = (g[3] + g[4]) / 2, (g[5] + g[6]) / 2
            local x, y, z = u, v, g[2]
            if g[1] == 1 then
              x, y, z = g[2], u, v
            elseif g[1] == 2 then
              x, y, z = u, g[2], v
            end
            -- name
            assert.is_falsy(Map.collides(x, y, z), g[7])
          end
        end)
      end
    end)
  end
end)
