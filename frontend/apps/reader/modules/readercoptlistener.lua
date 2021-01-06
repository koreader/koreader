local Event = require("ui/event")
local Device = require("device")
local EventListener = require("ui/widget/eventlistener")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

--local ReaderCoptListener = WidgetContainer:new{
--    name = "alt_status_bar",
--    is_doc_only = true,
--}
local ReaderCoptListener = EventListener:new{
    name = "alt_status_bar",
    is_doc_only = true,
}

function ReaderCoptListener:onReadSettings(config)
    local view_mode = config:readSetting("copt_view_mode") or
           G_reader_settings:readSetting("copt_view_mode")
    if view_mode == 0 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("page")
        end)
    elseif view_mode == 1 then
        self.ui:registerPostReadyCallback(function()
            self.view:onSetViewMode("scroll")
        end)
    end

    local status_line = config:readSetting("copt_status_line") or G_reader_settings:readSetting("copt_status_line") or 1
    self.ui:handleEvent(Event:new("SetStatusLine", status_line, true))

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

    self.ui.menu:registerToMainMenu(self)
end

function ReaderCoptListener:onSetFontSize(font_size)
    self.document.configurable.font_size = font_size
end

function ReaderCoptListener:setAndSave(property, setting, value)
    self.ui.document._document:setIntProperty(property, value)
    G_reader_settings:saveSetting(setting, value)
    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, true))
end

local about_text = _([[
Here you can set the items shown in the top status bar.

The settings here will only affect CRE documents in page mode.

The top status bar (per document or by default) has to be enabled in the bottom menu.]])

function ReaderCoptListener:addToMainMenu(menu_items)
    menu_items.alt_status_bar = {
        text = _("Alt status bar"),
        sub_item_table = {
            {
                text = _("About cover image"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
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
                    self:setAndSave("window.status.title", "cre_header_title", self.title)
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
                    self:setAndSave("window.status.clock", "cre_header_clock", self.clock)
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
                    self:setAndSave("window.status.pos.page.number", "cre_header_page_number", self.page_number)
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
                    self:setAndSave("window.status.pos.page.count", "cre_header_page_count", self.page_count)
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
                    self:setAndSave("window.status.pos.percent", "cre_header_reading_percent", self.reading_percent)
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
                    self:setAndSave("window.status.battery", "cre_header_battery", self.battery)
                end,
            },
            {
                text = _("Battery percent"),
                keep_menu_open = true,
                enabled_func = function()
                    return self.battery == 1
                end,
                checked_func = function()
                    return self.battery_percent == 1
                end,
                callback = function()
                    self.battery_percent = 1 - self.battery_percent
                    self:setAndSave("window.status.battery.percent", "cre_header_battery_percent", self.battery_percent)
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
                    self:setAndSave("crengine.page.header.chapter.marks", "cre_header_chapter_marks", self.chapter_marks)
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
                            self:setAndSave("crengine.page.header.font.size", "cre_header_status_font_size", spin.value)
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

return ReaderCoptListener
