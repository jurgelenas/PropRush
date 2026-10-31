-- README screenshots, drawn on the host as the radio draws them (text needs a local EdgeTX build's fonts, see
-- H.loadFonts) into docs/ in the simulator window's LCD look. Usage, from the repo root:
--   edgetx-cli dev simulator --radio "RadioMaster Boxer" --headless --script test/shots.lua
-- SHOT=drift renders one, TIMES=0,2,4 renders it after each of those seconds instead (to time a moving object).

local H = dofile("test/harness.lua")
H.install(128, 64)
assert(H.loadFonts(), "No EdgeTX fonts found: the screenshots need their text")

local OUT = "docs/"
local SHOT, TIMES = os.getenv("SHOT"), os.getenv("TIMES")

-- Menus: the whole tool run on key events, a frame each
local tool = loadScript("/SCRIPTS/TOOLS/PropRush/main.lua")()
tool.init()
local function frame(event)
  H.time = H.time + 5
  tool.run(event or 0)
end
frame()
frame(EVT_VIRTUAL_ENTER)
frame()
if not SHOT then
  H.savePng(OUT .. "menu.png")
end

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/PropRush/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("gfx/render3d")
local Quad = load("physics/quad", load("physics/rates"))
local Ground, Scene, Gap = load("world/ground", R), load("world/scene", R), load("world/gap")
local settings = load("config/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)
R.setView(0, 0, LCD_W, LCD_H, settings.fov, settings.camAngle)
local highscore = { byMap = {}, record = function() end }

-- Flight frames as ui/flight draws them, the quad held at a pose: x, y, z, heading (degrees, 0 north, 90 east),
-- pitchUp, rollRight (radians); t: seconds the map runs first, so moving objects are in view
local SHOTS = {
  { "racing", "super8", { 0, 2, -12, 0, -0.6, 0 }, t = 0 },
  -- Behind the car as it turns into the sweeper
  { "freestyle", "drift", { 2.5, 2, 27.5, 22, -0.8, 0 }, t = 2.2 },
  { "freestyle", "trainyard", { -10, 8, 10, 20, -0.9, 0 }, t = 3 },
}

local times = {}
for v in (TIMES or ""):gmatch("[^,]+") do
  times[#times + 1] = tonumber(v)
end

for _, s in ipairs(SHOTS) do
  local mode, id, p = s[1], s[2], s[3]
  if not SHOT or SHOT == id then
    for _, t in ipairs(#times > 0 and times or { s.t }) do
      local Map = load("maps/" .. mode .. "/" .. id, Ground, Scene, Gap, R, load)
      local m = load("modes/" .. mode, Gap).new(Map, nil, highscore, id)
      m:reset()
      local q = Quad.new()
      q:reset(p[1], p[2], p[3], p[4])
      q:rotate(p[5], 0, p[6])
      q.armed = true
      for _ = 1, t * 50 do
        Map.update(0.02, q)
      end
      m:update(0.02, q, q.px, q.py, q.pz)
      gfx.clear()
      R.setCamera(q)
      Map.draw(settings.quality)
      m:draw(R, gfx)
      Hud.draw(q, settings, m.goal, nil, m.note, m.clock)
      H.savePng(OUT .. id .. (#times > 0 and "_" .. t or "") .. ".png")
    end
  end
end
exit(0)
