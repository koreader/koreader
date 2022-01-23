local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local powerd = Device:getPowerDevice()
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderDeviceStatus = InputContainer:new{
battery_confirm_box = nil,
memory_confirm_box = nil,
}

function ReaderDeviceStatus:init()
    if Device:hasBattery() then
        self.battery_interval = G_reader_settings:readSetting("device_status_battery_interval", 10)
        self.battery_threshold = G_reader_settings:readSetting("device_status_battery_threshold", 20)
        self.battery_threshold_high = G_reader_settings:readSetting("device_status_battery_threshold_high", 100)
        self.checkLowBatteryLevel = function()
            local is_charging = powerd:isCharging()
            local battery_capacity = powerd:getCapacity()
            if powerd:getDismissBatteryStatus() == true then  -- alerts dismissed
                if (is_charging and battery_capacity <= self.battery_threshold_high) or
                   (not is_charging and battery_capacity > self.battery_threshold) then
                    powerd:setDismissBatteryStatus(false)
                end
            else
                if (is_charging and battery_capacity > self.battery_threshold_high) or
                   (not is_charging and battery_capacity <= self.battery_threshold) then
                    if self.battery_confirm_box then
                        UIManager:close(self.battery_confirm_box)
                    end
                    self.battery_confirm_box = ConfirmBox:new {
                        text = is_charging and T(_("High battery level: %1%\n\nDismiss battery level alert?"), battery_capacity)
                                            or T(_("Low battery level: %1%\n\nDismiss battery level alert?"), battery_capacity),
                        ok_text = _("Dismiss"),
                        dismissable = false,
                        ok_callback = function()
                            powerd:setDismissBatteryStatus(true)
                        end,
                    }
                    UIManager:show(self.battery_confirm_box)
                end
            end
            UIManager:scheduleIn(self.battery_interval * 60, self.checkLowBatteryLevel)
        end
        self:startBatteryChecker()
    end

    if not Device:isAndroid() then
        self.memory_interval = G_reader_settings:readSetting("device_status_memory_interval", 5)
        self.memory_threshold = G_reader_settings:readSetting("device_status_memory_threshold", 100)
        self.checkHighMemoryUsage = function()
            local statm = io.open("/proc/self/statm", "r")
            if statm then
                local dummy, rss = statm:read("*number", "*number")
                statm:close()
                rss = math.floor(rss * 4096 / 1024 / 1024)
                if rss >= self.memory_threshold then
                    if self.memory_confirm_box then
                        UIManager:close(self.memory_confirm_box)
                    end
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
                            self.memory_confirm_box = ConfirmBox:new {
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
                            }
                            UIManager:show(self.memory_confirm_box)
                        end
                    else
                        self.memory_confirm_box = ConfirmBox:new {
                            text = T(_("High memory usage: %1 MB\n\nExit KOReader?"), rss),
                            ok_text = _("Exit"),
                            dismissable = false,
                            ok_callback = function()
                                self.ui:handleEvent(Event:new("Exit"))
                            end,
                        }
                        UIManager:show(self.memory_confirm_box)
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
                text = _("Battery level"),
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
                    return T(_("Check interval: %1 min"), self.battery_interval)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_battery_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
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
                    return T(_("Thresholds: %1% – %2%"), self.battery_threshold, self.battery_threshold_high)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_battery_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
                    local thresholds_widget
                    thresholds_widget = DoubleSpinWidget:new{
                        title_text = _("Battery level alert thresholds"),
                        info_text = _([[
Low level threshold is checked when the device is not charging.
High level threshold is checked when the device is charging.]]),
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
                            if not left_value then -- "Default" button pressed
                                left_value = 20
                                right_value = 100
                            end
                            self.battery_threshold = left_value
                            self.battery_threshold_high = right_value
                            G_reader_settings:saveSetting("device_status_battery_threshold", self.battery_threshold)
                            G_reader_settings:saveSetting("device_status_battery_threshold_high", self.battery_threshold_high)
                            UIManager:close(thresholds_widget)
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
                    return T(_("Check interval: %1 min"), self.memory_interval)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
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
                            UIManager:scheduleIn(self.memory_interval * 60, self.checkHighMemoryUsage)
                        end,
                    })
                end,
            })
        table.insert(menu_items.device_status_alarm.sub_item_table,
            {
                text_func = function()
                    return T(_("Threshold: %1 MB"), self.memory_threshold)
                end,
                enabled_func = function()
                    return G_reader_settings:isTrue("device_status_memory_alarm")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
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
