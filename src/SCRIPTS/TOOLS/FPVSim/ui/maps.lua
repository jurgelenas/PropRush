-- Map list of one mode, shown when it has more than one map

local app = ...

local gfx, List, Save = app.gfx, app.list, app.save

local ROW_H = 8

local entries, title
local selected, first = 1, 1

local Maps = {}

-- list: catalogue entries of one mode
function Maps.enter(list)
  entries = list
  title = string.upper(list[1].mode)
  selected, first = 1, 1
end

function Maps.run(event)
  if event == EVT_VIRTUAL_EXIT then
    return "menu"
  elseif event == EVT_VIRTUAL_ENTER then
    return "flight", entries[selected]
  end
  selected = List.move(selected, event, #entries)

  local W, H = gfx.W, gfx.H
  local split = W // 2
  local rows = (H - List.TOP - 1) // ROW_H
  if selected < first then
    first = selected
  elseif selected >= first + rows then
    first = selected - rows + 1
  end

  gfx.clear()
  List.title(title)
  for i = first, math.min(#entries, first + rows - 1) do
    List.row(List.TOP + 1 + (i - first) * ROW_H, ROW_H - 1, split - 2, entries[i].name, i == selected)
  end
  gfx.line(split, List.TOP + 1, split, H - 1, 4)
  local entry = entries[selected]
  List.lines(split + 3, List.TOP + 3, entry.info)
  local best = Save.bests[entry.id]
  gfx.text(split + 3, H - gfx.FH - 2, best and string.format("BEST %d", best) or "BEST -")
end

return Maps
