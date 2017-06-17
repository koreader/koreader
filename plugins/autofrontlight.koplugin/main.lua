local Device = require("device")

if not Device:isKindle() or
   (Device.model ~= "KindleVoyage" and Device.model ~= "KindleOasis") then
    return { disabled = true, }
end

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoFrontlight = {
  settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autofrontlight.lua"),
  settings_id = 0,
  enabled = false,
  last_brightness = Device:ambientBrightnessLevel(),
}

function AutoFrontlight:_schedule()
    if not self.enabled then
        logger.dbg("AutoFrontlight:_schedule() is disabled")
        return
    end

    local settings_id = self.settings_id
    logger.dbg("AutoFrontlight:_schedule() @ ", os.time(), ", it should be executed at ", os.time() + 1)
    UIManager:scheduleIn(2, function()
        self:_action(settings_id)
        self:_schedule(self.settings_id)
    end)
end

function AutoFrontlight:_action(settings_id)
    if settings_id ~= self.settings_id then
        logger.dbg("AutoFrontlight:_action(): registered settings_id ",
                   settings_id,
                   " does not equal to current one ",
                   self.settings_id)
        return
    end
    logger.dbg("AutoFrontlight:_action() @ ", os.time())
    local current_level = Device:ambientBrightnessLevel()
    logger.dbg("Retrieved ambient brightness level: ", current_level)
    if self.last_brightness == current_level then
        logger.dbg("AutoFrontlight:_action(): recorded brightness is same as current level ",
                   self.last_brightness)
        return
    end
    if current_level <= 1 then
        logger.dbg("AutoFrontlight: going to turn on frontlight")
        Device:getPowerDevice():turnOnFrontlight()
        self.last_brightness = current_level
    elseif current_level >= 3 then
        logger.dbg("AutoFrontlight: going to turn off frontlight")
        Device:getPowerDevice():turnOffFrontlight()
        self.last_brightness = current_level
    end
end

function AutoFrontlight:init()
    self.enabled = not self.settings:nilOrFalse("enable")
    logger.dbg("AutoFrontlight:init() self.enabled: ", self.enabled)
    self.settings_id = self.settings_id + 1
    self:_schedule()
end

function AutoFrontlight:flipSetting()
    self.settings:flipNilOrFalse("enable")
    self:init()
end

AutoFrontlight:init()

local AutoFrontlightWidget = WidgetContainer:new{
    name = "AutoFrontlight",
}

function AutoFrontlightWidget:init()
    self.ui.menu:registerToMainMenu(self)
end

function AutoFrontlightWidget:addToMainMenu(menu_items)
    menu_items.auto_frontlight = {
        text = _("Auto frontlight"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = T(_("Auto frontlight detects the brightness of the environment and automatically turn on and off the frontlight.\nFrontlight will be turned off to save battery in bright environment, and turned on in dark environment.\nDo you want to %1 it?"),
                         AutoFrontlight.enabled and _("disable") or _("enable")),
                ok_text = AutoFrontlight.enabled and _("Disable") or _("Enable"),
                ok_callback = function()
                    AutoFrontlight:flipSetting()
                end
            })
        end,
        checked_func = function() AutoFrontlight.enabled end,
    }
end

return AutoFrontlightWidget
