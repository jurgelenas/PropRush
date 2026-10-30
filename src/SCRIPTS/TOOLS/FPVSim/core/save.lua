-- Settings and per-map bests, each in a key=value file. Values that are unknown or out of range are ignored, so a
-- damaged file falls back to the defaults. Settings are written on leaving the settings screen; a best is kept in
-- memory until the run ends (flush), so nothing is written in flight.

local storage, settings = ...

local PATH = "/SCRIPTS/TOOLS/FPVSim/save.txt"
local BESTS = "/SCRIPTS/TOOLS/FPVSim/bests.txt"
-- A best not written yet
local dirty = false

local Save = { bests = {} }

-- Calls fn for every setting, including those on sub-pages
local function each(list, fn)
  for _, item in ipairs(list) do
    if item.page then
      each(item.page, fn)
    else
      fn(item)
    end
  end
end

local function parse(item, s)
  if item.source then
    return #s <= 16 and string.match(s, "^[%w%-]+$") and s or nil
  elseif item.choices then
    for _, c in ipairs(item.choices) do
      if tostring(c) == s then
        return c
      end
    end
    return nil
  end
  local n = tonumber(s)
  if n and n >= item.min and n <= item.max and (n - item.min) % item.step == 0 then
    return n
  end
end

-- items: core/items
function Save.load(items)
  local kv = storage.read(PATH)
  if kv then
    each(items, function(item)
      local s = kv[item.key]
      local v = s and parse(item, s)
      if v ~= nil then
        settings[item.key] = v
      end
    end)
  end
  kv = storage.read(BESTS)
  if kv then
    for id, s in pairs(kv) do
      Save.bests[id] = tonumber(s)
    end
  end
end

function Save.write(items)
  return storage.write(PATH, function(put)
    each(items, function(item)
      put(item.key, settings[item.key])
    end)
  end)
end

-- Keeps a map result in memory if it beats the best (lower wins for times); true when it did
function Save.record(mapId, value, lowerIsBetter)
  local best = Save.bests[mapId]
  if best == nil or (lowerIsBetter and value < best) or (not lowerIsBetter and value > best) then
    Save.bests[mapId] = value
    dirty = true
    return true
  end
  return false
end

-- Writes the bests if one changed, from a collected heap: at the end of a run, where the pause does not show
function Save.flush()
  if not dirty then
    return
  end
  dirty = false
  collectgarbage("collect")
  return storage.write(BESTS, function(put)
    for id, n in pairs(Save.bests) do
      put(id, n)
    end
  end)
end

return Save
