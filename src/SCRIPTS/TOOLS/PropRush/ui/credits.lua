-- NEXT/PREV scroll when the lines do not fit, EXIT goes back to the menu

local app = ...

local gfx = app.gfx
local List = app.load("ui/list", gfx)

local LINES = {
  "PROPRUSH " .. app.load("version"),
  "FPV drone simulator",
  "",
  "Licence: GPL-3.0",
  "github.com/jurgelenas/",
  "  PropRush",
}

local LINE_H = gfx.FH + 1
local SHOWN = (gfx.H - List.TOP - 2) // LINE_H
local scroll = 0

local Credits = {}

function Credits.run(event)
  if event == EVT_VIRTUAL_EXIT then
    return "menu"
  end
  scroll = math.max(0, math.min(#LINES - SHOWN, scroll + List.step(event)))

  gfx.clear()
  List.title("CREDITS")
  for i = 1, math.min(SHOWN, #LINES - scroll) do
    gfx.text(2, List.TOP + 2 + (i - 1) * LINE_H, LINES[scroll + i])
  end
end

return Credits
