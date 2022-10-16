--[[--
SwitchPlugin creates a plugin with a switch to enable or disable it.
See spec/unit/switch_plugin_spec.lua for the usage.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local SwitchPlugin = WidgetContainer:extend{}

function SwitchPlugin:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function SwitchPlugin:new(o)
    o = self:extend(o)
    assert(type(o.name) == "string", "name is required")
    o.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/" .. o.name .. ".lua")
    o.settings_id = 0
    SwitchPlugin._init(o)
    return o
end

function SwitchPlugin:_init()
    if self.default_enable then
        self.enabled = self.settings:nilOrTrue("enable")
    else
        self.enabled = not self.settings:nilOrFalse("enable")
    end
    self.settings_id = self.settings_id + 1
    logger.dbg("SwitchPlugin:_init() self.enabled: ", self.enabled, " with id ", self.settings_id)
    if self.enabled then
        self:_start()
    else
        self:_stop()
    end
end

function SwitchPlugin:flipSetting()
    if self.default_enable then
        self.settings:flipNilOrTrue("enable")
    else
        self.settings:flipNilOrFalse("enable")
    end
    self:_init()
end

function SwitchPlugin:onFlushSettings()
    self.settings:flush()
end

--- Show a ConfirmBox to ask for enabling or disabling this plugin.
function SwitchPlugin:_showConfirmBox()
    UIManager:show(ConfirmBox:new{
        text = self:_confirmMessage(),
        ok_text = self.enabled and _("Disable") or _("Enable"),
        ok_callback = function()
            self:flipSetting()
        end,
    })
end

function SwitchPlugin:_confirmMessage()
    local result = ""
    if type(self.confirm_message) == "string" then
        result = self.confirm_message .. "\n"
    elseif type(self.confirm_message) == "function" then
        result = self.confirm_message() .. "\n"
    end
    if self.enabled then
        result = result .. _("Do you want to disable it?")
    else
        result = result .. _("Do you want to enable it?")
    end
    return result
end

function SwitchPlugin:init()
    if type(self.menu_item) == "string" and self.ui ~= nil and self.ui.menu ~= nil then
        self.ui.menu:registerToMainMenu(self)
    end
end

function SwitchPlugin:addToMainMenu(menu_items)
    assert(type(self.menu_item) == "string",
           "addToMainMenu should not be called without menu_item.")
    assert(type(self.menu_text) == "string",
           "Have you forgotten to set \"menu_text\"")
    menu_items[self.menu_item] = {
        text = self.menu_text,
        callback = function()
            self:_showConfirmBox()
        end,
        checked_func = function() return self.enabled end,
    }
end

-- Virtual
function SwitchPlugin:_start() end
-- Virtual
function SwitchPlugin:_stop() end

return SwitchPlugin
