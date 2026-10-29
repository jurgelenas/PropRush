-- Renders fixed camera poses on the host to PBM files under /tmp/fpv-render (no simulator boot needed).

local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("core/render3d")
local Quad = load("core/quad")
local World = load("core/world", R)
local settings = load("core/settings")
local Hud = load("ui/hud", gfx)
R.setSink(gfx)

-- name, x, y, z, heading, pitchUp(rad), rollRight(rad)
local POSES = {
  { "ground", 0, 0.1, 0, 0, 0, 0 },
  { "lowfwd", 0, 3, 10, 0, -0.7, 0 },
  { "high", 0, 20, 0, 0, -0.9, 0 },
  { "bank", 0, 6, 20, 20, -0.6, 0.6 },
}
local q = Quad.new()
for _, p in ipairs(POSES) do
  q:reset(p[2], p[3], p[4], p[5])
  q:rotate(p[6], 0, p[7])
  lcd.clear()
  R.setCamera(q, settings.camAngle, 0, 0, LCD_W, LCD_H, settings.fov)
  World.draw(settings.quality)
  Hud.draw(q, settings, nil, nil)
  H.savePbm(string.format("/tmp/fpv-render/%s_%dx%d.pbm", p[1], LCD_W, LCD_H))
end
exit(0)
