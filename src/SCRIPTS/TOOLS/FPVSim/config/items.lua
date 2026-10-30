-- The editable settings (config/settings), in menu order: a list of choices (with optional display labels) or a
-- min/max/step range (with an optional printf format and scale for display); preview: changing it plays a sample.
-- Loaded only to read the save file and on the settings screen, so its tables are not held in flight.
local ON_OFF = { "ON", "OFF" }
local RC_RATE = { min = 1, max = 200, step = 1, format = "%.2f", scale = 0.01 }
local HUNDREDTHS = { min = 0, max = 100, step = 1, format = "%.2f", scale = 0.01 }

local function rate(key, label, range, keys)
  local item = { key = key, label = label, axis = keys }
  for k, v in pairs(range) do
    item[k] = v
  end
  return item
end

-- Each rate item carries its axis keys (RC Rate, Rate, RC Expo) for the rate curve preview
local rates = {}
for _, axis in ipairs({ { "roll", "ROLL" }, { "pitch", "PITCH" }, { "yaw", "YAW" } }) do
  local keys = { axis[1] .. "RcRate", axis[1] .. "Rate", axis[1] .. "Expo" }
  rates[#rates + 1] = rate(keys[1], axis[2] .. " RC RATE", RC_RATE, keys)
  rates[#rates + 1] = rate(keys[2], axis[2] .. " RATE", HUNDREDTHS, keys)
  rates[#rates + 1] = rate(keys[3], axis[2] .. " EXPO", HUNDREDTHS, keys)
end

-- Sources first (any stick, pot, slider or channel, by getValue name), then the reverses; each item shows the live
-- sticks as the quad reads them. Then the arm source (also any switch) and its reverse, showing the arm state.
local AXES = {
  { "roll", "ROLL", "ROLL REV" },
  { "pitch", "PITCH", "PITCH REV" },
  { "yaw", "YAW", "YAW REV" },
  { "thr", "THROTTLE", "THR REV" },
}
local controls = {}
for i, axis in ipairs(AXES) do
  controls[i] = { key = axis[1] .. "Src", label = axis[2], source = true, sticks = true }
  controls[i + #AXES] =
    { key = axis[1] .. "Rev", label = axis[3], choices = { true, false }, labels = ON_OFF, sticks = true }
end
controls[#controls + 1] = { key = "armSrc", label = "ARM", source = true, arm = true }
controls[#controls + 1] = { key = "armRev", label = "ARM REV", choices = { true, false }, labels = ON_OFF, arm = true }

-- An item with a page opens it as a sub-page
local items = {
  { key = "camAngle", label = "CAM ANGLE", min = 0, max = 70, step = 1 },
  { key = "fov", label = "FOV", min = 60, max = 150, step = 5 },
  { key = "quality", label = "QUALITY", choices = { 1, 2, 3 }, labels = { "LOW", "MED", "HIGH" } },
  { key = "angleMode", label = "MODE", choices = { false, true }, labels = { "ACRO", "ANGLE" } },
  { key = "batterySim", label = "BATTERY", choices = { true, false }, labels = ON_OFF },
  { key = "fps", label = "FPS", choices = { true, false }, labels = ON_OFF },
  { key = "sound", label = "SOUND", choices = { 2, 1, 0 }, labels = { "ALL", "NO MOTOR", "OFF" }, preview = true },
  { key = "haptic", label = "HAPTIC", choices = { true, false }, labels = ON_OFF, preview = true },
  { label = "RATES", page = rates },
  { label = "CONTROLS", page = controls },
}

return items
