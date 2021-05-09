local Notification = require("ui/widget/notification")
local _ = require("gettext")

local band = bit.band
local bxor = bit.bxor

return {
    text = _("Notification level"),
    help_text = _("You can tune the number of popup Notifications"),
    checked_func = function()
        local value = G_reader_settings:readSetting("verbosity_popups")
        if not value then
            return false
        else
            return  value ~= 0
        end
    end,
    sub_item_table = {
        {
        text = _("Bottom menu icons"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_ICON) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_ICON))
        end,
        },
        {
        text = _("Bottom menu toggles"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_TOGGLE) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_TOGGLE))
        end,
        },
        {
        text = _("Bottom menu fine tuning"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_FINE) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_FINE))
        end,
        },
        {
        text = _("Bottom menu three dots"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_MORE) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_BOTTOM_MENU_MORE))
        end,
        },
        {
        text = _("Dispatcher"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_DISPATCHER) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_DISPATCHER))
        end,
        },
        {
        text = _("Gestures"),
        checked_func = function()
            return band(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_GESTURE) ~= 0
        end,
        callback = function()
            G_reader_settings:saveSetting("verbosity_popups",
                bxor(G_reader_settings:readSetting("verbosity_popups"), Notification.SOURCE_GESTURE))
        end,
        },

    },
}
