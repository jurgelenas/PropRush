-- Control mapping and source picking, on the host: each axis reads its chosen source, reversed when set, and moving
-- a control picks it.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local settings = load("core/settings")
local Input = load("platform/input", settings)
local Sources = load("platform/sources", Input)
local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then
    failures = failures + 1
  end
end

H.sticks = { ail = 512, ele = -1024, thr = -1024, rud = 2000, ch1 = 1024, ch3 = -512 }
local s = Input.read()
check(s.ail == 0.5 and s.ele == -1 and s.rud == 1 and s.thr == 0, "default sticks, clamped")

settings.rollSrc, settings.thrSrc = "ch3", "ch1"
s = Input.read()
check(s.ail == -0.5 and s.thr == 1, "channel sources")

settings.rollRev, settings.thrRev, settings.yawRev = true, true, true
s = Input.read()
check(s.ail == 0.5 and s.thr == 0 and s.rud == -1, "reversed")

settings.pitchSrc = "nosuch"
check(Input.read().ele == -1, "unknown source falls back to the stick")

local list = Sources.list()
check(
  table.concat(list.names, " ") == "rud ele thr ail s1 s2 ch1 ch2 ch3" and list.analog == 6,
  "list: sticks and pots, then channels"
)
check(
  Sources.label(list, "ail") == "AIL" and Sources.label(list, "s1") == "S1" and Sources.label(list, "ch9") == "CH9",
  "labels: capitals, no icons"
)

H.sticks = { ail = 0, ele = 0, thr = -1024, rud = 0, s2 = 0 }
Sources.snapshot(list)
H.sticks.ail = 200
check(Sources.moved(list) == nil, "small move ignored")
H.sticks.s2 = -900
check(Sources.moved(list) == "s2", "moved pot picked")

print(failures == 0 and "INPUT OK" or string.format("INPUT %d FAILED", failures))
exit(failures == 0 and 0 or 1)
