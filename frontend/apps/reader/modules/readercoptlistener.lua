local Event = require("ui/event")
local Device = require("device")
local EventListener = require("ui/widget/eventlistener")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderCoptListener = EventListener:new{}

function ReaderCoptListener:onReadSettings(config)
    local view_mode = config:readSetting("copt_view_mode")
                   or G_reader_settings:readSetting("copt_view_mode")
                   or 0 -- default to "page" mode
    local view_mode_name = view_mode == 0 and "page" or "scroll"
    -- Let crengine know of the view mode before rendering, as it can
    -- cause a rendering change (2-pages would become 1-page in
    -- scroll mode).
    self.ui.document:setViewMode(view_mode_name)
    -- ReaderView is the holder of the view_mode state
    self.view.view_mode = view_mode_name

    -- crengine top status bar can only show author and title together
    self.title = G_reader_settings:readSetting("cre_header_title") or 1
    self.clock = G_reader_settings:readSetting("cre_header_clock") or 1
    self.header_auto_refresh = G_reader_settings:readSetting("cre_header_auto_refresh") or 1
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

    self:onTimeFormatChanged()

    -- Enable or disable crengine header status line (note that for crengine, 0=header enabled, 1=header disabled)
    local status_line = config:readSetting("copt_status_line") or G_reader_settings:readSetting("copt_status_line") or 1
    self.ui:handleEvent(Event:new("SetStatusLine", status_line))

    self.old_battery_level = Device:getPowerDevice():getCapacity()

    -- Have this ready in case auto-refresh is enabled, now or later
    self.headerRefresh = function()
        -- Only draw it if the header is shown...
        if self.document.configurable.status_line == 0 and self.view.view_mode == "page" then
            -- ...and something has changed
            local new_battery_level = Device:getPowerDevice():getCapacity()
            if self.clock == 1 or (self.battery == 1 and new_battery_level ~= self.old_battery_level) then
                self.old_battery_level = new_battery_level
                self:updateHeader()
            end
        end
        self:rescheduleHeaderRefreshIfNeeded() -- schedule (or not) next refresh
    end
    self:rescheduleHeaderRefreshIfNeeded() -- schedule (or not) first refresh
end

function ReaderCoptListener:onConfigChange(option_name, option_value)
    self.document.configurable[option_name] = option_value
    self.ui:handleEvent(Event:new("StartActivityIndicator"))
    return true
end

function ReaderCoptListener:onSetFontSize(font_size)
    self.document.configurable.font_size = font_size
end

function ReaderCoptListener:onCharging()
    self:headerRefresh()
end

function ReaderCoptListener:onNotCharging()
    self:headerRefresh()
end

function ReaderCoptListener:onTimeFormatChanged()
    self.ui.document._document:setIntProperty("window.status.clock.12hours", G_reader_settings:isTrue("twelve_hour_clock") and 1 or 0)
end

function ReaderCoptListener:updateHeader()
    -- Have crengine display accurate time and battery on its next drawing
    self.ui.rolling:updateBatteryState()
    self.ui.document:resetBufferCache() -- be sure next repaint is a redrawing
    -- Force a refresh if we're not hidden behind another widget
    if UIManager:getTopWidget() == "ReaderUI" then
        UIManager:setDirty(self.view.dialog, "ui",
            Geom:new{
                x = 0, y = 0,
                w = Device.screen:getWidth(),
                h = self.ui.document:getHeaderHeight(),
            }
        )
    end
end

function ReaderCoptListener:unscheduleHeaderRefresh()
    if not self.headerRefresh then return end -- not yet set up
    UIManager:unschedule(self.headerRefresh)
    logger.dbg("ReaderCoptListener.headerRefresh unscheduled")
end

function ReaderCoptListener:rescheduleHeaderRefreshIfNeeded()
    if not self.headerRefresh then return end -- not yet set up
    local unscheduled = UIManager:unschedule(self.headerRefresh) -- unschedule if already scheduled
    -- Only schedule an update if the header is actually visible
    if self.header_auto_refresh == 1
            and self.document.configurable.status_line == 0 -- top bar enabled
            and self.view.view_mode == "page" -- not in scroll mode (which would disable the header)
            and (self.clock == 1 or self.battery == 1) then -- something shown can change in next minute
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.headerRefresh)
        if not unscheduled then
            logger.dbg("ReaderCoptListener.headerRefresh scheduled")
        else
            logger.dbg("ReaderCoptListener.headerRefresh rescheduled")
        end
    elseif unscheduled then
        logger.dbg("ReaderCoptListener.headerRefresh unscheduled")
    end
end

-- Schedule or stop scheluding on these events, as they may change what is shown:
ReaderCoptListener.onSetStatusLine = ReaderCoptListener.rescheduleHeaderRefreshIfNeeded
    -- configurable.status_line is set before this event is triggered
ReaderCoptListener.onSetViewMode = ReaderCoptListener.rescheduleHeaderRefreshIfNeeded
    -- ReaderView:onSetViewMode(), which sets view.view_mode, is called before
    -- ReaderCoptListener.onSetViewMode, so we'll get the updated value
function ReaderCoptListener:onResume()
    -- Don't repaint the header until OutOfScreenSaver if screensaver_delay is enabled...
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    if screensaver_delay and screensaver_delay ~= "disable" then
        self._delayed_screensaver = true
        return
    end

    self:headerRefresh()
end

function ReaderCoptListener:onOutOfScreenSaver()
    if not self._delayed_screensaver then
        return
    end

    self._delayed_screensaver = nil
    self:headerRefresh()
end

-- Unschedule on these events
ReaderCoptListener.onCloseDocument = ReaderCoptListener.unscheduleHeaderRefresh
ReaderCoptListener.onSuspend = ReaderCoptListener.unscheduleHeaderRefresh

function ReaderCoptListener:setAndSave(setting, property, value)
    self.ui.document._document:setIntProperty(property, value)
    G_reader_settings:saveSetting(setting, value)
    -- Have crengine redraw it (even if hidden by the menu at this time)
    self:updateHeader()
    -- And see if we should auto-refresh
    self:rescheduleHeaderRefreshIfNeeded()
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
                text = _("Auto refresh"),
                checked_func = function()
                    return self.header_auto_refresh == 1
                end,
                callback = function()
                    self.header_auto_refresh = self.header_auto_refresh == 0 and 1 or 0
                    G_reader_settings:saveSetting("cre_header_auto_refresh", self.header_auto_refresh)
                    self:rescheduleHeaderRefreshIfNeeded()
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
                            status = _("percentage")
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
                            -- This could change the header height, and as we refresh only on the
                            -- new height, we could get part of a previous taller status bar
                            -- still displayed. But as all this is covered by this menu that
                            -- we keep open, no need to handle this case.
                            self:setAndSave("cre_header_status_font_size", "crengine.page.header.font.size", spin.value)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                            -- Repaint the whole page, as changing this should cause a re-rendering
                            UIManager:setDirty(self.view.dialog, "ui")
                        end
                    }
                    UIManager:show(size_spinner)
                end,
            },
        },
    }
end

return ReaderCoptListener
