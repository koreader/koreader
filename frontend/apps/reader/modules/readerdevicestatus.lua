local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
local Font = require("ui/font")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local UIManager = require("ui/uimanager")
local powerd = Device:getPowerDevice()
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderDeviceStatus = InputContainer:new{
}

function ReaderDeviceStatus:init()
    self.battery_watchable = powerd:getCapacity() > 0 or powerd:isCharging()
    if self.battery_watchable then
        self:scheduleBatteryLevel()
        self.ui.menu:registerToMainMenu(self)
    end
end

function ReaderDeviceStatus:addToMainMenu(menu_items)
    menu_items.battery = {
        text = _("Low battery alarm"),
        sub_item_table = {
            {
                text = _("Enable"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("battery_alarm")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("battery_alarm")
                    if G_reader_settings:nilOrTrue("battery_alarm") then
                        self:scheduleBatteryLevel()
                    else
                        self:unScheduleBatteryLevel()
                    end
                end,
            },
            {
                text = _("Low battery threshold"),
                enabled_func = function() return G_reader_settings:nilOrTrue("battery_alarm") end,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local curr_items = G_reader_settings:readSetting("low_battery_threshold") or 20
                    local battery_spin = SpinWidget:new {
                        width = Screen:getWidth() * 0.6,
                        value = curr_items,
                        value_min = 5,
                        value_max = 90,
                        value_hold_step = 10,
                        ok_text = _("Set threshold"),
                        title_text = _("Low battery threshold"),
                        callback = function(battery_spin)
                            G_reader_settings:saveSetting("low_battery_threshold", battery_spin.value)
                            powerd:setDissmisBatteryStatus(false)
                        end
                    }
                    UIManager:show(battery_spin)
                end,
            },
        },
    }
end

function ReaderDeviceStatus:scheduleBatteryLevel()
    if G_reader_settings:nilOrTrue("battery_alarm") and self.battery_watchable then
        self.check_low_battery = function()
            UIManager:scheduleIn(300, self.check_low_battery)
            local threshold = G_reader_settings:readSetting("low_battery_threshold") or 20
            local battery_capacity = powerd:getCapacity()
            if powerd:getDissmisBatteryStatus() ~= true and battery_capacity <= threshold then
                local low_battery_info
                low_battery_info = ButtonDialogTitle:new {
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
                                    UIManager:close(low_battery_info)
                                    powerd:setDissmisBatteryStatus(true)
                                    UIManager:scheduleIn(300, self.check_low_battery)
                                end,
                            },
                        },
                    }
                }
                UIManager:show(low_battery_info)
                self:unScheduleBatteryLevel()
            elseif powerd:getDissmisBatteryStatus() and battery_capacity > threshold then
                powerd:setDissmisBatteryStatus(false)
            end
        end
        self.check_low_battery()
    end
end

function ReaderDeviceStatus:unScheduleBatteryLevel()
    if self.check_low_battery then
        UIManager:unschedule(self.check_low_battery)
        powerd:setDissmisBatteryStatus(false)
    end
end

function ReaderDeviceStatus:onResume()
    self:scheduleBatteryLevel()
end

function ReaderDeviceStatus:onSuspend()
    if self.check_low_battery then
        UIManager:unschedule(self.check_low_battery)
    end
end

function ReaderDeviceStatus:onCloseWidget()
    if self.check_low_battery then
        UIManager:unschedule(self.check_low_battery)
    end
end

return ReaderDeviceStatus
