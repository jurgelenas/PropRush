-- Scripted flight through the real modules; reports per-frame host CPU time and lcd call counts.

local H = dofile("test/harness.lua")
H.install(tonumber(BENCH_W) or 128, tonumber(BENCH_H) or 64)

local tool = assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/main.lua"))()
tool.init()

local FRAME = 5 -- ticks of 10 ms
local function frame(event)
  H.time = H.time + FRAME
  H.resetStats()
  local t0 = os.clock()
  tool.run(event or 0)
  return (os.clock() - t0) * 1000
end

-- {seconds, ail, ele, thr, rud} with sticks in -1024..1024
local SCRIPT = {
  { 0.5, 0, 0, -1024, 0 },
  { 1.5, 0, 0, 400, 0 },
  { 0.5, 0, 300, -200, 0 },
  { 2.0, 0, 0, -350, 0 },
  { 0.6, 0, 0, -350, 500 },
  { 0.4, 600, 0, -350, 0 },
  { 2.0, 0, 0, -400, 0 },
  { 0.5, 0, 1024, -1024, 0 },
  { 3.0, 0, 0, -1024, 0 },
}

-- Intro, then FREESTYLE in the menu
frame(EVT_VIRTUAL_ENTER)
frame(EVT_VIRTUAL_NEXT)
frame(EVT_VIRTUAL_ENTER)
local worst, total, n = 0, 0, 0
for _, step in ipairs(SCRIPT) do
  H.sticks.ail, H.sticks.ele, H.sticks.thr, H.sticks.rud = step[2], step[3], step[4], step[5]
  for _ = 1, math.floor(step[1] * 100 / FRAME) do
    local ms = frame()
    n = n + 1
    total = total + ms
    if ms > worst then
      worst = ms
    end
    if n % 10 == 0 then
      local s = H.stats
      print(string.format("BENCH f=%d %.2fms lines=%d px=%d | %s", n, ms, s.lines, s.linePixels, table.concat(H.text, " | ")))
    end
  end
end
print(string.format("BENCH frames=%d avg=%.2fms worst=%.2fms", n, total / n, worst))
exit(0)
