local Notification = require("ui/widget/notification")
local _ = require("gettext")

local band = bit.band
local bor = bit.bor
local bxor = bit.bxor

local function isMaskEnabled(source)
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
    return band(mask, source) ~= 0
end

local function toggleMask(source)
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
    G_reader_settings:saveSetting("notification_sources_to_show_mask", bxor(mask, source))
end

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
        text = _("No notification"),
        help_text = _("No notification popups will be shown."),
        checked_func = function()
            return getMask() == Notification.SOURCE_NONE
        end,
        callback = function()
            setMask(Notification.SOURCE_NONE)
        end,
        separator = true,
        },
        {
        text = _("Some notifications from bottom menu"),
        help_text = _("Show notification popups for bottom menu settings with no visual feedback."),
        checked_func = function()
            return band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_SOME, Notification.SOURCE_BOTTOM_MENU)
        end,
        callback = function()
            if getMask() == Notification.SOURCE_ALL then
                setMask(Notification.SOURCE_NONE)
            end
            setMask(bor(
                    band(Notification.SOURCE_SOME, Notification.SOURCE_BOTTOM_MENU),
                    band(getMask(), Notification.SOURCE_DISPATCHER)))
        end,
        },
        {
        text = _("More notifications from bottom menu"),
        help_text = _("Show notification popups for more bottom menu settings."),
        checked_func = function()
            return band(getMask(), Notification.SOURCE_BOTTOM_MENU) == band(Notification.SOURCE_DEFAULT, Notification.SOURCE_BOTTOM_MENU)
        end,
        callback = function()
            if getMask() == Notification.SOURCE_ALL then
                setMask(Notification.SOURCE_NONE)
            end
            setMask(bor(
                    band(Notification.SOURCE_DEFAULT, Notification.SOURCE_BOTTOM_MENU),
                    band(getMask(), Notification.SOURCE_DISPATCHER)))
        end,
        },
        {
        text = _("Notifications from gestures and profiles"),
        help_text = _("Show notification popups for changes from gestures and the profiles plugin."),
        checked_func = function()
            return band(getMask(), Notification.SOURCE_DISPATCHER) ~= 0 and getMask() ~= Notification.SOURCE_ALL
        end,
        callback = function()
            if getMask() == Notification.SOURCE_ALL then
                setMask(Notification.SOURCE_NONE)
            end

            setMask(bor(
                    Notification.SOURCE_DISPATCHER,
                    band(getMask(), Notification.SOURCE_BOTTOM_MENU)))
        end,
        separator = true,
        },
    }
}
