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
    if powerd:getCapacity() > 0 or powerd:isCharging() then
        self.checkLowBattery = function()
            local threshold = G_reader_settings:readSetting("low_battery_threshold") or 20
            local battery_capacity = powerd:getCapacity()
            if powerd:isCharging() then
                powerd:setDissmisBatteryStatus(false)
            elseif powerd:getDissmisBatteryStatus() ~= true and battery_capacity <= threshold then
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
                                    UIManager:scheduleIn(300, self.checkLowBattery)
                                end,
                            },
                        },
                    }
                }
                UIManager:show(low_battery_info)
                return
            elseif powerd:getDissmisBatteryStatus() and battery_capacity > threshold then
                powerd:setDissmisBatteryStatus(false)
            end
            UIManager:scheduleIn(300, self.checkLowBattery)
        end
        self.ui.menu:registerToMainMenu(self)
        self:startBatteryChecker()
    else
        self.checkLowBattery = nil
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
                        self:startBatteryChecker()
                    else
                        self:stopBatteryChecker()
                        powerd:setDissmisBatteryStatus(false)
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
                        width = math.floor(Screen:getWidth() * 0.6),
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

function ReaderDeviceStatus:startBatteryChecker()
    if G_reader_settings:nilOrTrue("battery_alarm") and self.checkLowBattery then
        self.checkLowBattery()
    end
end

function ReaderDeviceStatus:stopBatteryChecker()
    if self.checkLowBattery then
        UIManager:unschedule(self.checkLowBattery)
    end
end

function ReaderDeviceStatus:onResume()
    self:startBatteryChecker()
end

function ReaderDeviceStatus:onSuspend()
    self:stopBatteryChecker()
end

function ReaderDeviceStatus:onCloseWidget()
    self:stopBatteryChecker()
end

return ReaderDeviceStatus
