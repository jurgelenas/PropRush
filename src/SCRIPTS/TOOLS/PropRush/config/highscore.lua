-- Per-map bests in a key=value file, a number each; anything else is ignored. A best is kept in memory until the
-- run ends (flush), so nothing is written in flight. The settings file is config/prefs.

local storage = ...

local PATH = "/SCRIPTS/TOOLS/PropRush/highscore.txt"
-- A best not written yet
local dirty = false

local Highscore = { byMap = {} }

function Highscore.load()
  local kv = storage.read(PATH)
  if kv then
    for id, s in pairs(kv) do
      Highscore.byMap[id] = tonumber(s)
    end
  end
end

-- Keeps a map result in memory if it beats the best (lower wins for times); true when it did
function Highscore.record(mapId, value, lowerIsBetter)
  local best = Highscore.byMap[mapId]
  if best == nil or (lowerIsBetter and value < best) or (not lowerIsBetter and value > best) then
    Highscore.byMap[mapId] = value
    dirty = true
    return true
  end
  return false
end

-- Writes the bests if one changed, from a collected heap: at the end of a run, where the pause does not show
function Highscore.flush()
  if not dirty then
    return
  end
  dirty = false
  collectgarbage("collect")
  return storage.write(PATH, function(put)
    for id, n in pairs(Highscore.byMap) do
      put(id, n)
    end
  end)
end

return Highscore
