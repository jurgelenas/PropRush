local app = ...

local gfx, List = app.gfx, app.list

local sin, cos, pi = math.sin, math.cos, math.pi

-- Icons about 24 px square, centred on cx, cy

-- Chequered flag on a pole: 4 x 3 squares of 5 px in a 1 px border
local function flag(cx, cy)
  gfx.rect(cx - 11, cy - 11, 2, 24, 4)
  for r = 0, 2 do
    for c = 0, 3 do
      if (r + c) % 2 == 0 then
        gfx.rect(cx - 9 + c * 5, cy - 11 + r * 5, 5, 5, 4)
      end
    end
  end
  gfx.line(cx - 9, cy - 11, cx + 10, cy - 11, 4)
  gfx.line(cx + 10, cy - 11, cx + 10, cy + 3, 4)
  gfx.line(cx - 9, cy + 3, cx + 10, cy + 3, 4)
end

-- Quad flipping inside a loop arrow
local function flip(cx, cy)
  local R, a0, a1 = 11, 2 * pi / 3, 7 * pi / 3
  local px, py = cx + R * cos(a0), cy - R * sin(a0)
  for i = 1, 24 do
    local a = a0 + (a1 - a0) * i / 24
    local x, y = cx + R * cos(a), cy - R * sin(a)
    gfx.line(px, py, x, y, 4)
    px, py = x, y
  end
  -- Arrowhead: a triangle 4 px ahead along the travel direction t, 3 px either side across the loop (n)
  local tx, ty, nx, ny = -sin(a1), -cos(a1), cos(a1), -sin(a1)
  gfx.fill({ px + 4 * tx, px + 3 * nx, px - 3 * nx }, { py + 4 * ty, py + 3 * ny, py - 3 * ny }, 3, 4)
  gfx.line(cx - 3, cy - 3, cx + 3, cy + 3, 4)
  gfx.line(cx - 3, cy + 3, cx + 3, cy - 3, 4)
  for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    gfx.rect(cx + d[1] * 4 - 1, cy + d[2] * 4 - 1, 3, 3, 4)
  end
end

-- Gear, 19 x 19: "#" pixels set
local GEAR = {
  ".....###...###.....",
  "....#####.#####....",
  "....###########....",
  "....###########....",
  ".#################.",
  "###################",
  "########...########",
  "#######.....#######",
  ".#####.......#####.",
  "..####.......####..",
  ".#####.......#####.",
  "#######.....#######",
  "########...########",
  "###################",
  ".#################.",
  "....###########....",
  "....###########....",
  "....#####.#####....",
  ".....###...###.....",
}

local function gear(cx, cy)
  local x0, y0 = cx - #GEAR[1] // 2, cy - #GEAR // 2
  for y = 1, #GEAR do
    local row, s = GEAR[y], 1
    while true do
      local a, b = string.find(row, "#+", s)
      if not a then
        break
      end
      gfx.rect(x0 + a - 1, y0 + y - 1, b - a + 1, 1, 4)
      s = b + 1
    end
  end
end

local ITEMS = {
  { label = "RACING", mode = "racing", icon = flag, info = { "Gates against", "the clock" } },
  { label = "FREESTYLE", mode = "freestyle", icon = flip, info = { "Flips, gaps", "and dives" } },
  { label = "SETTINGS", icon = gear, info = { "Camera, rates", "and controls" } },
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
    item.status = #maps == 0 and "No maps yet" or (#maps == 1 and "1 Map" or string.format("%d Maps", #maps))
  end
end

local ROW_H = 8
-- Cue number (platform/cues)
local CUE_DENY = 1
-- Divider x: the list needs FREESTYLE, the rest is for the icon and its caption
local SPLIT = 52

-- Settings changed in the pause menu, saved here with flight out of memory
if app.settingsChanged then
  app.settingsChanged = nil
  app.save.write(app.load("config/items"))
end

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
    elseif #item.maps > 0 then
      return "maps", item.maps
    end
    app.sound.cue(CUE_DENY)
  end
  app.menuSelected = List.move(app.menuSelected, event, #ITEMS)
  item = ITEMS[app.menuSelected]

  local W, H, FH = gfx.W, gfx.H, gfx.FH
  gfx.clear()
  List.title("PROPRUSH")
  for i = 1, #ITEMS do
    List.row(List.TOP + 1 + (i - 1) * ROW_H, ROW_H, SPLIT - 2, ITEMS[i].label, i == app.menuSelected)
  end
  gfx.line(SPLIT, List.TOP + 1, SPLIT, H - 1, 4)
  local cx = (SPLIT + W) // 2
  item.icon(cx, List.TOP + 14)
  for i, line in ipairs(item.info) do
    gfx.text(cx, List.TOP + 29 + (i - 1) * (FH + 1), line, "c")
  end
  if item.status then
    gfx.text(cx, H - FH - 1, item.status, "c")
  end
end

return Menu
