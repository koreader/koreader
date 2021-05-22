local Notification = require("ui/widget/notification")
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
    text = _("Notifications"),
    help_text = _([[Notification popups may be shown at the top of screen on various occasions.
This allows selecting which to show or hide.]]),
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
    }
}
