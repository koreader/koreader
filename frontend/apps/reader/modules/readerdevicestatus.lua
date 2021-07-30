local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local powerd = Device:getPowerDevice()
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderDeviceStatus = InputContainer:new{
}

function ReaderDeviceStatus:init()
    if Device:hasBattery() then
        self.battery_interval = G_reader_settings:readSetting("device_status_battery_interval") or 10
        self.battery_threshold = G_reader_settings:readSetting("device_status_battery_threshold") or 20
        self.battery_threshold_high = G_reader_settings:readSetting("device_status_battery_threshold_high") or 100
        self.checkLowBatteryLevel = function()
            local battery_capacity = powerd:getCapacity()
            if powerd:getDismissBatteryStatus() == true then  -- alerts dismissed
                if (powerd:isCharging() and battery_capacity <= self.battery_threshold_high) or
                   (not powerd:isCharging() and battery_capacity > self.battery_threshold) then
                    powerd:setDismissBatteryStatus(false)
                end
            else
                if powerd:isCharging() and battery_capacity > self.battery_threshold_high then
                    UIManager:show(ConfirmBox:new {
                        text = T(_("High battery level: %1%\n\nDismiss high battery alert?"), battery_capacity),
                        ok_text = _("Dismiss"),
                        dismissable = false,
                        ok_callback = function()
                            powerd:setDismissBatteryStatus(true)
                        end,
                    })
                elseif not powerd:isCharging() and battery_capacity <= self.battery_threshold then
                    UIManager:show(ConfirmBox:new {
                        text = T(_("Low battery level: %1%\n\nDismiss low battery alert?"), battery_capacity),
                        ok_text = _("Dismiss"),
                        dismissable = false,
                        cancel_callback = function()
                            powerd:setDismissBatteryStatus(true)
                        end,
                    })
                end
            end
            UIManager:scheduleIn(self.battery_interval * 60, self.checkLowBatteryLevel)
        end
        self:startBatteryChecker()
    end

    if not Device:isAndroid() then
        self.memory_interval = G_reader_settings:readSetting("device_status_memory_interval") or 5
        self.memory_threshold = G_reader_settings:readSetting("device_status_memory_threshold") or 100
        self.checkHighMemoryUsage = function()
            local statm = io.open("/proc/self/statm", "r")
            if statm then
                local dummy, rss = statm:read("*number", "*number")
                statm:close()
                rss = math.floor(rss * 4096 / 1024 / 1024)
                if rss >= self.memory_threshold then
                    if Device:canRestart() then
                        if UIManager:getTopWidget() == "ReaderUI"
                           and G_reader_settings:isTrue("device_status_memory_auto_restart") then
                            UIManager:show(InfoMessage:new{
                                text = _("High memory usage!\n\nKOReader is restarting…"),
                                icon = "notice-warning",
                            })
                            UIManager:nextTick(function()
                                self.ui:handleEvent(Event:new("Restart"))
                            end)
                        else
                            UIManager:show(ConfirmBox:new {
                                text = T(_("High memory usage: %1 MB\n\nRestart KOReader?"), rss),
                                ok_text = _("Restart"),
                                dismissable = false,
                                ok_callback = function()
                                    UIManager:show(InfoMessage:new{
                                        text = _("High memory usage!\n\nKOReader is restarting…"),
                                        icon = "notice-warning",
                                    })
                                    UIManager:nextTick(function()
                                        self.ui:handleEvent(Event:new("Restart"))
                                    end)
                                end,
                            })
                        end
                    else
                        UIManager:show(ConfirmBox:new {
                            text = T(_("High memory usage: %1 MB\n\nExit KOReader?"), rss),
                            ok_text = _("Exit"),
                            dismissable = false,
                            ok_callback = function()
                                self.ui:handleEvent(Event:new("Exit"))
                            end,
                        })
                    end
                end
            end
            UIManager:scheduleIn(self.memory_interval * 60, self.checkHighMemoryUsage)
        end
        self:startMemoryChecker()
    end

    self.ui.menu:registerToMainMenu(self)
end

function ReaderDeviceStatus:addToMainMenu(menu_items)
    menu_items.device_status_alarm = {
        text = _("Device status alerts"),
        sub_item_table = {},
    }
    if Device:hasBattery() then
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text = _("Low or high battery level"),
                checked_func = function()
                    return G_reader_settings:isTrue("device_status_battery_alarm")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("device_status_battery_alarm")
                    if G_reader_settings:isTrue("device_status_battery_alarm") then
                        self:startBatteryChecker()
                    else
                        self:stopBatteryChecker()
                        powerd:setDismissBatteryStatus(false)
                    end
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text_func = function()
                    return T(_("Check interval (%1 min)"), self.battery_interval)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_battery_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = self.battery_interval,
                        value_min = 1,
                        value_max = 60,
                        default_value = 10,
                        value_hold_step = 5,
                        title_text = _("Battery check interval"),
                        callback = function(spin)
                            self.battery_interval = spin.value
                            G_reader_settings:saveSetting("device_status_battery_interval", self.battery_interval)
                            touchmenu_instance:updateItems()
                            powerd:setDismissBatteryStatus(false)
                            UIManager:scheduleIn(self.battery_interval * 60, self.checkLowBatteryLevel)
                        end,
                    })
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text_func = function()
                    return T(_("Thresholds (%1% – %2%)"), self.battery_threshold, self.battery_threshold_high)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_battery_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
                    local thresholds_widget = DoubleSpinWidget:new{
                        title_text = _("Battery level alert thresholds"),
                        info_text = _([[
Low level threshold is checked when the device is not charging.
High level threshold is checked when the device is charging.]]),
                        width = math.floor(Screen:getWidth() * 0.8),
                        left_text = _("Low"),
                        left_value = self.battery_threshold,
                        left_min = 1,
                        left_max = self.battery_threshold_high,
                        left_default = 20,
                        left_hold_step = 5,
                        right_text = _("High"),
                        right_value = self.battery_threshold_high,
                        right_min = self.battery_threshold,
                        right_max = 100,
                        right_default = 100,
                        right_hold_step = 5,
                        default_values = true,
                        callback = function(left_value, right_value)
                            if not left_value then return end -- "Use defaults" pressed
                            self.battery_threshold = left_value
                            self.battery_threshold_high = right_value
                            G_reader_settings:saveSetting("device_status_battery_threshold", self.battery_threshold)
                            G_reader_settings:saveSetting("device_status_battery_threshold_high", self.battery_threshold_high)
                            touchmenu_instance:updateItems()
                            powerd:setDismissBatteryStatus(false)
                        end,
                    }
                    UIManager:show(thresholds_widget)
                end,
                separator = true,
            })
    end
    if not Device:isAndroid() then
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text = _("High memory usage"),
                checked_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("device_status_memory_alarm")
                    if G_reader_settings:isTrue("device_status_memory_alarm") then
                        self:startMemoryChecker()
                    else
                        self:stopMemoryChecker()
                    end
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text_func = function()
                    return T(_("Check interval (%1 min)"), self.memory_interval)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = self.memory_interval,
                        value_min = 1,
                        value_max = 60,
                        default_value = 5,
                        value_hold_step = 5,
                        title_text = _("Memory check interval"),
                        callback = function(spin)
                            self.memory_interval = spin.value
                            G_reader_settings:saveSetting("device_status_memory_interval", self.memory_interval)
                            touchmenu_instance:updateItems()
                            UIManager:scheduleIn(self.memory_interval*60, self.checkHighMemoryUsage)
                        end,
                    })
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text_func = function()
                    return T(_("Threshold (%1 MB)"), self.memory_threshold)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        width = math.floor(Screen:getWidth() * 0.6),
                        value = self.memory_threshold,
                        value_min = 20,
                        value_max = 500,
                        default_value = 100,
                        value_step = 5,
                        value_hold_step = 10,
                        title_text = _("Memory alert threshold"),
                        callback = function(spin)
                            self.memory_threshold = spin.value
                            G_reader_settings:saveSetting("device_status_memory_threshold", self.memory_threshold)
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text = _("Automatic restart"),
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm") and Device:canRestart()
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("device_status_memory_auto_restart")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("device_status_memory_auto_restart")
                end,
            })
    end
end

function ReaderDeviceStatus:startBatteryChecker()
    if G_reader_settings:isTrue("device_status_battery_alarm") then
        self.checkLowBatteryLevel()
    end
end

function ReaderDeviceStatus:stopBatteryChecker()
    if self.checkLowBatteryLevel then
        UIManager:unschedule(self.checkLowBatteryLevel)
    end
end

function ReaderDeviceStatus:startMemoryChecker()
    if G_reader_settings:isTrue("device_status_memory_alarm") then
        self.checkHighMemoryUsage()
    end
end

function ReaderDeviceStatus:stopMemoryChecker()
    if self.checkHighMemoryUsage then
        UIManager:unschedule(self.checkHighMemoryUsage)
    end
end

function ReaderDeviceStatus:onResume()
    self:startBatteryChecker()
    self:startMemoryChecker()
end

function ReaderDeviceStatus:onSuspend()
    self:stopBatteryChecker()
    self:stopMemoryChecker()
end

function ReaderDeviceStatus:onCloseWidget()
    self:stopBatteryChecker()
    self:stopMemoryChecker()
end

return ReaderDeviceStatus
