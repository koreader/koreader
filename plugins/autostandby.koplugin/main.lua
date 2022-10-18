local Device = require("device")

if not Device:isPocketBook() --[[and not Device:isKobo()]] then
    return { disabled = true }
end

local PowerD = Device:getPowerDevice()
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local logger = require("logger")
local _ = require("gettext")

local AutoStandby = WidgetContainer:extend{
    is_doc_only = false,
    name = "autostandby",

    -- static for all plugin instances
    settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autostandby.lua"),
    delay = 0,
    lastInput = 0,
    preventing = false,
}

function AutoStandby:init()
    logger.dbg("AutoStandby:init() instance=", tostring(self))
    if not self.settings:has("filter") then
        logger.dbg("AutoStandby: No settings found, initializing defaults")
        self.settings.data = {
            forbidden = false,  -- If forbidden, standby is never allowed to occur
            filter = 1,         -- Consider input only further than this many seconds apart
            min = 1,            -- Initial delay period during which we won't standby
            mul = 1.5,          -- Multiply the delay with each subsequent input that happens, scales up to max
            max = 30,           -- Input that happens further than 30 seconds since last input one reset delay back to 'min'
            win = 5,            -- Additional time window to consider input contributing to standby delay
            bat = 60,           -- If battery is below this percent, make auto-standby aggressive again (disables scaling by mul)
        }
        self.settings:flush()
    end

    UIManager.event_hook:registerWidget("InputEvent", self)
    self.ui.menu:registerToMainMenu(self)
end

function AutoStandby:onCloseWidget()
    logger.dbg("AutoStandby:onCloseWidget() instance=", tostring(self))
    UIManager:unschedule(AutoStandby.allow)
end

function AutoStandby:addToMainMenu(menu_items)
    menu_items.autostandby = {
        sorting_hint = "device",
        text = _("Auto-standby settings"),
        sub_item_table = {
            {
                keep_menu_open = true,
                text = _("Allow auto-standby"),
                checked_func = function() return self:isAllowedByConfig() end,
                callback = function() self.settings:saveSetting("forbidden", self:isAllowedByConfig()):flush() end,
            },
            self:genSpinMenuItem(_("Min input idle seconds"), "min", function() return 0 end, function() return self.settings:readSetting("max") end),
            self:genSpinMenuItem(_("Max input idle seconds"), "max", function() return 0 end),
            self:genSpinMenuItem(_("Input window seconds"), "win", function() return 0 end, function() return self.settings:readSetting("max") end),
            self:genSpinMenuItem(_("Always standby if battery below"), "bat", function() return 0 end, function() return 100 end),
        }
    }
end

-- We've received touch/key event, so delay standby accordingly
function AutoStandby:onInputEvent()
    logger.dbg("AutoStandby:onInputevent() instance=", tostring(self))
    local config = self.settings.data
    local t = os.time()
    if t < AutoStandby.lastInput + config.filter then
        -- packed too close together, ignore
        logger.dbg("AutoStandby: input packed too close to previous one, ignoring")
        return
    end

    -- Nuke past timer as we'll reschedule the allow (or not)
    UIManager:unschedule(AutoStandby.allow)

    if PowerD:getCapacityHW() <= config.bat then
        -- battery is below threshold, so allow standby aggressively
        logger.dbg("AutoStandby: battery below threshold, enabling aggressive standby")
        self:allow()
        return
    elseif t > AutoStandby.lastInput + config.max then
        -- too far apart, so reset delay
        logger.dbg("AutoStandby: input too far in future, resetting adaptive standby delay from", AutoStandby.delay, "to", config.min)
        AutoStandby.delay = config.min
    elseif t < AutoStandby.lastInput + AutoStandby.delay + config.win then
        -- otherwise widen the delay - "adaptive" - with frequent inputs, but don't grow beyonnd the max
        AutoStandby.delay = math.min((AutoStandby.delay+1) * config.mul, config.max)
        logger.dbg("AutoStandby: increasing standby delay to", AutoStandby.delay)
    end -- equilibrium: when the event arrives beyond delay + win, but still below max, we keep the delay as-is

    AutoStandby.lastInput = t

    if not self:isAllowedByConfig() then
        -- all standbys forbidden, always prevent
        self:prevent()
        return
    elseif AutoStandby.delay == 0 then
        -- If delay is 0 now, just allow straight
        self:allow()
        return
    end
    -- otherwise prevent for a while for duration of the delay
    self:prevent()
    -- and schedule standby re-enable once delay expires
    UIManager:scheduleIn(AutoStandby.delay, AutoStandby.allow, AutoStandby)
end

-- Prevent standby (by timer)
function AutoStandby:prevent()
    if not AutoStandby.preventing then
        AutoStandby.preventing = true
        UIManager:preventStandby()
    end
end

-- Allow standby (by timer)
function AutoStandby:allow()
    if AutoStandby.preventing then
        AutoStandby.preventing = false
        UIManager:allowStandby()
    end
end

function AutoStandby:isAllowedByConfig()
    return self.settings:isFalse("forbidden")
end

function AutoStandby:genSpinMenuItem(text, cfg, min, max)
    return {
        keep_menu_open = true,
        text = text,
        enabled_func = function() return self:isAllowedByConfig() end,
        callback = function()
            local spin = SpinWidget:new {
                value = self.settings:readSetting(cfg),
                value_min = min and min() or 0,
                value_max = max and max() or 9999,
                value_hold_step = 10,
                ok_text = _("Update"),
                title_text = text,
                callback = function(spin) self.settings:saveSetting(cfg, spin.value):flush() end,
            }
            UIManager:show(spin)
        end
    }
end

-- koreader is merely waiting for user input right now.
-- UI signals us that standby is allowed at this very moment because nothing else goes on in the background.
function AutoStandby:onAllowStandby()
    logger.dbg("AutoStandby: onAllowStandby()")
    -- In case the OS frontend itself doesn't manage power state, we can do it on our own here.
    -- One should also configure wake-up pins and perhaps wake alarm,
    -- if we want to enter deeper sleep states later on from within standby.

    --os.execute("echo mem > /sys/power/state")
end

return AutoStandby

