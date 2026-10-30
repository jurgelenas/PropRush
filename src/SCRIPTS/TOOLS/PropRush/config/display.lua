-- Display, flight and sound settings (config/settings): the settings screen's top page, and all the pause menu
-- loads. A list of choices (with optional display labels) or a min/max/step range; preview: changing it plays a
-- sample.
local ON_OFF = { "ON", "OFF" }

return {
  { key = "camAngle", label = "CAM ANGLE", min = 0, max = 70, step = 1 },
  { key = "fov", label = "FOV", min = 60, max = 150, step = 1 },
  { key = "quality", label = "QUALITY", choices = { 1, 2, 3 }, labels = { "LOW", "MED", "HIGH" } },
  { key = "angleMode", label = "MODE", choices = { false, true }, labels = { "ACRO", "ANGLE" } },
  { key = "batterySim", label = "BATTERY", choices = { true, false }, labels = ON_OFF },
  { key = "fps", label = "FPS", choices = { true, false }, labels = ON_OFF },
  { key = "sound", label = "SOUND", choices = { 2, 1, 0 }, labels = { "ALL", "NO MTR", "OFF" }, preview = true },
  { key = "haptic", label = "HAPTIC", choices = { true, false }, labels = ON_OFF, preview = true },
}
