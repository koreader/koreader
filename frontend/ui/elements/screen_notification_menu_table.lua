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

local function showExpertMenu(toggle)
    if toggle and toggle==true then
        return {
            text = _("Expert notification settings"),
            help_text =_("Here you can set the sources of popup notifications on a fine grain scale."),
            sub_item_table = {
                {
                text = _("Bottom menu icons"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_BOTTOM_MENU_ICON)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_BOTTOM_MENU_ICON)
                end,
                },
                {
                text = _("Bottom menu toggles"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_BOTTOM_MENU_TOGGLE)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_BOTTOM_MENU_TOGGLE)
                end,
                },
                {
                text = _("Bottom menu fine tuning"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_BOTTOM_MENU_FINE)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_BOTTOM_MENU_FINE)
                end,
                },
                {
                text = _("Bottom menu three dots"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_BOTTOM_MENU_MORE)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_BOTTOM_MENU_MORE)
                end,
                },
                {
                text = _("Dispatcher"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_DISPATCHER)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_DISPATCHER)
                end,
                },
                {
                text = _("Events"),
                checked_func = function()
                    return isMaskEnabled(Notification.SOURCE_EVENT)
                end,
                callback = function()
                    toggleMask(Notification.SOURCE_EVENT)
                end,
                },
            },
        }
    end
    return ""
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
        text = _("No popups"),
        help_text = _("No popups are shown at all."),
        checked_func = function()
            return getMask() == Notification.SOURCE_NONE
        end,
        callback = function()
            setMask(Notification.SOURCE_NONE)
        end,
        separator = true,
        },
        {
        text = _("Only some bottom menu popus"),
        help_text = _("Just show popups from the bottom menu, which don't have visual feedback."),
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
        text = _("A lot of bottom menu popus"),
        help_text = _("Show popups from the bottom menu, which don't have visual feedback and popups from the three dots menus."),
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
        text = _("Dispatcher and Gestures"),
        help_text = _("Show popups on dispatcher gestures."),
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
        {
        text = _("Inflationary"),
        help_text = _("Show really many popups. This would include also keyboard events"),
        checked_func = function()
            return getMask() == Notification.SOURCE_ALL
        end,
        callback = function()
            print(getMask())
            print(Notification.SOURCE_ALL)
            setMask(Notification.SOURCE_ALL)
            print(getMask())
        end,
        separator = true,
        },
        showExpertMenu( true ),
    }
}
