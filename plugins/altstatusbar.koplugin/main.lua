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
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local logger = require("logger")
local _ = require("gettext")

local AltStatusBar = WidgetContainer:new{
    name = "altstatusbar",
    is_doc_only = true,
}

function AltStatusBar:onReadSettings(config)
    if self.document.provider == "crengine" then
        self.config = config
        self.title = G_reader_settings:readSetting("cre_header_title") or 1
        self.clock = G_reader_settings:readSetting("cre_header_clock") or 1
        self.page_number = G_reader_settings:readSetting("cre_header_page_number") or 1
        self.page_count = G_reader_settings:readSetting("cre_header_page_count") or 1
        self.reading_percent = G_reader_settings:readSetting("cre_header_reading_percent") or 0
        self.battery = G_reader_settings:readSetting("cre_header_battery") or 1
        self.battery_percent = G_reader_settings:readSetting("cre_header_battery_percent") or 0
        self.chapter_marks = G_reader_settings:readSetting("cre_header_chapter_marks") or 1

        self.ui.document._document:setIntProperty("window.status.title", self.title)
        self.ui.document._document:setIntProperty("window.status.clock", self.clock)
        self.ui.document._document:setIntProperty("window.status.pos.page.number", self.page_number)
        self.ui.document._document:setIntProperty("window.status.pos.page.count", self.page_count)
        self.ui.document._document:setIntProperty("crengine.page.header.chapter.marks", self.chapter_marks)
        self.ui.document._document:setIntProperty("window.status.battery", self.battery)
        self.ui.document._document:setIntProperty("window.status.battery.percent", self.battery_percent)
        self.ui.document._document:setIntProperty("window.status.pos.percent", self.reading_percent)

--        UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
        self.ui.menu:registerToMainMenu(self)
    else
        logger.dbg("AltStatusBar disabled")
    end
end

function AltStatusBar:addToMainMenu(menu_items)
    menu_items.alt_status_bar = {
        sorting_hint = "setting",
        text = _("Alt Status Bar"),
--        checked_func = function()
--            return self:isEnabled()
--        end,
        sub_item_table = {
            {
                text = _("Enable top status bar for new documents"),
                keep_menu_open = true,
                checked_func = function()
                    return G_reader_settings:readSetting("copt_status_line") == 0
                end,
                callback = function()
                    local old_status_line = G_reader_settings:readSetting("copt_status_line") or 1
                    G_reader_settings:saveSetting("copt_status_line", 1 - old_status_line)
                end,
            },
            {
                text = _("Enable top status bar for this document"),
                keep_menu_open = true,
                checked_func = function()
                    return self.document.configurable.status_line == 0
                end,
                callback = function()
                    self.document.configurable.status_line = 1 - self.document.configurable.status_line
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, true))
                end,
                separator = true,
            },
            {
                text = _("Title"),
                keep_menu_open = true,
                checked_func = function()
                    return self.title == 1
                end,
                callback = function()
                    self.title = 1 - self.title
                    self.ui.document._document:setIntProperty("window.status.title", self.title)
                    G_reader_settings:saveSetting("cre_header_title", self.title)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                hold_callback = function()
                    self:setDefaultBehavior(_("Title"), "cre_header_title")
                end,
            },
            {
                text = _("Clock"),
                keep_menu_open = true,
                checked_func = function()
                    return self.clock == 1
                end,
                callback = function()
                    self.clock = 1 - self.clock
                    self.ui.document._document:setIntProperty("window.status.clock", self.clock)
                    G_reader_settings:saveSetting("cre_header_clock", self.clock)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Page number"),
                keep_menu_open = true,
                checked_func = function()
                    return self.page_number == 1
                end,
                callback = function()
                    self.page_number = 1 - self.page_number
                    self.ui.document._document:setIntProperty("window.status.pos.page.number", self.page_number)
                    G_reader_settings:saveSetting("cre_header_page_number", self.page_number)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Page count"),
                keep_menu_open = true,
                checked_func = function()
                    return self.page_count == 1
                end,
                callback = function()
                    self.page_count = 1 - self.page_count
                    self.ui.document._document:setIntProperty("window.status.pos.page.count", self.page_count)
                    G_reader_settings:saveSetting("cre_header_page_count", self.page_count)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Reading percent"),
                keep_menu_open = true,
                checked_func = function()
                    return self.reading_percent == 1
                end,
                callback = function()
                    self.reading_percent = 1 - self.reading_percent
                    self.ui.document._document:setIntProperty("window.status.pos.percent", self.reading_percent)
                    G_reader_settings:saveSetting("cre_header_reading_percent", self.reading_percent)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Battery"),
                keep_menu_open = true,
                checked_func = function()
                    return self.battery == 1
                end,
                callback = function()
                    self.battery = 1 - self.battery
                    self.ui.document._document:setIntProperty("window.status.battery", self.battery)
                    G_reader_settings:saveSetting("cre_header_battery", self.battery)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Battery Percent"),
                keep_menu_open = true,
                enabled_func = function()
                    return self.battery == 1
                end,
                checked_func = function()
                    return self.battery_percent == 1
                end,
                callback = function()
                    self.battery_percent = 1 - self.battery_percent
                    self.ui.document._document:setIntProperty("window.status.battery.percent", self.battery_percent)
                    G_reader_settings:saveSetting("cre_header_battery_percent", self.battery_percent)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
            },
            {
                text = _("Chapter marks"),
                keep_menu_open = true,
                checked_func = function()
                    return self.chapter_marks == 1
                end,
                callback = function()
                    self.chapter_marks = 1 - self.chapter_marks
                    self.ui.document._document:setIntProperty("crengine.page.header.chapter.marks", self.chapter_marks)
                    G_reader_settings:saveSetting("cre_header_chapter_marks", self.chapter_marks)
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
                end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Header font size (%1)"), G_reader_settings:readSetting("cre_header_status_font_size") or 14 )
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
