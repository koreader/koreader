local Device = require("device")

if not (Device:isKindle() and Device:hasLightSensor()) then
    return { disabled = true, }
end

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoFrontlight = {
  settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autofrontlight.lua"),
  settings_id = 0,
  enabled = false,
  last_brightness = -1,
}

function AutoFrontlight:_schedule(settings_id)
    local enabled = function()
        if not self.enabled then
            logger.dbg("AutoFrontlight:_schedule() is disabled")
            return false
        end
        if settings_id ~= self.settings_id then
            logger.dbg("AutoFrontlight:_schedule(): registered settings_id ",
                       settings_id,
                       " does not equal to current one ",
                       self.settings_id)
            return false
        end

        return true
    end

    table.insert(PluginShare.backgroundJobs, {
        when = 2,
        repeated = enabled,
        executable = function()
            if enabled() then
                self:_action()
            end
        end
    })
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
end

function AutoFrontlight:_action()
    logger.dbg("AutoFrontlight:_action() @ ", os.time())
    local current_level = Device:ambientBrightnessLevel()
    logger.dbg("AutoFrontlight:_action(): Retrieved ambient brightness level: ", current_level)
    if self.last_brightness == current_level then
        logger.dbg("AutoFrontlight:_action(): recorded brightness is same as current level ",
                   self.last_brightness)
        return
    end
    if current_level <= 1 then
        logger.dbg("AutoFrontlight: going to turn on frontlight")
        Device:getPowerDevice():turnOnFrontlight()
    elseif current_level >= 3 then
        logger.dbg("AutoFrontlight: going to turn off frontlight")
        Device:getPowerDevice():turnOffFrontlight()
    end
    self.last_brightness = current_level
end

function AutoFrontlight:init()
    self.enabled = self.settings:nilOrTrue("enable")
    self.settings_id = self.settings_id + 1
    logger.dbg("AutoFrontlight:init() self.enabled: ", self.enabled, " with id ", self.settings_id)
    self:_schedule(self.settings_id)
end

function AutoFrontlight:flipSetting()
    self.settings:flipNilOrTrue("enable")
    self:init()
end

function AutoFrontlight:onFlushSettings()
    self.settings:flush()
end

AutoFrontlight:init()

local AutoFrontlightWidget = WidgetContainer:extend{
    name = "autofrontlight",
}

function AutoFrontlightWidget:init()
    -- self.ui and self.ui.menu are nil in unittests.
    if self.ui ~= nil and self.ui.menu ~= nil then
        self.ui.menu:registerToMainMenu(self)
    end
end

function AutoFrontlightWidget:flipSetting()
    AutoFrontlight:flipSetting()
end

-- For test only.
function AutoFrontlightWidget:deprecateLastTask()
    logger.dbg("AutoFrontlightWidget:deprecateLastTask() @ ", AutoFrontlight.settings_id)
    AutoFrontlight.settings_id = AutoFrontlight.settings_id + 1
end

function AutoFrontlightWidget:addToMainMenu(menu_items)
    menu_items.auto_frontlight = {
        text = _("Auto frontlight"),
        callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = T(_("Auto frontlight detects the brightness of the environment and automatically turn on and off the frontlight.\nFrontlight will be turned off to save battery in bright environment, and turned on in dark environment.\nDo you want to %1 it?"),
                         AutoFrontlight.enabled and _("disable") or _("enable")),
                ok_text = AutoFrontlight.enabled and _("Disable") or _("Enable"),
                ok_callback = function()
                    self:flipSetting()
                    touchmenu_instance:updateItems()
                end
            })
        end,
        checked_func = function() return AutoFrontlight.enabled end,
    }
end

function AutoFrontlightWidget:onFlushSettings()
    AutoFrontlight:onFlushSettings()
end

return AutoFrontlightWidget
