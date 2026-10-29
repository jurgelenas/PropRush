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

-- The sources an axis can take, in the radio's order: the sticks, pots and sliders (the first `analog` entries, up
-- to MIN), then the channels the model uses. names: getValue names (saved), labels: the radio's names in capitals,
-- without its stick and pot icons.
function Sources.list()
  local first, last = math.huge, idOf("min")
  for _, name in pairs(Input.DEFAULT) do
    local id = idOf(name)
    if id < first then
      first = id
    end
  end
  local list = { names = {}, labels = {}, ids = {}, base = {}, analog = 0 }
  for id, label in sources() do
    local f = getFieldInfo(id)
    local name = f and f.name
    local analog = id >= first and id < last
    if name and (analog or string.match(name, "^ch%d+$")) then
      local n = #list.names + 1
      list.names[n], list.labels[n], list.ids[n] = name, plain(label, name), id
      if analog then
        list.analog = n
      end
    end
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

-- Notes where every stick, pot and slider is
function Sources.snapshot(list)
  for i = 1, list.analog do
    list.base[i] = getValue(list.ids[i])
  end
end

-- The name of a stick, pot or slider moved well away from its snapshot, as the radio's own source fields pick one
function Sources.moved(list)
  for i = 1, list.analog do
    local d = getValue(list.ids[i]) - list.base[i]
    if d > MOVED or d < -MOVED then
      return list.names[i]
    end
  end
end

return Sources
