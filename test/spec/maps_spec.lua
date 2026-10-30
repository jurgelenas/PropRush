-- Maps of the catalogue: each loads and draws, and racing maps leave every opening clear to fly through.

local H = dofile("test/harness.lua")
H.install(128, 64)

local SRC = "src/SCRIPTS/TOOLS/PropRush/"
local R = assert(loadfile(SRC .. "gfx/render3d.lua"))()
local Ground = assert(loadfile(SRC .. "world/ground.lua"))(R)
local Scene = assert(loadfile(SRC .. "world/scene.lua"))(R)
local Course = assert(loadfile(SRC .. "world/course.lua"))(R, Scene)
local Quad = assert(loadfile(SRC .. "physics/quad.lua"))(assert(loadfile(SRC .. "physics/rates.lua"))())
local list = assert(loadfile(SRC .. "maps/list.lua"))()

R.setSink(assert(loadfile(SRC .. "gfx/bw.lua"))())
R.setView(0, 0, 128, 64, 95, 45)

describe("maps", function()
  for _, entry in ipairs(list) do
    describe(entry.name, function()
      local Map = assert(loadfile(SRC .. "maps/" .. entry.id .. ".lua"))(Ground, Scene, Course)

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
    end)
  end
end)
