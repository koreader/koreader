local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaSettings = require("luasettings")
local PowerD = require("device"):getPowerDevice()
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local dbg = require("dbg")
local time = require("ui/time")
local _ = require("gettext")

local State = {}

function State:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.percentage == nil or o.timestamp == nil then
        o.percentage = PowerD:getCapacityHW()
        o.timestamp = time.boottime_or_realtime_coarse()
    end
    return o
end

function State:toString()
    return string.format("{%d @ %s}", self.percentage, os.date("%c", time.to_s(self.timestamp)))
end

local Usage = {}
local INDENTATION = "   " -- Three spaces.

function Usage:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.percentage == nil or o.time == nil then
        o.percentage = 0
        o.time = 0
    end
    return o
end

function Usage:append(state)
    local curr = State:new()
    self.percentage = self.percentage + math.abs(state.percentage - curr.percentage)
    self.time = self.time + curr.timestamp - state.timestamp
end

function Usage:percentageRate()
    if self.time == 0 then
        return 0
    else
        return self.percentage / time.to_s(self.time)
    end
end

function Usage:percentageRatePerHour()
    return self:percentageRate() * 3600
end

function Usage:remainingTime()
    if self:percentageRate() == 0 then return "N/A" end
    local curr = State:new()
    return curr.percentage / self:percentageRate()
end

function Usage:chargingTime()
    if self:percentageRate() == 0 then return "N/A" end
    local curr = State:new()
    return math.abs(curr.percentage - 100) / self:percentageRate()
end

local function shorten(number)
    if number == "N/A" then return _("N/A") end
    return string.format("%.2f%%", number)
end

local function duration(number)
    local duration_fmt = G_reader_settings:readSetting("duration_format", "classic")
    return type(number) ~= "number" and number or
        datetime.secondsToClockDuration(duration_fmt, number, true, true)
end

function Usage:dump(kv_pairs, id)
    local name = id or _("Consumed:")
    table.insert(kv_pairs, {INDENTATION .. _("Total time:"), duration(time.to_s(self.time)) })
    table.insert(kv_pairs, {INDENTATION .. name, shorten(self.percentage), "%"})
    table.insert(kv_pairs, {INDENTATION .. _("Change per hour:"), shorten(self:percentageRatePerHour())})
end

function Usage:dumpRemaining(kv_pairs)
    table.insert(kv_pairs, {INDENTATION .. _("Estimated remaining time:"), duration(self:remainingTime())})
end

function Usage:dumpCharging(kv_pairs)
    table.insert(kv_pairs, {INDENTATION .. _("Estimated time for charging:"), duration(self:chargingTime())})
end

local BatteryStat = {
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/battery_stats.lua"),
    kv_page = nil,
}

function BatteryStat:init()
    self.awake = Usage:new(self.settings:readSetting("awake"))
    self.sleeping = Usage:new(self.settings:readSetting("sleeping"))
    self.charging = Usage:new(self.settings:readSetting("charging"))
    self.discharging = Usage:new(self.settings:readSetting("discharging"))

    -- Note: these fields are not the "real" timestamp and battery usage, but
    -- the unaccumulated values.
    self.awake_state = State:new()
    self.charging_state = State:new()

    -- Whether the device was suspending before current timestamp.
    self.was_suspending = false
    -- Whether the device was charging before current timestamp.
    self.was_charging = PowerD:isCharging()
    if self.was_charging then
        self:reset(true, false)
    end
    -- Check if the battery was charging when KO was turned off.
    local battery_before_off = self.settings:readSetting("awake_state")
    if battery_before_off and battery_before_off.percentage
        and self.awake_state.percentage > battery_before_off.percentage then
        self:reset(false, true)
    end
end

function BatteryStat:onFlushSettings()
    self.settings:reset({
        charging = self.charging,
        discharging = self.discharging,
        awake = self.awake,
        sleeping = self.sleeping,
        charging_state = self.charging_state,
        awake_state = self.awake_state,
    })
    self.settings:flush()
end

function BatteryStat:accumulate()
    if self.was_suspending and not self.was_charging then
        -- Suspending to awake.
        self.sleeping:append(self.awake_state)
    elseif not self.was_suspending and not self.was_charging then
        -- Awake to suspending, time between self.awake_state and now should belong to awake.
        self.awake:append(self.awake_state)
    end
    if self.was_charging then
        -- Decharging to charging.
        self.charging:append(self.charging_state)
    else
        self.discharging:append(self.charging_state)
    end
    self.awake_state = State:new()
    self.charging_state = State:new()
end

function BatteryStat:onSuspend()
    if not self.was_suspending then
        self:accumulate()
    end
    self.was_suspending = true
end

function BatteryStat:onResume()
    if self.was_suspending then
        self:accumulate()
    end
    self.was_suspending = false
end

function BatteryStat:onCharging()
    if not self.was_charging then
        self:reset(true, true)
        self:accumulate()
    end
    self.was_charging = true
end

function BatteryStat:onNotCharging()
    if self.was_charging then
        self:reset(false, true)
        self:accumulate()
    end
    self.was_charging = false
end

function BatteryStat:showStatistics()
    local function askResetData()
        UIManager:show(ConfirmBox:new{
            text = _("Are you sure that you want to clear battery statistics?"),
            ok_text = _("Clear"),
            ok_callback = function()
                self:resetAll()
                self:restart()
            end,
        })
    end

    self:accumulate()
    local kv_pairs = self:dump()
    kv_pairs[#kv_pairs].separator = true
    table.insert(kv_pairs, {_("Tap to reset the data"), "",
                            callback = function()
                                UIManager:setDirty(self.kv_page, "fast")
                                UIManager:scheduleIn(0.1, function()
                                    askResetData()
                                end)
                            end})
    self.kv_page = KeyValuePage:new{
        title = _("Battery statistics") .. " (" .. self.awake_state.percentage .. "%)",
        kv_pairs = kv_pairs,
        single_page = true,
    }
    UIManager:show(self.kv_page)
end

function BatteryStat:reset(withCharging, withDischarging)
    self.awake = Usage:new()
    self.sleeping = Usage:new()

    if withCharging then
        self.charging = Usage:new()
    end
    if withDischarging then
        self.discharging = Usage:new()
    end
    self.awake_state = State:new()
end

function BatteryStat:resetAll()
    self:reset(true, true)
    self.charging_state = State:new()
    self.awake_state = State:new()
end

function BatteryStat:restart()
    dbg.dassert(self.kv_page ~= nil)
    UIManager:close(self.kv_page)
    self:showStatistics()
end

function BatteryStat:dump()
    local kv_pairs = {}
    table.insert(kv_pairs, {_("Awake since last charge"), ""})
    self.awake:dump(kv_pairs)
    self.awake:dumpRemaining(kv_pairs)
    table.insert(kv_pairs, {_("Sleeping since last charge"), ""})
    self.sleeping:dump(kv_pairs)
    self.sleeping:dumpRemaining(kv_pairs)
    table.insert(kv_pairs, {_("During last charge"), ""})
    self.charging:dump(kv_pairs, _("Charged:"))
    self.charging:dumpCharging(kv_pairs)
    table.insert(kv_pairs, {_("Since last charge"), ""})
    self.discharging:dump(kv_pairs)
    self.discharging:dumpRemaining(kv_pairs)
    return kv_pairs
end

BatteryStat:init()

local BatteryStatWidget = WidgetContainer:extend{
    name = "batterystat",
}

function BatteryStatWidget:onDispatcherRegisterActions()
    Dispatcher:registerAction("battery_statistics", {category="none", event="ShowBatteryStatistics", title=_("Battery statistics"), device=true, separator=true})
end

function BatteryStatWidget:init()
    -- self.ui is nil in test cases.
    if not self.ui or not self.ui.menu then return end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function BatteryStatWidget:addToMainMenu(menu_items)
    menu_items.battery_statistics = {
        text = _("Battery statistics"),
        keep_menu_open = true,
        callback = function()
            BatteryStat:showStatistics()
        end,
    }
end

function BatteryStatWidget:onShowBatteryStatistics()
    BatteryStat:showStatistics()
end

function BatteryStatWidget:onFlushSettings()
    BatteryStat:onFlushSettings()
end

function BatteryStatWidget:onSuspend()
    BatteryStat:onSuspend()
end

function BatteryStatWidget:onResume()
    BatteryStat:onResume()
end

function BatteryStatWidget:onCharging()
    BatteryStat:onCharging()
end

function BatteryStatWidget:onNotCharging()
    BatteryStat:onNotCharging()
end

-- Test only
function BatteryStatWidget:stat()
    return BatteryStat
end

return BatteryStatWidget
