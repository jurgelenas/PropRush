local app = ...

local gfx = app.gfx

local Intro = {}

function Intro.run(event)
  if event == EVT_VIRTUAL_EXIT then
    return "quit"
  elseif event == EVT_VIRTUAL_ENTER then
    return "menu"
  end

  local W, FH = gfx.W, gfx.FH
  gfx.clear()
  gfx.text(W / 2, 2, "FPV SIM", "c", true)
  gfx.text(W / 2, 14, "WARNING: your sticks still", "c")
  gfx.text(W / 2, 14 + FH + 1, "drive the model outputs.", "c")
  gfx.text(W / 2, 14 + 2 * (FH + 1), "Disarm or turn RF off.", "c")
  gfx.text(W / 2, gfx.H - FH - 1, "ENTER continue  EXIT quit", "c", nil, true)
end

return Intro
