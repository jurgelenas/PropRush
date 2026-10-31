-- Renders fixed camera poses on the host to PNG files under /tmp/fpv-render, pixel for pixel as the radio draws them
-- (text needs a local EdgeTX build's fonts, see H.loadFonts), in the simulator window's LCD look.

local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)
if not H.loadFonts() then
  print("No EdgeTX fonts found: rendering without text")
end

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/PropRush/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("gfx/render3d")
local Quad = load("physics/quad", load("physics/rates"))
local Ground = load("world/ground", R)
local Scene = load("world/scene", R)
local Gap = load("world/gap")
local settings = load("config/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)
R.setView(0, 0, LCD_W, LCD_H, settings.fov, settings.camAngle)

-- Per map: name, x, y, z, heading, pitchUp(rad), rollRight(rad)
local MAPS = {
  farm = {
    { "ground", 2, 0.1, -50, 0, 0, 0 },
    { "lowfwd", 2, 3, -40, 0, -0.7, 0 },
    { "high", 2, 20, -50, 0, -0.9, 0 },
    { "bank", 2, 6, -30, 20, -0.6, 0.6 },
    { "steep", 2, 60, -50, 0, -1.0, 0.7 },
    -- Looking down at the launch pad from behind it
    { "pad", 2, 8, -62, 0, -1.4, 0 },
    -- Out of range: 125, 155 and 190 m from the map centre
    { "fade", 15, 5, 125, 0, -0.6, 0 },
    { "breakup", 15, 5, 155, 0, -0.6, 0 },
    { "lost", 15, 5, 190, 0, -0.6, 0 },
  },
  bando = {
    { "ground", 0, 0.1, 0, 0, 0, 0 },
    { "approach", 0, 3, 20, 0, -0.7, 0 },
    { "high", -10, 25, 5, 10, -0.9, 0 },
    -- Inside the ground storey, then the top storey under the roof, looking east
    { "storey0", -10, 2, 50, 90, -0.6, 0 },
    { "storey1", -10, 6.5, 50, 90, -0.6, 0 },
    -- Diving at the open half of the roof
    { "roofdive", 8, 16, 40, 0, -1.6, 0 },
    { "facade", -22, 2.5, 12, 0, -0.75, 0 },
    { "bridge", 32, 3, 30, 0, -0.6, 0 },
    { "chimney", 26, 40, 78, 30, -1.9, 0 },
    { "west", -60, 6, 50, 90, -0.7, 0 },
  },
  field = {
    { "ground", 0, 0.1, -10, 0, 0, 0 },
    { "start", 0, 1.7, -8, 0, -0.5, 0 },
    -- Past the start: gate 2 ahead, then turned away from it (the marker's side arrow)
    { "gate2", 1, 2, 20, 5, -0.6, 0 },
    { "away", 1, 2, 20, 100, -0.6, 0 },
    { "high", -10, 25, -20, 40, -0.9, 0 },
    { "high2", 60, 9, 80, 0, -0.6, 0.4 },
  },
}

local q = Quad.new()
local Racing = load("modes/racing", Gap)
for _, path in ipairs({ "freestyle/farm", "freestyle/bando", "racing/field" }) do
  local id = path:match("[^/]+$")
  local Map = load("maps/" .. path, Ground, Scene, Gap, R, load)
  local race = Map.gates and Racing.new(Map)
  for _, p in ipairs(MAPS[id]) do
    q:reset(p[2], p[3], p[4], p[5])
    q.armed = true
    q:rotate(p[6], 0, p[7])
    lcd.clear()
    R.setCamera(q)
    Map.draw(settings.quality)
    if race then
      -- Through the start gate, so the marker is on gate 2
      race.next = 2
      race:draw(R, gfx)
    end
    local loss = Map.signalLoss(q.px, q.py, q.pz) ^ 2
    if loss > 0 then
      if loss >= 1 then
        lcd.clear()
      end
      gfx.static(loss)
    end
    Hud.draw(q, settings, nil, nil)
    H.savePng(string.format("/tmp/fpv-render/%s_%s_%dx%d.png", id, p[1], LCD_W, LCD_H))
  end
end
exit(0)
