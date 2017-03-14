
local DataStorage = require("datastorage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaSettings = require("luasettings")
local PowerD = require("device"):getPowerDevice()
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local logger = require("logger")
local util = require("ffi/util")
local _ = require("gettext")

local State = {}

function State:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.percentage == nil or o.timestamp == nil then
        o.percentage = PowerD:getCapacity()
        o.timestamp = os.time()
    end
    return o
end

local Usage = {}

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
    self.percentage = self.percentage + (state.percentage - curr.percentage)
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
    local curr = State:new()
    return curr.percentage / self:percentagePerHour()
end

function Usage:chargingHours()
    local curr = State:new()
    return (100 - curr.percentage) / self:percentagePerHour()
end

local function shorten(number)
    return string.format("%.2f", number);
end

function Usage:dump(kv_pairs)
    table.insert(kv_pairs, {_("    Consumed %"), shorten(self.percentage)})
    table.insert(kv_pairs, {_("    Total minutes"), shorten(self:minutes())})
    table.insert(kv_pairs, {_("    % per hour"), shorten(self:percentagePerHour())})
end

function Usage:dumpRemaining(kv_pairs)
    table.insert(kv_pairs, {_("    Estimated remaining hours"), shorten(self:remainingHours())})
end

function Usage:dumpCharging(kv_pairs)
    table.insert(kv_pairs, {_("    Estimated hours for charging"), shorten(self:chargingHours())})
end

local BatteryStat = WidgetContainer:new{
    name = "batterstat",
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/batterstat.lua"),
    dump_file = util.realpath(DataStorage:getDataDir()) .. "/battery_stat.txt",
}

function BatteryStat:init()
    self.charging = Usage:new(self.settings.charging)
    self.decharging = Usage:new(self.settings.decharging)
    self.awake = Usage:new(self.settings.awake)
    self.sleeping = Usage:new(self.settings.sleeping)

    -- Note: these fields are not the "real" timestamp and battery usage, but
    -- the unaccumulated values.
    self.charging_state = State:new(self.settings.charging_state)
    self.awake_state = State:new(self.settings.awake_state)
    -- Whether the device was suspending before current timestamp.
    self.was_suspending = false
    -- Whether the device was charging before current timestamp.
    self.was_charging = PowerD:isCharging()

    self.ui.menu:registerToMainMenu(self)
end

function BatteryStat:onFlushSettings()
    self.settings:replace({
        charging = self.charging,
        decharging = self.decharging,
        awake = self.awake,
        sleeping = self.sleeping,
        charging_state = self.charging_state,
        awake_state = self.awake_state,
    })
    self.settings:flush()
end

function BatteryStat:accumulate()
    if self.was_suspending then
        -- Suspending to awake.
        self.sleeping:append(self.awake_state)
    else
        -- Awake to suspending, time between self.awake_state and now should belong to awake.
        self.awake:append(self.awake_state)
    end
    if self.was_charging then
        -- Decharging to charging.
        self.charging:append(self.charging_state)
    else
        self.decharging:append(self.charging_state)
    end
    self.awake_state = State:new()
    self.charging_state = State:new()
end

function BatteryStat:onSuspend()
    self.was_suspending = false
    self:accumulate()
end

function BatteryStat:onResume()
    self.was_suspending = true
    self:accumulate()
end

function BatteryStat:onCharging()
    self.was_charging = false
    self:dumpToText()
    self.charging = Usage:new()
    self.awake = Usage:new()
    self.sleeping = Usage:new()
    self:accumulate()
end

function BatteryStat:onNotCharging()
    self.was_charging = true
    self:dumpToText()
    self.decharging = Usage:new()
    self.awake = Usage:new()
    self.sleeping = Usage:new()
    self:accumulate()
end

function BatteryStat:dumpToText()
    local kv_pairs = self:dump()
    local content = T(_("Dump at %1"), os.date("%c", os.time()))
    for _, pair in ipairs(kv_pairs) do
        content = content .. "\n" .. pair[1]
        if pair[2] ~= nil and pair[2] ~= "" then
            content = content .. "\t" .. pair[2]
        end
    end
    content = content .. "\n-=-=-=-=-=-\n"
    local file = io.open(self.dump_file, "a")
    if file then
        file:write(content)
        file:close()
    else
        logger.warn(content)
    end
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
    self.decharging:dump(kv_pairs)
    self.decharging:dumpRemaining(kv_pairs)
    return kv_pairs
end

function BatteryStat:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Battery statistics"),
        callback = function()
            self.was_suspending = false
            self.was_charging = PowerD:isCharging()
            self:accumulate()
            local kv_pairs = self:dump()
            table.insert(kv_pairs, {_("Historical records are dumped to"), ""})
            table.insert(kv_pairs, {self.dump_file, ""})
            UIManager:show(KeyValuePage:new{
                title = _("Battery statistics"),
                kv_pairs = kv_pairs,
            })
        end,
    })
end

return BatteryStat
