-- Pause menu over the paused flight: resume, the settings worth changing mid-run (applied at once, camera changes
-- showing in the view beside it), restart and quit. Loaded on pausing and dropped on resuming. Changes are saved
-- once flight is left (app.settingsChanged), not with flight in memory.
-- ENTER edits a setting, opens RATES or picks an action; NEXT/PREV change it, ENTER or EXIT ends editing.
-- EXIT leaves RATES; on the top page it resumes.

local app = ...

local gfx, List, settings = app.gfx, app.list, app.settings
local Edit = app.load("ui/edit", settings)

local ROW_H = 8
-- The top page's panel width: the view shows to its right
local PANEL_W = 66

local KEYS = { camAngle = true, fov = true, quality = true, angleMode = true, batterySim = true, fps = true }
local items = { { label = "RESUME", action = "resume" } }
for _, item in ipairs(app.load("core/items")) do
  if KEYS[item.key] or item.label == "RATES" then
    items[#items + 1] = item
  end
end
items[#items + 1] = { label = "RESTART", action = "restart" }
items[#items + 1] = { label = "QUIT", action = "quit" }

-- Current page: its items, selection and first row shown
local top = { items = items, selected = 1, first = 1 }
local page, editing = top, false

local Pause = {}

-- "resume", "restart" or "quit" once picked
function Pause.run(event)
  local item = page.items[page.selected]
  if editing then
    if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
      editing = false
    else
      local d = List.step(event)
      if d ~= 0 then
        Edit.change(item, d)
        app.settingsChanged = true
      end
    end
  elseif event == EVT_VIRTUAL_EXIT then
    if page == top then
      return "resume"
    end
    page = top
  elseif event == EVT_VIRTUAL_ENTER then
    if item.action then
      return item.action
    elseif item.page then
      page = { items = item.page, selected = 1, first = 1 }
    else
      editing = true
    end
  else
    page.selected = List.move(page.selected, event, #page.items)
  end
end

-- Over the view drawn behind it: the top page as a panel at the left, RATES over the whole screen
function Pause.draw()
  local list, selected = page.items, page.selected
  local H = gfx.H
  local w = page == top and PANEL_W or gfx.W
  local rows = H // ROW_H
  if selected < page.first then
    page.first = selected
  elseif selected >= page.first + rows then
    page.first = selected - rows + 1
  end
  local first = page.first
  gfx.rect(0, 0, w, H, 0)
  if page == top then
    gfx.line(w, 0, w, H - 1, 4)
  end
  for i = first, math.min(#list, first + rows - 1) do
    local y = (i - first) * ROW_H
    local it = list[i]
    local sel = i == selected
    List.row(y, ROW_H, w, it.label, sel and not editing)
    -- Selected: the whole row is inverted; editing: only the value
    if it.key then
      gfx.text(w - 1, y + 1, Edit.text(it), "r", nil, sel)
    elseif it.page then
      gfx.text(w - 1, y + 1, ">", "r", nil, sel)
    end
  end
end

return Pause
