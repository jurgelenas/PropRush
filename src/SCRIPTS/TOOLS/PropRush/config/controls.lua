-- Control settings (config/settings), the CONTROLS page: sources first (any stick, pot, slider or channel, by
-- getValue name), then the reverses; each item shows the live sticks as the quad reads them. Then the arm source
-- (also any switch) and its reverse, showing the arm state. Only the settings screen loads it.
local ON_OFF = { "ON", "OFF" }

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

return controls
