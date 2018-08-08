local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
local Font = require("ui/font")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Battery = {}

function Battery:scheduleBatteryLevel()
    if G_reader_settings:isFalse("battery_alarm") then return end
    self.schedule_func = function()
        UIManager:scheduleIn(300, self.schedule_func)
        local threshold = G_reader_settings:readSetting("low_battery_threshold") or 20
        local powerd = Device:getPowerDevice()
        local battery_capacity = powerd:getCapacity()
        if self.battery_warning ~= true and battery_capacity <= threshold then
            local choose_action
            choose_action = ButtonDialogTitle:new{
                modal = true,
                title = T(_("The battery is getting low.\n%1% remaining."), battery_capacity),
                title_align = "center",
                title_face = Font:getFace("infofont"),
                dismissable = false,
                buttons = {
                    {
                        {
                            text = _("Dismiss"),
                            callback = function()
                                UIManager:close(choose_action)
                                self.battery_warning = true
                                UIManager:scheduleIn(300, self.schedule_func)
                            end,
                        },
                    },
                }
            }
            UIManager:show(choose_action)
            self:unScheduleBatteryLevel()
        elseif self.battery_warning and battery_capacity > threshold then
            self.battery_warning = false
        end
    end
    self.schedule_func()
end

function Battery:unScheduleBatteryLevel()
    UIManager:unschedule(self.schedule_func)
    self.battery_warning = false
end

function Battery:onResume()
    Battery:scheduleBatteryLevel()
end

function Battery:onSuspend()
    if self.schedule_func then
        UIManager:unschedule(self.schedule_func)
    end
end

local LowBatteryWidget = Widget:new{
    name = "lowbatterywidget",
}

function LowBatteryWidget:onResume()
    Battery:onResume()
end

function LowBatteryWidget:onSuspend()
    Battery:onSuspend()
end

function LowBatteryWidget:scheduleBatteryLevel()
    Battery:scheduleBatteryLevel()
end

function LowBatteryWidget:unScheduleBatteryLevel()
    Battery:unScheduleBatteryLevel()
end

return LowBatteryWidget
