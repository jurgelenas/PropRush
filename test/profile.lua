-- Host CPU cost of each render stage, relative to a loop known to fit the sim's 50 ms Lua slice.

FAST_MOCK = true
local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local gfx = load("gfx/bw")
local R = load("core/render3d")
local Quad = load("core/quad")
local World = load("core/world", R)
R.setSink(gfx)

local REPS = 200
local TRIALS = 5
-- Best of several trials: the minimum is the least disturbed by other host load
local function time(fn)
  local best = math.huge
  for _ = 1, TRIALS do
    local t0 = os.clock()
    for _ = 1, REPS do
      fn()
    end
    best = math.min(best, (os.clock() - t0) * 1e6 / REPS)
  end
  return best
end

local function loop6000()
  local x = 0
  for i = 1, 6000 do
    x = x + i * 0.5
  end
  return x
end
local budget = time(loop6000)
print(string.format("PROF budget(loop6000)=%.1fus", budget))

local q = Quad.new()
local POSES = {
  { "ground", 0, 0.1, 0, 0, 0 },
  { "low-fwd", 0, 3, 10, 0, 0.3 },
  { "20m", 0, 20, 0, 0, 0.5 },
}
local sticks = { ail = 0, ele = 0, thr = 0, rud = 0 }
local settings = load("core/settings")
for _, p in ipairs(POSES) do
  q:reset(p[2], p[3], p[4], p[5])
  q:rotate(-p[6], 0, 0)
  R.setCamera(q, 25, 0, 0, LCD_W, LCD_H, 90)
  local parts = {}
  for qual = 1, 3 do
    H.resetStats()
    World.drawGround(qual)
    local gl = H.stats.lines
    H.resetStats()
    World.drawBoxes(qual)
    local bl = H.stats.lines
    parts[#parts + 1] = string.format(
      "Q%d ground=%.0f%%(%d) boxes=%.0f%%(%d)",
      qual,
      100 * time(function() World.drawGround(qual) end) / budget, gl,
      100 * time(function() World.drawBoxes(qual) end) / budget, bl
    )
  end
  local realFill = gfx.fill
  local rows = 0
  gfx.fill = function(xs, ys, n)
    local a, b = ys[1], ys[1]
    for i = 2, n do
      a, b = math.min(a, ys[i]), math.max(b, ys[i])
    end
    rows = rows + math.max(0, math.min(b, LCD_H) - math.max(a, 0))
  end
  World.drawBoxes(2)
  local noFill = time(function() World.drawBoxes(2) end)
  gfx.fill = realFill
  local realLine = gfx.line
  gfx.line = function() end
  local noLines = time(function() World.drawBoxes(1) end)
  gfx.line = realLine
  parts[#parts + 1] = string.format("LOW boxes-without-lines=%.0f%%", 100 * noLines / budget)
  parts[#parts + 1] = string.format("| MED boxes-without-fill=%.0f%% rows=%.0f", 100 * noFill / budget, rows)
  local phys = time(function()
    q:step(0.02, sticks, settings)
  end)
  q:reset(p[2], p[3], p[4], p[5])
  print(string.format("PROF %-8s %s | physStep=%.0f%%", p[1], table.concat(parts, " "), 100 * phys / budget))
end
exit(0)
