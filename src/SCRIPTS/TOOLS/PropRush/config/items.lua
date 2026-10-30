-- Every editable setting (config/settings) in menu order: the display page (config/display) with the RATES and
-- CONTROLS pages (config/rates, config/controls) as sub-pages. An item with a page opens it. Loaded only to read and
-- write the settings file and on the settings screen; the pause menu loads its pages on their own.
local load = ...

local items = load("config/display")
items[#items + 1] = { label = "RATES", page = load("config/rates") }
items[#items + 1] = { label = "CONTROLS", page = load("config/controls") }

return items
