-- compatibility wrapper
local Screen = require("device").screen

-- set eink flag for this screen
local is_eink = G_reader_settings:readSetting("eink")
Screen.eink = (is_eink == nil) and true or is_eink

return Screen
