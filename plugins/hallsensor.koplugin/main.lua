local Device = require("device")
local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local powerd = Device:getPowerDevice()
local _ = require("gettext")

if powerd.hall_sensor_file == nil then
    return { disabled = true, }
end

local HallSensor = WidgetContainer:extend{
    name = "hallsensor",
}

function HallSensor:onDispatcherRegisterActions()
    Dispatcher:registerAction("hall_sensor", {category="none", event="ToggleHallSensor", title=_("Toggle hall sensor"), device=true,})
end

function HallSensor:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function HallSensor:getHallSensor()
    local int = powerd:read_int_file(powerd.hall_sensor_file)
    return int == 1
end

function HallSensor:onToggleHallSensor()
    local stat = self:getHallSensor()
    local fd = io.open(powerd.hall_sensor_file, "we")
    if fd then
        fd:write(stat and 0 or 1)
        fd:close()
    end
end

function HallSensor:addToMainMenu(menu_items)
    menu_items.hall_sensor = {
        text = _("Hall Sensor"),
        sorting_hint = "more_tools",
        keep_menu_open = true,
        checked_func = function() return self:getHallSensor() end,
        callback = function() self:onToggleHallSensor() end,
        separator = true,
    }
end

return HallSensor
