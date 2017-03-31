
local KeyValuePage = require("ui/widget/keyvaluepage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

local SystemStat = {
    name = "systemstat",
}

function SystemStat:init()
    self.start_sec = os.time()
    self.charging = Usage:new(self.settings:readSetting("charging"))
    self.decharging = Usage:new(self.settings:readSetting("decharging"))
    self.awake = Usage:new(self.settings:readSetting("awake"))
    self.sleeping = Usage:new(self.settings:readSetting("sleeping"))

    -- Note: these fields are not the "real" timestamp and battery usage, but
    -- the unaccumulated values.
    self.charging_state = State:new(self.settings:readSetting("charging_state"))
    self.awake_state = State:new(self.settings:readSetting("awake_state"))
    self:initCurrentState()

    if self.debugging then
        self.debugOutput = self._debugOutput
    else
        self.debugOutput = function() end
    end
end

function SystemStat:initCurrentState()
    -- Whether the device was suspending before current timestamp.
    self.was_suspending = false
    -- Whether the device was charging before current timestamp.
    self.was_charging = PowerD:isCharging()
end

function SystemStat:onFlushSettings()
    self.settings:reset({
        charging = self.charging,
        decharging = self.decharging,
        awake = self.awake,
        sleeping = self.sleeping,
        charging_state = self.charging_state,
        awake_state = self.awake_state,
    })
    self.settings:flush()
end

function SystemStat:accumulate()
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

function SystemStat:dumpOrLog(content)
    local file = io.open(self.dump_file, "a")
    if file then
        file:write(content .. "\n")
        file:close()
    else
        logger.warn("Failed to dump output ", content, " into ", self.dump_file )
    end
end

function SystemStat:_debugOutput(event)
    self:dumpOrLog(event .. " @ " .. State:new():toString() ..
                   ", awake_state " .. self.awake_state:toString() ..
                   ", charging_state " .. self.charging_state:toString())
end

function SystemStat:onSuspend()
    self:debugOutput("onSuspend")
    self.was_suspending = false
    self:accumulate()
end

function SystemStat:onResume()
    self:debugOutput("onResume")
    self.was_suspending = true
    self:accumulate()
end

function SystemStat:onCharging()
    self:debugOutput("onCharging")
    self.was_charging = false
    self:dumpToText()
    self.charging = Usage:new()
    self.awake = Usage:new()
    self.sleeping = Usage:new()
    self:accumulate()
end

function SystemStat:onNotCharging()
    self:debugOutput("onNotCharging")
    self.was_charging = true
    self:dumpToText()
    self.decharging = Usage:new()
    self.awake = Usage:new()
    self.sleeping = Usage:new()
    self:accumulate()
end

function SystemStat:onCallback()
    self:initCurrentState()
    self:accumulate()
    local kv_pairs = self:dump()
    table.insert(kv_pairs, "----------")
    table.insert(kv_pairs, {_("Historical records are dumped to"), ""})
    table.insert(kv_pairs, {self.dump_file, ""})
    UIManager:show(KeyValuePage:new{
        title = _("System statistics"),
        kv_pairs = kv_pairs,
    })
end

function SystemStat:dumpToText()
    local kv_pairs = self:dump()
    local content = T(_("Dump at %1"), os.date("%c"))
    for _, pair in ipairs(kv_pairs) do
        content = content .. "\n" .. pair[1]
        if pair[2] ~= nil and pair[2] ~= "" then
            content = content .. "\t" .. pair[2]
        end
    end
    self:dumpOrLog(content .. "\n-=-=-=-=-=-\n")
end

function SystemStat:dump()
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

SystemStat:init()

local SystemStatWidget = WidgetContainer:new()

function SystemStatWidget:init()
    self.ui.menu:registerToMainMenu(self)
end

function SystemStatWidget:addToMainMenu(menu_items)
    menu_items.battery_statistics = {
        text = _("System statistics"),
        callback = function()
            SystemStat:onCallback()
        end,
    }
end

function SystemStatWidget:onFlushSettings()
    SystemStat:onFlushSettings()
end

function SystemStatWidget:onSuspend()
    SystemStat:onSuspend()
end

function SystemStatWidget:onResume()
    SystemStat:onResume()
end

function SystemStatWidget:onCharging()
    SystemStat:onCharging()
end

function SystemStatWidget:onNotCharging()
    SystemStat:onNotCharging()
end

return SystemStatWidget
