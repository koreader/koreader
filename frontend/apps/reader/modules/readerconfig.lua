local ConfigDialog = require("ui/widget/configdialog")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local CreOptions = require("ui/data/creoptions")
local KoptOptions = require("ui/data/koptoptions")
local _ = require("gettext")

local ReaderConfig = InputContainer:new{
    last_panel_index = 1,
}

function ReaderConfig:init()
    if self.document.koptinterface ~= nil then
        self.options = KoptOptions
    else
        self.options = CreOptions
    end
    self.configurable:loadDefaults(self.options)

    if not self.dimen then self.dimen = Geom:new{} end
    if Device:hasKeys() then
        self.key_events = {
            ShowConfigMenu = { {{"Press","AA"}}, doc = "show config dialog" },
        }
    end
    if Device:isTouchDevice() then
        self:initGesListener()
    end
    if G_reader_settings:has("activate_menu") then
        self.activation_menu = G_reader_settings:readSetting("activate_menu")
    else
        self.activation_menu = "swipe_tap"
    end
end

function ReaderConfig:initGesListener()
    self.ui:registerTouchZones({
        {
            id = "readerconfigmenu_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG.x, ratio_y = DTAP_ZONE_CONFIG.y,
                ratio_w = DTAP_ZONE_CONFIG.w, ratio_h = DTAP_ZONE_CONFIG.h,
            },
            overrides = {
                "tap_forward",
                "tap_backward",
            },
            handler = function() return self:onTapShowConfigMenu() end,
        },
        {
            id = "readerconfigmenu_ext_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG_EXT.x, ratio_y = DTAP_ZONE_CONFIG_EXT.y,
                ratio_w = DTAP_ZONE_CONFIG_EXT.w, ratio_h = DTAP_ZONE_CONFIG_EXT.h,
            },
            overrides = {
                "readerconfigmenu_tap",
            },
            handler = function() return self:onTapShowConfigMenu() end,
        },
        {
            id = "readerconfigmenu_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG.x, ratio_y = DTAP_ZONE_CONFIG.y,
                ratio_w = DTAP_ZONE_CONFIG.w, ratio_h = DTAP_ZONE_CONFIG.h,
            },
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            },
            handler = function(ges) return self:onSwipeShowConfigMenu(ges) end,
        },
        {
            id = "readerconfigmenu_ext_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG_EXT.x, ratio_y = DTAP_ZONE_CONFIG_EXT.y,
                ratio_w = DTAP_ZONE_CONFIG_EXT.w, ratio_h = DTAP_ZONE_CONFIG_EXT.h,
            },
            overrides = {
                "readerconfigmenu_swipe",
            },
            handler = function(ges) return self:onSwipeShowConfigMenu(ges) end,
        },
        {
            id = "readerconfigmenu_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG.x, ratio_y = DTAP_ZONE_CONFIG.y,
                ratio_w = DTAP_ZONE_CONFIG.w, ratio_h = DTAP_ZONE_CONFIG.h,
            },
            overrides = {
                "rolling_pan",
                "paging_pan",
            },
            handler = function(ges) return self:onSwipeShowConfigMenu(ges) end,
        },
        {
            id = "readerconfigmenu_ext_pan",
            ges = "pan",
            screen_zone = {
                ratio_x = DTAP_ZONE_CONFIG_EXT.x, ratio_y = DTAP_ZONE_CONFIG_EXT.y,
                ratio_w = DTAP_ZONE_CONFIG_EXT.w, ratio_h = DTAP_ZONE_CONFIG_EXT.h,
            },
            overrides = {
                "readerconfigmenu_pan",
            },
            handler = function(ges) return self:onSwipeShowConfigMenu(ges) end,
        },
    })
end

function ReaderConfig:onShowConfigMenu()
    self.config_dialog = ConfigDialog:new{
        dimen = self.dimen:copy(),
        document = self.document,
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
    self.ui:handleEvent(Event:new("HandledAsSwipe")) -- cancel any pan scroll made

    return true
end

function ReaderConfig:onTapShowConfigMenu()
    if self.activation_menu ~= "swipe" then
        self:onShowConfigMenu()
        return true
    end
end

function ReaderConfig:onSwipeShowConfigMenu(ges)
    if self.activation_menu ~= "tap" and ges.direction == "north" then
        self:onShowConfigMenu()
        return true
    end
end

function ReaderConfig:onSetDimensions(dimen)
    -- since we cannot redraw config_dialog with new size, we close
    -- the old one on screen size change
    if self.config_dialog then
        self.config_dialog:closeDialog()
    end
end

function ReaderConfig:onCloseCallback()
    self.last_panel_index = self.config_dialog.panel_index
    self.config_dialog = nil
    self.ui:handleEvent(Event:new("RestoreHinting"))
end

-- event handler for readercropping
function ReaderConfig:onCloseConfigMenu()
    if self.config_dialog then
        self.config_dialog:closeDialog()
    end
end

function ReaderConfig:onReadSettings(config)
    self.configurable:loadSettings(config, self.options.prefix.."_")
    local config_panel_index = config:readSetting("config_panel_index")
    if config_panel_index then
        config_panel_index = math.min(config_panel_index, #self.options)
    end
    self.last_panel_index = config_panel_index or 1
end

function ReaderConfig:onSaveSettings()
    self.configurable:saveSettings(self.ui.doc_settings, self.options.prefix.."_")
    self.ui.doc_settings:saveSetting("config_panel_index", self.last_panel_index)
end

return ReaderConfig
