-- plugin for configuration of the Alt Status Bar

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

function AltStatusBar:init()
    self.enabled = self:isEnabled()
    self.document.configurable.title = self.ui.doc_settings:readSetting("copt_title")
        or G_reader_settings:readSetting("copt_title") or 1
    self.document.configurable.clock = self.ui.doc_settings:readSetting("copt_clock")
        or G_reader_settings:readSetting("copt_clock") or 1
    self.document.configurable.page_number = self.ui.doc_settings:readSetting("copt_page_number")
        or G_reader_settings:readSetting("copt_page_number") or 1
    self.document.configurable.page_count = self.ui.doc_settings:readSetting("copt_page_count")
        or G_reader_settings:readSetting("copt_page_count") or 1
    self.document.configurable.battery = self.ui.doc_settings:readSetting("copt_battery")
        or G_reader_settings:readSetting("copt_battery") or 1
    self.document.configurable.battery_percent = self.ui.doc_settings:readSetting("copt_battery_percent")
        or G_reader_settings:readSetting("copt_battery_percent") or 0

    -- set top status bar title
    if self.document.configurable.title then
        self.ui.document._document:setIntProperty("window.status.title", self.document.configurable.title)
    end
    -- set top status bar clock
    if self.document.configurable.clock then
        self.ui.document._document:setIntProperty("window.status.clock", self.document.configurable.clock)
    end
    -- set top status bar page number
    if self.document.configurable.page_number then
        self.ui.document._document:setIntProperty("window.status.pos.page.number", self.document.configurable.page_number)
    end
    -- set top status bar page count
    if self.document.configurable.page_count then
        self.ui.document._document:setIntProperty("window.status.pos.page.count", self.document.configurable.page_count)
    end
    -- set top status bar battery
    if self.document.configurable.battery then
        self.ui.document._document:setIntProperty("window.status.battery", self.document.configurable.battery)
    end
    -- set top status bar battery percent
    if self.document.configurable.battery_percent then
        self.ui.document._document:setIntProperty("window.status.battery.percent", self.document.configurable.battery_percent)
    end
    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))

    self.ui.menu:registerToMainMenu(self)
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
                text = _("Enable top status bar"),
                keep_menu_open = true,
                checked_func = function()
                    return self:isEnabled()
                end,
                callback = function()
                    self.document.configurable.status_line = 1 - self.document.configurable.status_line
                    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, false))
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_title", 1)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_title", 0)
                        end,
                    })
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_clock", 1)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_clock", 0)
                        end,
                    })
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_page_number", 0)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_page_number", 0)
                        end,
                    })
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_page_count", 1)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_page_count", 0)
                        end,
                    })
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_battery", 1)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_battery", 0)
                        end,
                    })
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
                    UIManager:show( ConfirmBox:new{
                        text = _("Default behavior"),
                        cancel_text = _("Disable"),
                        ok_text = _("Enable"),
                        ok_callback = function()
                            G_reader_settings:saveSetting("copt_battery_percent", 1)
                        end,
                        cancel_callback = function()
                            G_reader_settings:saveSetting("copt_battery_percent", 0)
                        end,
                    })
                end,
                separator = true,
            },
            {
                -- todo save in sdr
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
