-- Settings (config/items) shown as row text and changed with NEXT/PREV: shared by the settings screen and the pause
-- menu. Sources and sub-pages are the settings screen's own.

local settings = ...

local Edit = {}

function Edit.indexOf(list, v)
  for i = 1, #list do
    if list[i] == v then
      return i
    end
  end
  return 1
end

function Edit.text(item)
  local v = settings[item.key]
  if item.labels then
    return item.labels[Edit.indexOf(item.choices, v)]
  elseif item.format then
    return string.format(item.format, v * item.scale)
  end
  return tostring(v)
end

-- Choices wrap around; ranges stop at their ends
function Edit.change(item, d)
  local v = settings[item.key]
  if item.choices then
    local n = #item.choices
    settings[item.key] = item.choices[(Edit.indexOf(item.choices, v) - 1 + d) % n + 1]
  else
    v = v + d * item.step
    if v < item.min then
      v = item.min
    elseif v > item.max then
      v = item.max
    end
    settings[item.key] = v
  end
end

return Edit
