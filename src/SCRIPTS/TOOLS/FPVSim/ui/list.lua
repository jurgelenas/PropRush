-- Shared pieces of the menu screens: title bar, list rows, key navigation

local gfx = ...

local List = { TOP = 10 }

function List.title(text)
  gfx.rect(0, 0, gfx.W, List.TOP, 4)
  gfx.text(2, (List.TOP - gfx.FH) // 2, text, nil, nil, true)
end

-- +1 for NEXT, -1 for PREV (held keys repeat), 0 otherwise
function List.step(event)
  if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT then
    return 1
  elseif event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT then
    return -1
  end
  return 0
end

-- Index moved by a navigation key, wrapping around n entries
function List.move(index, event, n)
  return (index - 1 + List.step(event)) % n + 1
end

-- Row of width w at y, h pixels high, its text centred upright, inverted when selected
function List.row(y, h, w, text, selected, big)
  if selected then
    gfx.rect(0, y, w, h, 4)
  end
  gfx.text(2, y + (h - (big and gfx.BIG_FH or gfx.FH)) // 2, text, nil, big, selected)
end

-- Lines of small text from y down
function List.lines(x, y, lines)
  for i = 1, #lines do
    gfx.text(x, y + (i - 1) * (gfx.FH + 1), lines[i])
  end
end

return List
