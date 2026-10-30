-- In place of the game on EdgeTX older than main.lua's minimum: any key quits.
local app = ...

local gfx = app.gfx

local Firmware = {}
-- This radio's version
local found

function Firmware.enter(version)
  found = version
end

function Firmware.run(event)
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then
    return "quit"
  end

  local W, FH = gfx.W, gfx.FH
  gfx.clear()
  gfx.text(W / 2, 2, "PROPRUSH", "c", true)
  gfx.text(W / 2, 16, "Needs EdgeTX " .. app.minVersion, "c")
  gfx.text(W / 2, 16 + FH + 1, "or newer. This radio", "c")
  gfx.text(W / 2, 16 + 2 * (FH + 1), "runs " .. found .. ":", "c")
  gfx.text(W / 2, 16 + 3 * (FH + 1), "update the firmware.", "c")
  gfx.text(W / 2, gfx.H - FH - 1, "EXIT quit", "c", nil, true)
end

return Firmware
