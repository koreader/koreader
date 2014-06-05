local ConfigDialog = require("ui/widget/configdialog")
local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ReaderConfig = InputContainer:new{
    last_panel_index = 1,
}

function ReaderConfig:init()
    if Device:hasKeyboard() then
        self.key_events = {
            ShowConfigMenu = { { "AA" }, doc = "show config dialog" },
        }
    end
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderConfig:initGesListener()
    self.ges_events = {
        TapShowConfigMenu = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_CONFIG.x,
                    y = Screen:getHeight()*DTAP_ZONE_CONFIG.y,
                    w = Screen:getWidth()*DTAP_ZONE_CONFIG.w,
                    h = Screen:getHeight()*DTAP_ZONE_CONFIG.h,
                }
            }
        }
    }
end

function ReaderConfig:onShowConfigMenu()
    self.config_dialog = ConfigDialog:new{
        dimen = self.dimen:copy(),
        ui = self.ui,
        configurable = self.configurable,
        config_options = self.options,
        is_always_active = true,
        close_callback = function() self:onCloseCallback() end,
    }
    self.ui:handleEvent(Event:new("DisableHinting"))
    -- show last used panel when opening config dialog
    self.config_dialog:onShowConfigPanel(self.last_panel_index)
    UIManager:show(self.config_dialog)

    return true
end

function ReaderConfig:onTapShowConfigMenu()
    self:onShowConfigMenu()
    return true
end

function ReaderConfig:onSetDimensions(dimen)
    if Device:isTouchDevice() then
        self:initGesListener()
    end
    -- since we cannot redraw config_dialog with new size, we close
    -- the old one on screen size change
    if self.config_dialog then
        self.config_dialog:closeDialog()
    end
end

function ReaderConfig:onCloseCallback()
    self.last_panel_index = self.config_dialog.panel_index
    self.ui:handleEvent(Event:new("RestoreHinting"))
end

-- event handler for readercropping
function ReaderConfig:onCloseConfig()
    self.config_dialog:closeDialog()
end

function ReaderConfig:onReadSettings(config)
    self.configurable:loadSettings(config, self.options.prefix.."_")
    self.last_panel_index = config:readSetting("config_panel_index") or 1
end

function ReaderConfig:onSaveSettings()
    self.configurable:saveSettings(self.ui.doc_settings, self.options.prefix.."_")
    self.ui.doc_settings:saveSetting("config_panel_index", self.last_panel_index)
end

return ReaderConfig
