-- ENTER edits the selected setting (or opens its sub-page), NEXT/PREV change it, ENTER or EXIT ends editing.
-- EXIT leaves a sub-page; on the top page it saves and returns to the menu.

local app = ...

local gfx, settings, stickRate, input = app.gfx, app.settings, app.rates, app.input
local List = app.load("ui/list", gfx)
local Prefs = app.load("config/prefs", app.storage, settings)
local Sound = app.sound

local ROW_H = 8
local PREVIEW_W, PREVIEW_H = 42, 34
local RAD = math.pi / 180

-- RATE_STEPS segments draw the rate curve
local RATE_STEPS = 12

local Sources = app.load("platform/sources", input)
local Edit = app.load("ui/edit", settings)
-- The radio's sources for the axes and for arming, each listed when first shown
local axisList, armList
local function sourcesOf(item)
  if item.arm then
    armList = armList or Sources.list(true)
    return armList
  end
  axisList = axisList or Sources.list()
  return axisList
end

local TOP = { items = app.load("config/items", app.load), title = "SETTINGS" }
-- Current page: items and title; selection, scroll position and the page it was opened from
local page, editing

local function valueText(item)
  if item.page then
    return ">"
  elseif item.source then
    return Sources.label(sourcesOf(item), settings[item.key])
  end
  return Edit.text(item)
end

local function change(item, d)
  if item.source then
    local names = sourcesOf(item).names
    settings[item.key] = names[(Edit.indexOf(names, settings[item.key]) - 1 + d) % #names + 1]
  else
    Edit.change(item, d)
  end
  if item.preview then
    Sound.preview(item.key)
  end
end

-- Side view of the quad with the camera tilted up and its vertical field of view
local function drawCameraPreview(x, y)
  local W, H = gfx.W, gfx.H
  gfx.line(x, y, x + PREVIEW_W, y, 4)
  gfx.line(x + PREVIEW_W, y, x + PREVIEW_W, y + PREVIEW_H, 4)
  gfx.line(x + PREVIEW_W, y + PREVIEW_H, x, y + PREVIEW_H, 4)
  gfx.line(x, y + PREVIEW_H, x, y, 4)
  local qx, qy = x + 12, y + PREVIEW_H - 8
  gfx.line(qx - 7, qy, qx + 7, qy, 4)
  gfx.line(qx - 9, qy - 2, qx - 4, qy - 2, 4)
  gfx.line(qx + 4, qy - 2, qx + 9, qy - 2, 4)
  local cam = settings.camAngle * RAD
  local half = math.atan(math.tan(settings.fov * RAD / 2) * H / math.sqrt(W * W + H * H))
  local len = PREVIEW_W - 16
  local cx, cy = qx + 4, qy - 1
  gfx.line(cx, cy, cx + math.cos(cam) * len, cy - math.sin(cam) * len, 4)
  gfx.line(cx, cy, cx + math.cos(cam + half) * len, cy - math.sin(cam + half) * len, 2)
  gfx.line(cx, cy, cx + math.cos(cam - half) * len, cy - math.sin(cam - half) * len, 2)
end

-- Stick deflection 0..1 against deg/s for one axis, scaled to its max velocity (printed in the corner)
local function drawRatePreview(x, y, keys)
  gfx.line(x, y, x + PREVIEW_W, y, 4)
  gfx.line(x + PREVIEW_W, y, x + PREVIEW_W, y + PREVIEW_H, 4)
  gfx.line(x + PREVIEW_W, y + PREVIEW_H, x, y + PREVIEW_H, 4)
  gfx.line(x, y + PREVIEW_H, x, y, 4)
  local rcRate, rate, expo = settings[keys[1]], settings[keys[2]], settings[keys[3]]
  local full = stickRate(1, rcRate, rate, expo)
  local w, h = PREVIEW_W - 2, PREVIEW_H - 2
  local px, py = x + 1, y + 1 + h
  for i = 1, RATE_STEPS do
    local s = i / RATE_STEPS
    local qx, qy = x + 1 + s * w, y + 1 + h - stickRate(s, rcRate, rate, expo) / full * h
    gfx.line(px, py, qx, qy, 4)
    px, py = qx, qy
  end
  gfx.text(x + 2, y + 2, string.format("%d", math.floor(full + 0.5)))
end

-- The two gimbals as the quad reads them, mode 2 order: yaw and throttle left, roll and pitch right
local GIMBAL = 20
local function drawGimbal(x, y, sx, sy)
  gfx.line(x, y, x + GIMBAL - 1, y, 4)
  gfx.line(x + GIMBAL - 1, y, x + GIMBAL - 1, y + GIMBAL - 1, 4)
  gfx.line(x + GIMBAL - 1, y + GIMBAL - 1, x, y + GIMBAL - 1, 4)
  gfx.line(x, y + GIMBAL - 1, x, y, 4)
  local half = (GIMBAL - 5) / 2
  gfx.rect(x + 1 + math.floor(half * (sx + 1) + 0.5), y + 1 + math.floor(half * (1 - sy) + 0.5), 3, 3, 4)
end

local function drawSticksPreview(x, y)
  local s = input.read()
  y = y + (PREVIEW_H - GIMBAL) // 2
  drawGimbal(x, y, s.rud, s.thr * 2 - 1)
  drawGimbal(x + PREVIEW_W - GIMBAL + 1, y, s.ail, s.ele)
end

-- The arm source live, and that the model arms with it: the sim's switch is the model's own
local function drawArmPreview(x, y)
  local on = input.arm()
  gfx.text(x + PREVIEW_W / 2, y + 2, on == false and "DISARMED" or "ARMED", "c", nil, on ~= false)
  gfx.text(x + PREVIEW_W / 2, y + 12, "THE MODEL", "c")
  gfx.text(x + PREVIEW_W / 2, y + 19, "ARMS TOO", "c")
  gfx.text(x + PREVIEW_W / 2, y + 26, "IF RF ON", "c")
end

local function open(items, title, parent)
  page = { items = items, title = title, selected = 1, first = 1, parent = parent }
end

local Settings = {}

function Settings.enter()
  open(TOP.items, TOP.title)
  editing = false
end

function Settings.run(event)
  local items = page.items
  local item = items[page.selected]
  if editing then
    if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
      editing = false
    else
      local d = List.step(event)
      if d ~= 0 then
        change(item, d)
      elseif item.source then
        -- Moving a stick, pot or slider picks it
        local list = sourcesOf(item)
        local name = Sources.moved(list)
        if name then
          settings[item.key] = name
          Sources.snapshot(list)
        end
      end
    end
  elseif event == EVT_VIRTUAL_EXIT then
    if page.parent then
      page = page.parent
    else
      Prefs.write(TOP.items)
      return "menu"
    end
  elseif event == EVT_VIRTUAL_ENTER then
    if item.page then
      open(item.page, item.label, page)
    else
      editing = true
      if item.source then
        Sources.snapshot(sourcesOf(item))
      end
    end
  else
    page.selected = List.move(page.selected, event, #items)
  end
  items = page.items
  local selected = page.selected

  local W, H = gfx.W, gfx.H
  local listW = W - PREVIEW_W - 4
  local rows = (H - List.TOP - 1) // ROW_H
  if selected < page.first then
    page.first = selected
  elseif selected >= page.first + rows then
    page.first = selected - rows + 1
  end
  local first = page.first
  gfx.clear()
  List.title(page.title)
  for i = first, math.min(#items, first + rows - 1) do
    local y = List.TOP + 1 + (i - first) * ROW_H
    local it = items[i]
    local sel = i == selected
    List.row(y, ROW_H, listW, it.label, sel and not editing)
    -- Selected: the whole row is inverted; editing: only the value
    gfx.text(listW - 1, y + 1, valueText(it), "r", nil, sel)
  end
  local axis = items[selected].axis
  if axis then
    drawRatePreview(W - PREVIEW_W - 1, List.TOP + 2, axis)
  elseif items[selected].sticks then
    drawSticksPreview(W - PREVIEW_W - 1, List.TOP + 2)
  elseif items[selected].arm then
    drawArmPreview(W - PREVIEW_W - 1, List.TOP + 2)
  else
    drawCameraPreview(W - PREVIEW_W - 1, List.TOP + 2)
  end
end

return Settings
