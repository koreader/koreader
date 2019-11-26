local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaSettings = require("luasettings")
local PowerD = require("device"):getPowerDevice()
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dbg = require("dbg")
local util = require("util")
local _ = require("gettext")

local State = {}

function State:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.percentage == nil or o.timestamp == nil then
        o.percentage = PowerD:getCapacityHW()
        o.timestamp = os.time()
    end
    return o
end

function State:toString()
    return string.format("{%d @ %s}", self.percentage, os.date("%c", self.timestamp))
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
    self.time = self.time + os.difftime(curr.timestamp - state.timestamp)
end

function Usage:minutes()
    return self.time / 60
end

function Usage:hours()
    return self:minutes() / 60
end

function Usage:percentagePerHour()
    if self.time == 0 then
        return 0
    else
        return self.percentage / self:hours()
    end
end

function Usage:remainingHours()
    if self:percentagePerHour() == 0 then return "n/a" end
    local curr = State:new()
    return curr.percentage / self:percentagePerHour()
end

function Usage:chargingHours()
    if self:percentagePerHour() == 0 then return "n/a" end
    local curr = State:new()
    return math.abs(curr.percentage - 100) / self:percentagePerHour()
end

local function shorten(number)
    if number == "n/a" then return _("n/a") end
    return string.format("%.2f", number);
end

function Usage:dump(kv_pairs)
    table.insert(kv_pairs, {INDENTATION .. _("Consumed %"), shorten(self.percentage)})
    table.insert(kv_pairs, {INDENTATION .. _("Total time"), util.secondsToHClock(self.time, true, true)})
    table.insert(kv_pairs, {INDENTATION .. _("% per hour"), shorten(self:percentagePerHour())})
end

function Usage:dumpRemaining(kv_pairs)
    table.insert(kv_pairs, {INDENTATION .. _("Estimated remaining hours"), shorten(self:remainingHours())})
end

function Usage:dumpCharging(kv_pairs)
    table.insert(kv_pairs, {INDENTATION .. _("Estimated hours for charging"), shorten(self:chargingHours())})
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
    table.insert(kv_pairs, "----------")
    table.insert(kv_pairs, {_("If you would like to reset the data,"), "",
                            callback = function()
                                UIManager:setDirty(self.kv_page, "fast")
                                UIManager:scheduleIn(0.1, function()
                                    askResetData()
                                end)
                            end})
    table.insert(kv_pairs, {_("please tap here."), "",
                            callback = function()
                                UIManager:setDirty(self.kv_page, "fast")
                                UIManager:scheduleIn(0.1, function()
                                    askResetData()
                                end)
                            end})
    self.kv_page = KeyValuePage:new{
        title = _("Battery statistics"),
        kv_pairs = kv_pairs,
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
    self.charging:dump(kv_pairs)
    self.charging:dumpCharging(kv_pairs)
    table.insert(kv_pairs, {_("Since last charge"), ""})
    self.discharging:dump(kv_pairs)
    self.discharging:dumpRemaining(kv_pairs)
    return kv_pairs
end

BatteryStat:init()

local BatteryStatWidget = WidgetContainer:new{
    name = "batterystat",
}

function BatteryStatWidget:init()
    -- self.ui is nil in test cases.
    if not self.ui or not self.ui.menu then return end
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
