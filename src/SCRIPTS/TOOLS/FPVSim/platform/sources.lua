-- Picking an axis source on the settings screen: the radio's sources and which control the pilot moves

local getValue, getFieldInfo, sources, getSourceName = getValue, getFieldInfo, sources, getSourceName

local Input = ...

-- Travel from where a control was when picking began that selects it as a source
local MOVED = 300

local idOf = Input.idOf

local Sources = {}

local function plain(label, name)
  label = string.upper(string.gsub(label, "[^%w%-%+]", ""))
  return label ~= "" and label or string.upper(name)
end

-- The sources an axis can take, in the radio's order: the sticks, pots and sliders, then for arming the switches
-- (the first `moving` entries, picked by moving them; arming starts with ALWAYS, no source), then the channels the
-- model uses. names: getValue names (saved), labels: the radio's names in capitals, without its stick and pot icons.
function Sources.list(arm)
  local first, last = math.huge, idOf("min")
  for _, name in pairs(Input.DEFAULT) do
    local id = idOf(name)
    if id < first then
      first = id
    end
  end
  local list = { names = {}, labels = {}, ids = {}, base = {}, moving = 0 }
  local function add(name, label, id)
    local n = #list.names + 1
    list.names[n], list.labels[n], list.ids[n] = name, label, id
  end
  if arm then
    add(Input.ALWAYS, "ALWAYS", false)
  end
  local channels = {}
  for id, label in sources() do
    local f = getFieldInfo(id)
    local name = f and f.name
    if name then
      if id >= first and id < last then
        add(name, plain(label, name), id)
      elseif string.match(name, "^ch%d+$") then
        channels[#channels + 1] = id
        channels[#channels + 1] = plain(label, name)
        channels[#channels + 1] = name
      end
    end
  end
  if arm then
    -- The firmware names switches only when asked by name, "sa" .. "sz"
    for c = 97, 122 do
      local name = "s" .. string.char(c)
      local id = idOf(name)
      if id then
        add(name, plain(getSourceName(id) or "", name), id)
      end
    end
  end
  list.moving = #list.names
  for i = 1, #channels, 3 do
    add(channels[i + 2], channels[i + 1], channels[i])
  end
  return list
end

-- The display label of a saved source name
function Sources.label(list, name)
  for i = 1, #list.names do
    if list.names[i] == name then
      return list.labels[i]
    end
  end
  local id = idOf(name)
  return plain(id and getSourceName(id) or "", name)
end

-- Notes where every control that can be picked by moving it is
function Sources.snapshot(list)
  for i = 1, list.moving do
    local id = list.ids[i]
    list.base[i] = id and getValue(id) or 0
  end
end

-- The name of a control moved well away from its snapshot, as the radio's own source fields pick one
function Sources.moved(list)
  for i = 1, list.moving do
    local id = list.ids[i]
    local d = id and getValue(id) - list.base[i] or 0
    if d > MOVED or d < -MOVED then
      return list.names[i]
    end
  end
end

return Sources
