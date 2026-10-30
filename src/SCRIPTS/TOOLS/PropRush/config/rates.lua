-- Rate settings (config/settings), the RATES page: RC Rate, Rate and RC Expo per axis, as ranges with a printf
-- format and scale for display. Each item carries its axis keys for the rate curve preview.
local RC_RATE = { min = 1, max = 200, step = 1, format = "%.2f", scale = 0.01 }
local HUNDREDTHS = { min = 0, max = 100, step = 1, format = "%.2f", scale = 0.01 }

local function rate(key, label, range, keys)
  local item = { key = key, label = label, axis = keys }
  for k, v in pairs(range) do
    item[k] = v
  end
  return item
end

local rates = {}
for _, axis in ipairs({ { "roll", "ROLL" }, { "pitch", "PITCH" }, { "yaw", "YAW" } }) do
  local keys = { axis[1] .. "RcRate", axis[1] .. "Rate", axis[1] .. "Expo" }
  rates[#rates + 1] = rate(keys[1], axis[2] .. " RC RATE", RC_RATE, keys)
  rates[#rates + 1] = rate(keys[2], axis[2] .. " RATE", HUNDREDTHS, keys)
  rates[#rates + 1] = rate(keys[3], axis[2] .. " EXPO", HUNDREDTHS, keys)
end

return rates
