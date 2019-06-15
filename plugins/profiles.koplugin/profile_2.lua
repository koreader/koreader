local Device = require("device")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")

local night_mode = G_reader_settings:isTrue("night_mode")
if not night_mode then
    Screen:toggleNightMode()
    UIManager:setDirty("all", "full")
    G_reader_settings:saveSetting("night_mode", true)
end

local powerd = Device:getPowerDevice()
powerd:setIntensity(1)
powerd:setWarmth(100)
