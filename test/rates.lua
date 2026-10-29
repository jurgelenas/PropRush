-- Rate curve against Betaflight Configurator's Max Vel figures.

local rate = assert(loadfile("src/SCRIPTS/TOOLS/FPVSim/core/rates.lua"))()

local failures = 0
local function check(name, got, want)
  local ok = math.abs(got - want) < 0.5
  print(string.format("%s %-40s got %.1f want %.1f", ok and "PASS" or "FAIL", name, got, want))
  if not ok then
    failures = failures + 1
  end
end

-- RC Rate, Rate, RC Expo in hundredths
check("RC 1.00 Rate 0.50 Expo 0.00 full stick", rate(1, 100, 50, 0), 400)
check("RC 2.00 Rate 0.00 Expo 0.42 full stick", rate(1, 200, 0, 42), 400)
check("RC 1.00 Rate 0.00 Expo 0.00 full stick", rate(1, 100, 0, 0), 200)
check("defaults 1.00 / 0.70 / 0.00 full stick", rate(1, 100, 70, 0), 666.7)
check("defaults, full stick left", rate(-1, 100, 70, 0), -666.7)
check("defaults, half stick", rate(0.5, 100, 70, 0), 100 / 0.65)
check("expo 0.42, half stick", rate(0.5, 100, 0, 42), 200 * (0.5 * 0.125 * 0.42 + 0.5 * 0.58))
check("rate limit", rate(1, 200, 100, 0), 1998)
check("centre stick", rate(0, 100, 70, 50), 0)

print(failures == 0 and "RATES OK" or string.format("RATES %d FAILED", failures))
exit(failures == 0 and 0 or 1)
