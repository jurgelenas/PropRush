-- Save file round trip and damaged-file handling, on the host.

local H = dofile("test/harness.lua")
H.install(128, 64)

local function load(name, ...)
  return assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/" .. name .. ".lua"))(...)
end
local PATH = "/SCRIPTS/TOOLS/FPVSim/save.txt"
local failures = 0
local function check(cond, what)
  print((cond and "PASS " or "FAIL ") .. what)
  if not cond then
    failures = failures + 1
  end
end
local function fresh()
  local settings, items = load("core/settings")
  return settings, load("core/save", load("platform/storage"), settings, items)
end

-- No file: defaults stay
local settings, Save = fresh()
Save.load()
check(settings.camAngle == 45 and settings.angleMode == false, "missing file keeps defaults")

-- Round trip
settings.camAngle, settings.angleMode, settings.batterySim, settings.rollExpo = 63, true, false, 54
Save.record("pillars", 1200)
check(Save.record("pillars", 900) == false, "lower score does not beat a higher best")
check(Save.record("pillars", 1500) == true, "higher score beats the best")
check(Save.record("gates", 42.5, true) == true and Save.record("gates", 50, true) == false, "lap times: lower wins")
settings, Save = fresh()
Save.load()
check(settings.camAngle == 63, "camAngle restored")
check(settings.angleMode == true and settings.batterySim == false, "booleans restored")
check(settings.rollExpo == 54, "expo restored")
check(Save.bests.pillars == 1500 and Save.bests.gates == 42.5, "bests restored")

-- Damaged file: bad values ignored, good ones kept
H.files[PATH] = "camAngle=999\nquality=7\nangleMode=maybe\nrollRcRate=abc\n\0\1junk\nrollRate=12.5\n"
  .. "yawRcRate=150\nbest.pillars=77\nbest.x=notanumber\n"
settings, Save = fresh()
Save.load()
check(settings.camAngle == 45 and settings.quality == 3 and settings.angleMode == false, "out-of-range values ignored")
check(settings.rollRcRate == 100 and settings.rollRate == 70, "non-numeric and off-step values ignored")
check(settings.yawRcRate == 150, "valid value next to junk kept")
check(Save.bests.pillars == 77 and Save.bests.x == nil, "only numeric bests kept")

print(failures == 0 and "SAVE OK" or string.format("SAVE %d FAILED", failures))
exit(failures == 0 and 0 or 1)
