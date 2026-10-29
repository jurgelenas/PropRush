-- Renders fixed camera poses on the host to PBM files under /tmp/fpv-render (no simulator boot needed).

local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("core/render3d")
local Quad = load("core/quad", load("core/rates"))
local Kit = load("core/kit", R)
local settings = load("core/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)

-- Per map: name, x, y, z, heading, pitchUp(rad), rollRight(rad)
local MAPS = {
  pillars = {
    { "ground", 0, 0.1, 0, 0, 0, 0 },
    { "lowfwd", 0, 3, 10, 0, -0.7, 0 },
    { "high", 0, 20, 0, 0, -0.9, 0 },
    { "bank", 0, 6, 20, 20, -0.6, 0.6 },
    { "steep", 0, 60, 0, 0, -1.0, 0.7 },
    -- Looking down at the launch pad from behind it
    { "pad", 0, 8, -12, 0, -1.4, 0 },
    -- Out of range: 250, 330 and 410 m from the map centre
    { "fade", 0, 5, 310, 0, -0.6, 0 },
    { "breakup", 0, 5, 390, 0, -0.6, 0 },
    { "lost", 0, 5, 470, 0, -0.6, 0 },
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
}

local q = Quad.new()
for _, id in ipairs({ "pillars", "bando" }) do
  local Map = load("maps/" .. id, Kit, R)
  for _, p in ipairs(MAPS[id]) do
    q:reset(p[2], p[3], p[4], p[5])
    q:rotate(p[6], 0, p[7])
    lcd.clear()
    R.setCamera(q, settings.camAngle, 0, 0, LCD_W, LCD_H, settings.fov)
    Map.draw(settings.quality)
    local loss = Map.signalLoss(q.px, q.py, q.pz) ^ 2
    if loss > 0 then
      if loss >= 1 then
        lcd.clear()
      end
      gfx.static(loss)
  end
  Hud.draw(q, settings, nil, nil)
  H.savePbm(string.format("/tmp/fpv-render/%s_%s_%dx%d.pbm", id, p[1], LCD_W, LCD_H))
  end
end
exit(0)
