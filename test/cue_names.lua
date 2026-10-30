-- Names of the sound cues (src/.../platform/cues.lua) in their order, so specs can name them: names[id], and
-- names.id[name] the id.

local names = {
  "deny",
  "rev",
  "throttle",
  "armed",
  "disarmed",
  "respawn",
  "bump",
  "strike",
  "strikeHard",
  "crackle",
  "crackleLoud",
  "low",
  "empty",
  "range",
  "link",
  "roll",
  "flip",
  "flipRoll",
  "yaw",
  "trippy",
  "loop",
  "splitS",
  "dive",
  "gap",
  "gapInverted",
  "hang",
  "knife",
  "proxy",
  "hangTick",
  "knifeTick",
  "proxyTick",
  "chime",
  "bank",
  "lost",
  "record",
  "best",
  "start",
  "gate",
  "lap",
  "bestLap",
}
names.id = {}
for id, name in ipairs(names) do
  names.id[name] = id
end
return names
