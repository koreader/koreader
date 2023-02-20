local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local band = bit.band
local bor = bit.bor

local function setMask(source)
    G_reader_settings:saveSetting("notification_sources_to_show_mask", source)
end

local function getMask()
    return G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
end

return {
    text = _("Notifications and info-messages"),
    help_text = _([[Notification popups may be shown at the top of screen on various occasions.
This allows selecting which to show or hide.\n
Past notifications and info-massages can be retrieved.]]),
    checked_func = function()
        local value = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
        return  value ~= 0
    end,
    sub_item_table = {
        {
            text = _("Some notifications from bottom menu"),
            help_text = _("Show notification popups for bottom menu settings with no visual feedback."),
            checked_func = function()
                return band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_SOME, Notification.SOURCE_BOTTOM_MENU)
            end,
            callback = function()
                if band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_SOME, Notification.SOURCE_BOTTOM_MENU) then
                    setMask(bor(
                        Notification.SOURCE_NONE,
                        band(getMask(), Notification.SOURCE_DISPATCHER)))
                else
                    setMask(bor(
                        band(Notification.SOURCE_SOME, Notification.SOURCE_BOTTOM_MENU),
                        band(getMask(), Notification.SOURCE_DISPATCHER)))
                end
            end,
        },
        {
            text = _("More notifications from bottom menu"),
            help_text = _("Show notification popups for more bottom menu settings."),
            checked_func = function()
                return band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_DEFAULT, Notification.SOURCE_BOTTOM_MENU)
            end,
            callback = function()
                if band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_DEFAULT, Notification.SOURCE_BOTTOM_MENU) then
                    setMask(bor(
                        Notification.SOURCE_NONE,
                        band(getMask(), Notification.SOURCE_DISPATCHER)))
                else
                    setMask(bor(
                        band(Notification.SOURCE_DEFAULT, Notification.SOURCE_BOTTOM_MENU),
                        band(getMask(), Notification.SOURCE_DISPATCHER)))
                end
            end,
        },
        {
            text = _("Notifications from gestures and profiles"),
            help_text = _("Show notification popups for changes from gestures and the profiles plugin."),
            checked_func = function()
                return band(getMask(), Notification.SOURCE_DISPATCHER) == Notification.SOURCE_DISPATCHER
            end,
            callback = function()
                if band(getMask(), Notification.SOURCE_DISPATCHER) == Notification.SOURCE_DISPATCHER then
                    setMask(bor(
                        Notification.SOURCE_NONE,
                        band(getMask(), Notification.SOURCE_BOTTOM_MENU)))
                else
                    setMask(bor(
                        Notification.SOURCE_DISPATCHER,
                        band(getMask(), Notification.SOURCE_BOTTOM_MENU)))
                end
            end,
            separator = true,
        },
        {
            text = _("Show past notifications"),
            help_text = _("Show the text of past Notifications."),
            callback = function()
                local file = io.open(Notification.log_file_name, "rb")
                local content
                if file then
                    content = file:read("*all")
                    file:close()
                end

                if not content then
                    content = _("No notifications available.")
                end

                local textviewer
                textviewer = TextViewer:new{
                    title = _("Past notifications"),
                    text = content,
                    justified = false,
                }
                UIManager:show(textviewer)
            end,
            keep_menu_open = true,
        },
        {
            text = _("Show past info-messages"),
            help_text = _("Show the text of past info-messages."),
            callback = function()
                local InfoMessage = require("ui/widget/infomessage")
                local file = io.open(InfoMessage.log_file_name, "rb")
                local content
                if file then
                    content = file:read("*all")
                    file:close()
                end

                if not content then
                    content = _("No info-messages available.")
                end
                local textviewer
                textviewer = TextViewer:new{
                    title = _("Past info-messages"),
                    text = content,
                    justified = false,
                    start_at_end = true,
                }
                UIManager:show(textviewer)
            end,
            keep_menu_open = true,
            separator = true,
        },
    }
}
