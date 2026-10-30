-- Settings file: a key=value line per setting (config/items). Values that are unknown or out of range are ignored,
-- so a damaged file falls back to the defaults. Loaded to read it at start and to write it from the menus, never
-- kept in flight.

local storage, settings = ...

local PATH = "/SCRIPTS/TOOLS/PropRush/settings.txt"

local Prefs = {}

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

-- items: config/items
function Prefs.read(items)
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
end

function Prefs.write(items)
  return storage.write(PATH, function(put)
    each(items, function(item)
      put(item.key, settings[item.key])
    end)
  end)
end

return Prefs
