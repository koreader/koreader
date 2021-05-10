local Notification = require("ui/widget/notification")
local _ = require("gettext")

local band = bit.band
local bxor = bit.bxor

local function isSourceEnabled(source)
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
    return band(mask, source) ~= 0
end

local function toggleSource(source)
    local mask = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
    G_reader_settings:saveSetting("notification_sources_to_show_mask", bxor(mask, source))
end

return {
    text = _("Notification level"),
    help_text = _([[KOReader may show notification popups at top of screen on various occasions.
You can decide here what kind of notifications to show or hide.]]),
    checked_func = function()
        local value = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
        return  value ~= 0
    end,
    sub_item_table = {
        {
        text = _("Bottom menu icons"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_BOTTOM_MENU_ICON)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_BOTTOM_MENU_ICON)
        end,
        },
        {
        text = _("Bottom menu toggles"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_BOTTOM_MENU_TOGGLE)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_BOTTOM_MENU_TOGGLE)
        end,
        },
        {
        text = _("Bottom menu fine tuning"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_BOTTOM_MENU_FINE)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_BOTTOM_MENU_FINE)
        end,
        },
        {
        text = _("Bottom menu three dots"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_BOTTOM_MENU_MORE)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_BOTTOM_MENU_MORE)
        end,
        },
        {
        text = _("Dispatcher"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_DISPATCHER)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_DISPATCHER)
        end,
        },
        {
        text = _("Gestures"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_GESTURE)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_GESTURE)
        end,
        },
        {
        text = _("Events"),
        checked_func = function()
            return isSourceEnabled(Notification.SOURCE_EVENT)
        end,
        callback = function()
            toggleSource(Notification.SOURCE_EVENT)
        end,
        },
    },
}
