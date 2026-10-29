-- Settings and per-map bests in one key=value file. Values that are unknown or out of range are ignored, so a
-- damaged file falls back to the defaults.

local storage, settings, items = ...

local PATH = "/SCRIPTS/TOOLS/FPVSim/save.txt"
local BEST_PREFIX = "best."

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

function Save.load()
  local kv = storage.read(PATH)
  if not kv then
    return
  end
  each(items, function(item)
    local s = kv[item.key]
    local v = s and parse(item, s)
    if v ~= nil then
      settings[item.key] = v
    end
  end)
  for key, s in pairs(kv) do
    local n = tonumber(s)
    if n and string.sub(key, 1, #BEST_PREFIX) == BEST_PREFIX then
      Save.bests[string.sub(key, #BEST_PREFIX + 1)] = n
    end
  end
end

function Save.write()
  local keys, values = {}, {}
  each(items, function(item)
    keys[#keys + 1] = item.key
    values[item.key] = settings[item.key]
  end)
  for id, n in pairs(Save.bests) do
    local key = BEST_PREFIX .. id
    keys[#keys + 1] = key
    values[key] = n
  end
  return storage.write(PATH, keys, values)
end

-- Keeps a map result if it beats the stored best (lower wins for times); true when it did
function Save.record(mapId, value, lowerIsBetter)
  local best = Save.bests[mapId]
  if best == nil or (lowerIsBetter and value < best) or (not lowerIsBetter and value > best) then
    Save.bests[mapId] = value
    Save.write()
    return true
  end
  return false
end

return Save
