local app = ...

local gfx, List = app.gfx, app.list

local ITEMS = {
  { label = "RACING", mode = "racing", info = { "Fly the gates", "against the", "clock" } },
  { label = "FREESTYLE", mode = "freestyle", info = { "Gaps, dives", "and flying", "close" } },
  { label = "SETTINGS", info = { "Camera, FOV,", "quality,", "mode, rates" } },
}

for _, item in ipairs(ITEMS) do
  if item.mode then
    local maps = {}
    for _, m in ipairs(app.maps) do
      if m.mode == item.mode then
        maps[#maps + 1] = m
      end
    end
    item.maps = maps
    item.status = #maps == 0 and "NO MAPS YET" or (#maps == 1 and "1 MAP" or string.format("%d MAPS", #maps))
  end
end

local ROW_H = 12

-- Kept in app: the menu is reloaded each time it is opened
app.menuSelected = app.menuSelected or 1

local Menu = {}

function Menu.run(event)
  local item = ITEMS[app.menuSelected]
  if event == EVT_VIRTUAL_EXIT then
    return "quit"
  elseif event == EVT_VIRTUAL_ENTER then
    if not item.mode then
      return "settings"
    elseif #item.maps == 1 then
      return "flight", item.maps[1]
    elseif #item.maps > 1 then
      return "maps", item.maps
    end
  end
  app.menuSelected = List.move(app.menuSelected, event, #ITEMS)
  item = ITEMS[app.menuSelected]

  local W, H, FH = gfx.W, gfx.H, gfx.FH
  local split = W // 2
  gfx.clear()
  List.title("FPV SIM")
  for i = 1, #ITEMS do
    List.row(List.TOP + 1 + (i - 1) * ROW_H, ROW_H - 1, split - 2, ITEMS[i].label, i == app.menuSelected, true)
  end
  gfx.line(split, List.TOP + 1, split, H - 1, 4)
  List.lines(split + 3, List.TOP + 3, item.info)
  if item.status then
    gfx.text(split + 3, H - FH - 2, item.status)
  end
end

return Menu
