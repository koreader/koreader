local Event = require("ui/event")
local Device = require("device")
local EventListener = require("ui/widget/eventlistener")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderCoptListener = EventListener:new{}

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

    -- crengine top status bar can only show author and title together
    self.title = G_reader_settings:readSetting("cre_header_title") or 1
    self.clock = G_reader_settings:readSetting("cre_header_clock") or 1
    self.clock_auto_refresh = G_reader_settings:readSetting("cre_header_clock_auto_refresh") or 1
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

    local status_line = config:readSetting("copt_status_line") or G_reader_settings:readSetting("copt_status_line") or 1
    self.ui:handleEvent(Event:new("SetStatusLine", status_line, true))

    self.old_battery_level = Device:getPowerDevice():getCapacity()

    if self.clock_auto_refresh then
        self:setupAutoRefreshTime()
    end
end

function ReaderCoptListener:onSetFontSize(font_size)
    self.document.configurable.font_size = font_size
end

function ReaderCoptListener:setAndSave(setting, property, value)
    self.ui.document._document:setIntProperty(property, value)
    G_reader_settings:saveSetting(setting, value)
    UIManager:broadcastEvent(Event:new("SetStatusLine", self.document.configurable.status_line, true))
end

function ReaderCoptListener:UpdateHeader()
    if self.view.view_mode == "page" then
        if self.ui.document.provider == "crengine" then -- can that "if" be dropped
            self.ui.document._callCacheSet("current_buffer_tag", nil)
        end
        self.ui:handleEvent(Event:new("RedrawCurrentView", self.current_page))
    end
end

function ReaderCoptListener:setupAutoRefreshTime()
    if not self.autoRefreshTime then
        self.autoRefreshTime = function()
            -- Only actually repaint the header if nothing's being shown over ReaderUI (#6616)
            if UIManager:getTopWidget() == "ReaderUI" then
                -- And that only if it's actually visible
                if self.document.configurable.status_line == 0 then -- is top bar enabled
                    local new_battery_level = Device:getPowerDevice():getCapacity()
                    if self.clock == 1 or (self.battery == 1 and new_battery_level ~= self.old_battery_level) then
                        self:UpdateHeader(true)
                        self.old_battery_level = new_battery_level
                    end
                end
            else
                require("logger").dbg("Skipping Header repaint, because ReaderUI is not the top-level widget")
                -- NOTE: We *do* keep its content up-to-date, though
                self:UpdateHeader()
            end
            UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
        end
    end
    self.onCloseDocument = function()
        UIManager:unschedule(self.autoRefreshTime)
    end
    UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshTime)
end

function ReaderCoptListener:unsetAutoRefreshTime()
    UIManager:unschedule(self.autoRefreshTime)
end

local about_text = _([[
In CRE documents, an alternative status bar can be displayed at the top of the screen, with or without the regular bottom status bar.

Enabling this alt status bar, per document or by default, can be done in the bottom menu.

The alternative status bar can be configured here.]])

function ReaderCoptListener:getAltStatusBarMenu()
    return {
        text = _("Alt status bar"),
        separator = true,
        sub_item_table = {
            {
                text = _("About alternate status bar"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                    })
                end,
                separator = true,
            },
            {
                text = _("Auto refresh the alternate status bar"),
                checked_func = function()
                    return self.clock_auto_refresh == 1
                end,
                callback = function()
                    self.clock_auto_refresh = self.clock_auto_refresh == 0 and 1 or 0
                    G_reader_settings:saveSetting("cre_header_clock_auto_refresh", self.clock_auto_refresh)
                    if self.clock_auto_refresh then
                        self:setupAutoRefreshTime()
                    else
                        self:unsetAutoRefreshTime()
                    end
                end,
                separator = true
            },
            {
                text = _("Book author and title"),
                checked_func = function()
                    return self.title == 1
                end,
                callback = function()
                    self.title = self.title == 0 and 1 or 0
                    self:setAndSave("cre_header_title", "window.status.title", self.title)
                end,
            },
            {
                text = _("Current time"),
                checked_func = function()
                    return self.clock == 1
                end,
                callback = function()
                    self.clock = self.clock == 0 and 1 or 0
                    self:setAndSave("cre_header_clock", "window.status.clock", self.clock)
                end,
            },
            {
                text = _("Current page"),
                checked_func = function()
                    return self.page_number == 1
                end,
                callback = function()
                    self.page_number = self.page_number == 0 and 1 or 0
                    self:setAndSave("cre_header_page_number", "window.status.pos.page.number", self.page_number)
                end,
            },
            {
                text = _("Total pages"),
                checked_func = function()
                    return self.page_count == 1
                end,
                callback = function()
                    self.page_count = self.page_count == 0 and 1 or 0
                    self:setAndSave("cre_header_page_count", "window.status.pos.page.count", self.page_count)
                end,
            },
            {
                text = _("Progress percentage"),
                checked_func = function()
                    return self.reading_percent == 1
                end,
                callback = function()
                    self.reading_percent = self.reading_percent == 0 and 1 or 0
                    self:setAndSave("cre_header_reading_percent", "window.status.pos.percent", self.reading_percent)
                end,
            },
            {
                text = _("Chapter marks"),
                checked_func = function()
                    return self.chapter_marks == 1
                end,
                callback = function()
                    self.chapter_marks = self.chapter_marks == 0 and 1 or 0
                    self:setAndSave("cre_header_chapter_marks", "crengine.page.header.chapter.marks", self.chapter_marks)
                end,
            },
            {
                text_func = function()
                    local status = _("off")
                    if self.battery == 1 then
                        if self.battery_percent == 1 then
                            status = _("percent")
                        else
                            status = _("icon")
                        end
                    end
                    return T(_("Battery status (%1)"), status)
                end,
                sub_item_table = {
                    {
                        text = _("Battery icon"),
                        checked_func = function()
                            return self.battery == 1 and self.battery_percent == 0
                        end,
                        callback = function()
                            if self.battery == 0 then -- self.battery_percent don't care
                                self.battery = 1
                                self.battery_percent = 0
                            elseif self.battery == 1 and self.battery_percent == 1 then
                                self.battery = 1
                                self.battery_percent = 0
                            else
                                self.battery = 0
                                self.battery_percent = 0
                            end

                            self:setAndSave("cre_header_battery", "window.status.battery", self.battery)
                            self:setAndSave("cre_header_battery_percent", "window.status.battery.percent", self.battery_percent)
                        end,
                    },
                    {
                        text = _("Battery percentage"),
                        checked_func = function()
                            return self.battery == 1 and self.battery_percent == 1
                        end,
                        callback = function()
                            if self.battery == 0 then -- self.battery_percent don't care
                                self.battery = 1
                                self.battery_percent = 1
                            elseif self.battery == 1 and self.battery_percent == 0 then
                                self.battery_percent = 1
                            else
                                self.battery = 0
                                self.battery_percent = 0
                            end


                            self:setAndSave("cre_header_battery", "window.status.battery", self.battery)
                            self:setAndSave("cre_header_battery_percent", "window.status.battery.percent", self.battery_percent)
                        end,
                    },
                },
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Font size (%1)"), G_reader_settings:readSetting("cre_header_status_font_size") or 20 )
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local start_size = G_reader_settings:readSetting("cre_header_status_font_size") or 20
                    local size_spinner = SpinWidget:new{
                        width = math.floor(Device.screen:getWidth() * 0.6),
                        value = start_size,
                        value_min = 8,
                        value_max = 36,
                        default_value = 14,
                        keep_shown_on_apply = true,
                        title_text =  _("Size of top status bar"),
                        ok_text = _("Set size"),
                        callback = function(spin)
                            self:setAndSave("cre_header_status_font_size", "crengine.page.header.font.size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    }
                    UIManager:show(size_spinner)
                end,
            },
        },
    }
end

return ReaderCoptListener
