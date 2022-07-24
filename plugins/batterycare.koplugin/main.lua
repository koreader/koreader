--[[--
@module koplugin.batterycare

Plugin for tuning the threshold for battery charging.
]]
local Device = require("device")

if not Device:canControlCharge() then
    return { disabled = true }
end

local Dispatcher = require("dispatcher")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local powerd = Device:getPowerDevice()

local default_stop_thr = 95
local default_start_thr = 80 -- set this a bit lower as `default_aux_stop_thr`, for reasons (dc/dc step up efficiency ...)
local default_aux_stop_thr = 95
local default_aux_start_thr = 90
local default_balance_thr = 25 -- balance if aux batt is below this

local KOBO_WAKEUP_OFFSET_S = 16   -- Offset on Kobo between wakeup and suspend
-- Time for a scheduled wakeup, when a charger is connected.
-- As long a charger is connected, we have no need for extensive power saving, so a shorter
-- time will help not to exceed the upper charge limit.
-- For example: on a Sage, with an noname charger we can expect around 1%/min. Charging on a poor
-- laptop might give us 0.5%/min or less.
local WAKEUP_TIMER_SECONDS = 60 - KOBO_WAKEUP_OFFSET_S

local BatteryCare = WidgetContainer:new{
    name = "batterycare",
    is_doc_only = false,
}

function BatteryCare:init()
    if not Device:canControlCharge() then return end

    self.can_pretty_print = lfs.attributes("./fbink", "mode") == "file" and true or false

    self.enabled = G_reader_settings:isTrue("battery_care")
    self.show_capacity_in_sleep = G_reader_settings:isTrue("battery_care_show_capacity_in_sleep")

    self.battery_care_stop_thr = G_reader_settings:readSetting("battery_care_stop_thr",
        default_stop_thr)
    self.battery_care_start_thr = G_reader_settings:readSetting("battery_care_start_thr",
        default_start_thr)

    self.battery_care_aux_stop_thr = G_reader_settings:readSetting("battery_care_aux_stop_thr",
        default_aux_stop_thr)
    self.battery_care_aux_start_thr = G_reader_settings:readSetting("battery_care_aux_start_thr",
        default_aux_start_thr)
    self.battery_care_balance_thr = G_reader_settings:readSetting("battery_care_balance_thr",
        default_balance_thr)

    self.ui.menu:registerToMainMenu(self)

    self:task() -- Schedules itself, if BatteryCare is enabled.
end

function BatteryCare:onDispatcherRegisterActions()
    Dispatcher:registerAction("Charge Battery: disable",
        {category="none", event="BatteryCareEnable", title=_("Battery care enable"), device=true})
    Dispatcher:registerAction("Charge Battery: enable",
        {category="none", event="BatteryCareDisable", title=_("Battery care disable "), device=true})
    Dispatcher:registerAction("Charge Battery: toggle",
        {category="none", event="BatteryCareToggle", title=_("Battery care toggle"), device=true})
    Dispatcher:registerAction("Charge Battery: once on",
        {category="none", event="BatteryCareOnceOn", title=_("Battery care charge once on"), device=true})
    Dispatcher:registerAction("Charge Battery: once off",
        {category="none", event="BatteryCareOnceOff", title=_("Battery care charge once off"), device=true})
    Dispatcher:registerAction("Charge Battery: once toggle",
        {category="none", event="BatteryCareOnceToggle", title=_("Battery care once toggle"), device=true})
end

function BatteryCare:onBatteryCareEnable()
    self.enabled = true
    G_reader_settings:saveSetting("battery_care", true)
    -- don't save this setting!!!
    self.charge_once = false
    self:unschedule_task()
    self:task()
end

function BatteryCare:onBatteryCareDisable()
    self.enabled = false
    G_reader_settings:saveSetting("battery_care", false)
    self.charge_once = false
    self:unschedule_task()
end

function BatteryCare:onBatteryCareToggle()
    self.enabled = not G_reader_settings:isTrue("battery_care")
    G_reader_settings:saveSetting("battery_care", self.enabled)
    self.charge_once = false
    self:unschedule_task()
    self:task()
end

function BatteryCare:onBatteryCareOnceOn()
    -- don't save this setting!!!
    self.charge_once = true
    self:unschedule_task()
    self:task()
end

function BatteryCare:onBatteryCareOnceOff()
    -- don't save this setting!!!
    self.charge_once = false
    self:unschedule_task()
    self:task()
end

function BatteryCare:onBatteryCareOnceToggle()
    -- don't save this setting!!!
    self.charge_once = not self.charge_once
    self:unschedule_task()
    self:task()
end

function BatteryCare:schedule_task()
    -- schedule the same time as footer update, to reduce wakeups from standby.
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.task, self)
end

function BatteryCare:unschedule_task()
    UIManager:unschedule(self.task)
end

function BatteryCare:printMessage(enabled)
    if enabled == false then
        self.message_old_capacity = -1
    end

    if not self.can_pretty_print or not self.show_capacity_in_sleep then
        return
    end

    local curr_charging = powerd:isCharging()
    local aux_charging = powerd:isAuxCharging()

    if self.message_old_capacity == self.curr_capacity
        and self.message_old_aux_capacity == self.curr_aux_capacity
        and self.message_old_charging == curr_charging
        and self.message_old_aux_charging == aux_charging then
        return
    end

    local message
    local charge_symbol = "↯"
    if self.curr_aux_capacity then
        message = string.format(" %s%d%% %s%d%% ",
            curr_charging and charge_symbol or " ", self.curr_capacity,
            aux_charging and charge_symbol or " ", self.curr_aux_capacity)
    else
        message = string.format(" %s%d%% ",
            curr_charging and charge_symbol or " ", self.curr_capacity)
    end

    self.message_old_capacity = self.curr_capacity
    self.message_old_aux_capacity = self.curr_aux_capacity
    self.message_old_charging = curr_charging
    self.message_old_aux_charging = aux_charging

    -- Correct lenght of message by utf8 encoded symbols ("↯")
    local charge_symbol_len = #charge_symbol - 1
    local message_len = #message
        - (curr_charging == true and charge_symbol_len or 0)
        - (aux_charging == true and charge_symbol_len or 0)
    message = string.format("./fbink -q -F TEWI -x -%s '%s'", tostring(message_len), message)
    os.execute(message)
    logger.dbg("BatteryCare: Screensaver", message)
end

function BatteryCare:scheduleWakeupCall(enabled, show_soon)
    -- We will do wakeup from suspend every WAKEUP_TIMER_SECONDS if connected to an external charger or
    -- if the internal battery is charged from the aux battery. Then we can check and set the new
    -- charging state.
    local function wakeupCall()
        if Device:canSuspend() then
            -- self:onSuspend() will do that will print the capacity message in screensaver
            UIManager:scheduleIn(1, UIManager.suspend, UIManager) -- and go back to sleep
        end
    end

    if Device.wakeup_mgr then
        Device.wakeup_mgr:removeTask(nil, nil, wakeupCall)
    end

    if not enabled or not Device.wakeup_mgr then
        logger.dbg("BatteryCare: don't schedule wakeup call")
        return
    end

    -- Schedule a wakeup if necessary, when going to suspend.
    local wakeup_timer_seconds
    if powerd:isCharging() then
        -- If charging from an external charger or aux battery use the default value
        wakeup_timer_seconds = WAKEUP_TIMER_SECONDS
    else
        -- If _not_ charging ...
        if powerd.device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            -- ... and with an aux battery for a _long_ sleeping period: It is desireable to load
            -- the internal battery (from the aux batt) if its capacity drops.
            wakeup_timer_seconds = 6 * 3600 -- four times a day, maybe this can be reduced to once a day
        else
            -- ... and no aux battery present wake once per day
            wakeup_timer_seconds = 24 * 3600
        end
    end
    -- A Kobo Sage needs at least KOBO_WAKEUP_OFFSET_S seconds betweeen wakeup and suspend
    -- Should be no problem, as our shortest wakeup will be around a minute, but for further experiments ...
    Device.wakeup_mgr:addTask(math.max(wakeup_timer_seconds, KOBO_WAKEUP_OFFSET_S), wakeupCall)

    -- Show capacity after drawing screensaver
    if show_soon then
        local print_scheduling_counter = 0
        local function print_message_soon()
            if UIManager:getTopWidget() == "ScreenSaver" then
                self:printMessage()
            elseif print_scheduling_counter < 4 then
                print_scheduling_counter = print_scheduling_counter + 1
                logger.dbg("BatteryCare: print_scheduling_counter", print_scheduling_counter)
                UIManager:scheduleIn(0.5, print_message_soon)
            end
        end

        UIManager:tickAfterNext(print_message_soon)
    end
end

function BatteryCare:onExit()
    logger.dbg("BatteryCare: onExit/onRestart/onReboot")
    self:unschedule_task()
    self:scheduleWakeupCall(false, false) -- no wakeup
    powerd:charge(true, true) -- restore default behaviour
end

BatteryCare.onRestart = BatteryCare.onExit
BatteryCare.onReboot = BatteryCare.onExit
-- no BatteryCare.onPowerOff as we don't want the cover to be sucked out

function BatteryCare:onEnterStandby()
    self:unschedule_task()
end

function BatteryCare:onLeaveStandby()
    self:task()
end

function BatteryCare:onSuspend()
    logger.dbg("BatteryCare: onSuspend")
    self:task()
    self:unschedule_task()
    self:scheduleWakeupCall(true, self.show_capacity_in_sleep)
end

function BatteryCare:onResume()
    logger.dbg("BatteryCare: onResume/onLeaveStandby")
    logger.dbg("BatteryCare: isCharging", tostring(powerd:isCharging()), "isAuxCharging", tostring(powerd:isAuxCharging()))
    self:scheduleWakeupCall(false, false)
    self:task() -- is not scheduled here

    self:printMessage(false)
end

function BatteryCare:onCharging()
    logger.dbg("BatteryCare: onCharging/onNotCharging UsbPlugIn/Out")

    if UIManager:getTopWidget() == "ScreenSaver" then
        self:task()
        self:printMessage()
        self:scheduleWakeupCall(true, false)
    end

    -- Give the firmware some time (at least less than standby time) to calculate the new state
    UIManager:scheduleIn(0.5, self.task, self) -- task gets called in 0.5s and then schedules itself on a full minute
end

BatteryCare.onNotCharging = BatteryCare.onCharging
BatteryCare.onUsbPlugIn = BatteryCare.onCharging
BatteryCare.onUsbPlugOut = BatteryCare.onCharging

function BatteryCare:setThresholds(touchmenu_instance, title, info, lower, upper, lower_default, upper_default, value_min)
    local threshold_spinner = DoubleSpinWidget:new {
        title_text = title,
        info_text = info,
        left_text = _("Start"),
        left_value = self[lower] or lower_default,
        left_default = lower_default,
        left_min = value_min or 10,
        left_max = 100,
        left_hold_step = 5,
        right_text = _("Stop"),
        right_value = self[upper] or upper_default,
        right_default = upper_default,
        right_min = value_min or 50,
        right_max = 100,
        right_hold_step = 5,
        unit = "%",
        ok_always_enabled = true,
        default_values = true,
        is_range = true,
        callback = function(left_value, right_value)
            if left_value > right_value then
                left_value = right_value
            end
            self[lower] = left_value
            G_reader_settings:saveSetting(lower, left_value)
            self[upper] = right_value
            G_reader_settings:saveSetting(upper, right_value)
            self:unschedule_task()
            self:task()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        extra_text = _("Disable"),
        extra_callback = function()
            self[lower] = false
            self[upper] = false
            G_reader_settings:saveSetting(lower, false)
            G_reader_settings:saveSetting(upper, false)
            self:unschedule_task()
            self:task()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
    UIManager:show(threshold_spinner)
end

function BatteryCare:setAuxMin(touchmenu_instance, title, info, setting, value_default, value_min, value_max)
    local threshold_spinner = SpinWidget:new{
        title_text = title,
        info_text = info,
        value = self[setting] or value_default,
        default_value = value_default,
        value_min = value_min,
        value_max = value_max,
        value_hold_step = 5,
        unit = "%",
        ok_always_enabled = true,
        callback = function(spin)
            if spin.value >= 0 and spin.value <=100 then
                self[setting] = spin.value
                G_reader_settings:saveSetting(setting, spin.value)
                self:unschedule_task()
                self:task()
            end
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
        extra_text = _("Disable"),
        extra_callback = function()
            self[setting] = false
            G_reader_settings:delSetting(setting)
            self:unschedule_task()
            self:task()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
    UIManager:show(threshold_spinner)
end

local about_text = _([[Allows to set thresholds to start and stop charging.

Depending on the hardware, an attempt is made to adhere to the specified thresholds as precisely as possible.

On some devices an auxilliary battery can be managed, too.]])

function BatteryCare:addToMainMenu(menu_items)
    local batt_item = {
        text_func = function()
            if self.battery_care_start_thr and  self.battery_care_stop_thr then
                return T(_("Primary battery charge hysteresis: %1 % — %2 %"),
                    self.battery_care_start_thr, self.battery_care_stop_thr)
            else
                return _("Primary battery charge hysteresis")
            end
        end,
        enabled_func = function()
            return self.enabled
        end,
        checked_func = function()
            return self.battery_care_start_thr and self.battery_care_stop_thr
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            self:setThresholds(touchmenu_instance, _("Charge hysteresis thresholds"),
                _("Enter lower threshold to start and upper threshold to stop start charging.\nCharging will starts if the capacity is below the lower and stops if the capacity is higher than the upper threshold."),
                "battery_care_start_thr", "battery_care_stop_thr",
                default_start_thr, default_stop_thr)
        end,
        separator = true,
    }

    local aux_batt_item, aux_batt_ballance
    if Device:isKobo() and Device:hasAuxBattery() or Device:isEmulator() then
        aux_batt_item = {
            text_func = function()
                if self.battery_care_aux_start_thr and self.battery_care_aux_stop_thr then
                    return T(_("Auxilliary battery charge hysteresis: %1 % — %2 %"),
                        self.battery_care_aux_start_thr, self.battery_care_aux_stop_thr)
                else
                    return _("Auxilliary battery charge hysteresis")
                end
            end,
            enabled_func = function()
                return self.enabled
            end,
            checked_func = function()
                return self.battery_care_aux_start_thr and self.battery_care_aux_stop_thr
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:setThresholds(touchmenu_instance, _("Charge hysteresis thresholds"),
                    _("Enter lower threshold to start and upper threshold to stop start charging.\nCharging starts if the capacity is below the lower and stops if the capacity is higher than the upper threshold."),
                    "battery_care_aux_start_thr", "battery_care_aux_stop_thr",
                    default_aux_start_thr, default_aux_stop_thr, self.battery_care_balance_thr)
            end,
        }
        aux_batt_ballance = {
            text_func = function()
                if self.battery_care_balance_thr then
                    return T(_("Balance threshold: %1 %"), self.battery_care_balance_thr)
                else
                    return _("Balance threshold")
                end
            end,
            enabled_func = function()
                return self.enabled
            end,
            checked_func = function()
                return self.battery_care_balance_thr
            end,
            help_text = _("Keep batteries ballanced, if aux battery's capacity drops below this threshold."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:setAuxMin(touchmenu_instance,
                    _("Charge equalize thresholds"),
                    _("Enter threshold to equalize batteries."),
                    "battery_care_balance_thr", default_balance_thr, 1, self.battery_care_aux_start_thr)
            end,
        }
    end

    menu_items.BatteryCare = {
        sorting_hint = "device",
        checked_func = function()
            return self.enabled
        end,
        text = _("Battery care"),
        sub_item_table = {
            {
                text = _("About battery care"),
                callback = function(touchmenu_instance)
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Show capacity in sleep state"),
                checked_func = function()
                    return self.show_capacity_in_sleep
                end,
                callback = function(touchmenu_instance)
                    self.show_capacity_in_sleep = not self.show_capacity_in_sleep
                    G_reader_settings:saveSetting("battery_care_show_capacity_in_sleep", self.show_capacity_in_sleep)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Battery care"),
                checked_func = function()
                    return self.enabled
                end,
                callback = function(touchmenu_instance)
                    self.enabled = not G_reader_settings:isTrue("battery_care")
                    G_reader_settings:saveSetting("battery_care", self.enabled)
                    -- don't save this setting!!!
                    self.charge_once = false
                    self:unschedule_task()
                    self:task()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Charge once"),
                enabled_func = function()
                    return self.enabled
                end,
                checked_func = function()
                    return self.charge_once
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self.charge_once = not self.charge_once
                    -- don't save this setting!!!
                    self:unschedule_task()
                    self:task()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            batt_item,
            aux_batt_item,
            aux_batt_ballance,
        },
    }
end

--- Calculate the charging conditions for an internal and an external battery, and schedules its next call.
-- The actual action has to be done in powerd:charge().
-- For a new device an appropriate powerd:charge() has to be implemented.
function BatteryCare:task() -- the brain of batteryCare
    local info
    if self.enabled then
        if self:unschedule_task() then
            -- delete the next line, after testing -xxxx
            logger.err("BatteryCare: XXX: THIS SHOULD NOT HAPPEN; BUGBUGUBUGUBUGUBUGUBUG")
        end

        self:schedule_task()
    else
        self:unschedule_task()
        info = powerd:charge(true, true) -- restore default behavior
        logger.dbg("BatteryCare disabled:", info)
        return
    end

    logger.dbg("BatteryCare: isCharging", tostring(powerd:isChargingHW()), "isAuxCharging", tostring(powerd:isAuxChargingHW()))

    self.curr_capacity = powerd:getCapacityHW()

    if powerd.device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
        self.curr_aux_capacity = powerd:getAuxCapacityHW() -- might give us nil, even if aux batt is present
    end

    if self.charge_once then
        if self.curr_capacity > 99 and (self.curr_aux_capacity == nil or self.curr_aux_capacity > 99) then
            logger.dbg("BatteryCare: charge once off")
            self.charge_once = false
            info = powerd:charge(false, false)
        else
            logger.dbg("BatteryCare: charge once running")
            info = powerd:charge(true, true) -- turn on default behaviour
        end
        logger.dbg("BatteryCare:", info)
        return
    end

    logger.dbg("BatteryCare: battery", self.curr_capacity, "-",
        self.battery_care_start_thr, self.battery_care_stop_thr)

    local charge_batt, charge_aux -- nil means, don't change state
    local balance_batt

    if self.battery_care_stop_thr and self.battery_care_start_thr then
        if self.curr_capacity > self.battery_care_stop_thr then
            -- logger.dbg("BatteryCare: disable batt charge")
            charge_batt = false
        elseif self.curr_capacity < self.battery_care_start_thr then
            -- logger.dbg("BatteryCare: enable batt charge")
            charge_batt = true
        -- else
            -- logger.dbg("BatteryCare: nochange batt charge")
        end
    end

    if self.curr_aux_capacity then
        if self.battery_care_aux_stop_thr and self.battery_care_aux_start_thr then
            logger.dbg("BatteryCare: aux battery", self.curr_aux_capacity, "-",
                self.battery_care_aux_start_thr, self.battery_care_aux_stop_thr)

            if self.curr_aux_capacity > self.battery_care_aux_stop_thr then
                -- logger.dbg("BatteryCare: disable aux batt charge")
                charge_aux = false
            elseif self.curr_aux_capacity < self.battery_care_aux_start_thr then
                -- logger.dbg("BatteryCare: enable aux batt charge")
                charge_aux = true
            -- else
                -- logger.dbg("BatteryCare: nochange aux batt charge")
            end
        end
        if self.battery_care_balance_thr and self.curr_aux_capacity < self.battery_care_balance_thr then
            balance_batt = true
            if self.curr_capacity <= self.curr_aux_capacity then
                -- logger.dbg("BatteryCare: batt lower or equal aux")
                charge_batt = true
                charge_aux = true
            else
                -- logger.dbg("BatteryCare: batt higher than aux")
                charge_batt = false
                charge_aux = false
            end
        end
    end

    info = powerd:charge(charge_batt, charge_aux, balance_batt)
    logger.dbg("BatteryCare:", info)
end

return BatteryCare
