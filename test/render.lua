-- Renders fixed camera poses on the host to PBM files under /tmp/fpv-render (no simulator boot needed).

local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("core/render3d")
local Quad = load("core/quad")
local Kit = load("core/kit", R)
local Map = load("maps/pillars", Kit, R)
local settings = load("core/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)

-- name, x, y, z, heading, pitchUp(rad), rollRight(rad)
local POSES = {
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
}
local q = Quad.new()
for _, p in ipairs(POSES) do
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
  H.savePbm(string.format("/tmp/fpv-render/%s_%dx%d.pbm", p[1], LCD_W, LCD_H))
end
exit(0)
