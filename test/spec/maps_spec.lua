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
            assert.is_falsy(Map.collides(g.cx, g.cy, g.cz), "opening " .. i)
          end
        end)
      end

      if Map.gaps then
        it("leaves each gap's centre clear", function()
          for _, g in ipairs(Map.gaps) do
            -- A gap spans u0..u1 and v0..v1 in its plane at; axis 1, 2, 3: the x, y, z plane
            local u, v = (g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2
            local x, y, z = u, v, g.at
            if g.axis == 1 then
              x, y, z = g.at, u, v
            elseif g.axis == 2 then
              x, y, z = u, g.at, v
            end
            assert.is_falsy(Map.collides(x, y, z), g.name)
          end
        end)
      end
    end)
  end
end)
