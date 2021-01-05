-- plugin for configuration of the Alt Status Bar

--[[
from https://github.com/koreader/koreader/issues/5848#issuecomment-584682914
thanks to @poire-z
That top status bar is not managed by KOReader, but by crengine (the engine thats renders EPUB files).
You can tweak a bit of what it will show/not show by editing koreader/data/cr3.ini, these bits should apply to it:

crengine.page.header.chapter.marks=1
crengine.page.header.font.color=0xFF000000
crengine.page.header.font.face=Noto Sans
crengine.page.header.font.size=22

window.status.battery=1
window.status.battery.percent=0
window.status.clock=0
window.status.line=0
window.status.pos.page.count=1
window.status.pos.page.number=1
window.status.pos.percent=0
window.status.title=1
]]

--if true then return { disabled = true, } end

local Device = require("device")
local Event = require("ui/event")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local logger = require("logger")
local _ = require("gettext")

local AltStatusBar = WidgetContainer:new{
    name = "altstatusbar",
    is_doc_only = true,
}

function AltStatusBar:isEnabled()
    return self.document.configurable.status_line == 0
end

function AltStatusBar:onReadSettings()
    if self.document.provider == "crengine" then
        self.enabled = self:isEnabled()
        self.document.configurable.title = self.document.configurable.title
            or G_reader_settings:readSetting("copt_title") or 1
        self.document.configurable.clock = self.document.configurable.clock
            or G_reader_settings:readSetting("copt_clock") or 1
        self.document.configurable.page_number = self.document.configurable.page_number
            or G_reader_settings:readSetting("copt_page_number") or 1
        self.document.configurable.page_count = self.document.configurable.page_count
            or G_reader_settings:readSetting("copt_page_count") or 1
        self.document.configurable.battery = self.document.configurable.battery
            or G_reader_settings:readSetting("copt_battery") or 1
        self.document.configurable.battery_percent = self.document.configurable.battery_percent
            or G_reader_settings:readSetting("copt_battery_percent") or 0

        self.ui.document._document:setIntProperty("window.status.title", self.document.configurable.title)
        self.ui.document._document:setIntProperty("window.status.clock", self.document.configurable.clock)
        self.ui.document._document:setIntProperty("window.status.pos.page.number", self.document.configurable.page_number)
        self.ui.document._document:setIntProperty("window.status.pos.page.count", self.document.configurable.page_count)
        self.ui.document._document:setIntProperty("window.status.battery", self.document.configurable.battery)
        self.ui.document._document:setIntProperty("window.status.battery.percent", self.document.configurable.battery_percent)

        UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))

        self.ui.menu:registerToMainMenu(self)
    else
        logger.dbg("AltStatusBar disabled")
    end
end

function AltStatusBar:setDefaultBehavior(title, key, inverse)
    local inverse_val = 0
    if inverse then
        inverse_val = 1
    end
    UIManager:show( ConfirmBox:new{
        text = T(_("Set default of \"%1\" to"), title),
        cancel_text = _("Off"),
        ok_text = _("On"),
        ok_callback = function()
            G_reader_settings:saveSetting(key, inverse_val - 1)
        end,
        cancel_callback = function()
            G_reader_settings:saveSetting(key, inverse_val - 0)
        end,
    })
end

function AltStatusBar:addToMainMenu(menu_items)
    menu_items.alt_status_bar = {
        sorting_hint = "setting",
        text = _("Alternate status bar"),
        checked_func = function()
            return self:isEnabled()
        end,
        sub_item_table = {
            {
                text = _("Top status bar"),
                keep_menu_open = true,
                checked_func = function()
                    return self:isEnabled()
                end,
                callback = function()
                    self.document.configurable.status_line = 1 - self.document.configurable.status_line
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Top status bar"), "copt_status_line", true)
                end,
            },
            {
                text = _("Title"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled()
                end,
                checked_func = function()
                    return self.document.configurable.title == 1
                end,
                callback = function()
                    self.document.configurable.title = 1 - self.document.configurable.title
                    self.ui.document._document:setIntProperty("window.status.title", self.document.configurable.title)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Title"), "copt_title")
                end,
            },
            {
                text = _("Clock"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled()
                end,
                checked_func = function()
                    return self.document.configurable.clock == 1
                end,
                callback = function()
                    self.document.configurable.clock = 1 - self.document.configurable.clock
                    self.ui.document._document:setIntProperty("window.status.clock", self.document.configurable.clock)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Clock"), "copt_clock")
                end,
            },
            {
                text = _("Page number"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled()
                end,
                checked_func = function()
                    return self.document.configurable.page_number == 1
                end,
                callback = function()
                    self.document.configurable.page_number = 1 - self.document.configurable.page_number
                    self.ui.document._document:setIntProperty("window.status.pos.page.number", self.document.configurable.page_number)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Page number"), "copt_page_number")
                end,
            },
            {
                text = _("Page count"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled()
                end,
                checked_func = function()
                    return self.document.configurable.page_count == 1
                end,
                callback = function()
                    self.document.configurable.page_count = 1 - self.document.configurable.page_count
                    self.ui.document._document:setIntProperty("window.status.pos.page.count", self.document.configurable.page_count)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Page count"), "copt_page_count")
                end,
            },
            {
                text = _("Battery"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled()
                end,
                checked_func = function()
                    return self.document.configurable.battery == 1
                end,
                callback = function()
                    self.document.configurable.battery = 1 - self.document.configurable.battery
                    self.ui.document._document:setIntProperty("window.status.battery", self.document.configurable.battery)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Battery"), "copt_battery")
                end,
            },
            {
                text = _("Battery Percent"),
                keep_menu_open = true,
                enabled_func = function()
                    return self:isEnabled() and self.document.configurable.battery == 1
                end,
                checked_func = function()
                    return self.document.configurable.battery_percent == 1
                end,
                callback = function()
                    self.document.configurable.battery_percent = 1 - self.document.configurable.battery_percent
                    self.ui.document._document:setIntProperty("window.status.battery.percent", self.document.configurable.battery_percent)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Pattery Percent"), "copt_battery_percent")
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Header font size (%1)"), G_reader_settings:readSetting("cre_header_status_font_size") or 14 )
                end,
                enabled_func = function()
                    return self:isEnabled()
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local start_size = G_reader_settings:readSetting("cre_header_status_font_size") or 14
                    local size_spinner = SpinWidget:new{
                        width = math.floor(Device.screen:getWidth() * 0.6),
                        value = start_size,
                        value_min = 8,
                        value_max = 36,
                        default_value = 14,
                        title_text =  _("Size of top status bar"),
                        ok_text = _("Set size"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            G_reader_settings:saveSetting("cre_header_status_font_size", spin.value)
                            G_reader_settings:flush()
                            self.ui.document._document:setIntProperty("crengine.page.header.font.size", spin.value)
                            UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(size_spinner)
                end,
                keep_menu_open = true,
            },
        },
    }
end

return AltStatusBar
