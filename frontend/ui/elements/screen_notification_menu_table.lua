local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local band = bit.band
local bor = bit.bor
local bnot = bit.bnot

local function getMask()
    return G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
end

local function setMask(source)
    logger.dbg(string.format("Notification: Updating display mask from %#x to %#x", getMask(), source))
    G_reader_settings:saveSetting("notification_sources_to_show_mask", source)
end

local function someEnabled()
    return band(getMask(), Notification.SOURCE_SOME) == Notification.SOURCE_SOME
end

-- i.e., MORE - SOME
local SOURCE_MORE = band(Notification.SOURCE_MORE, bnot(Notification.SOURCE_SOME))
local function moreEnabled()
    return band(getMask(), SOURCE_MORE) == SOURCE_MORE
end

local function dispatcherEnabled()
    return band(getMask(), Notification.SOURCE_DISPATCHER) == Notification.SOURCE_DISPATCHER
end

-- i.e., ALL - DEFAULT
local SOURCE_MISC = band(Notification.SOURCE_ALL, bnot(Notification.SOURCE_DEFAULT))
local function miscEnabled()
    return band(getMask(), SOURCE_MISC) == SOURCE_MISC
end

--[[
local function allEnabled()
    return band(getMask(), Notification.SOURCE_ALL) == Notification.SOURCE_ALL
end
--]]

-- NOTE: Default is MORE + DISPATCHER
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
            checked_func = someEnabled,
            callback = function()
                if someEnabled() then
                    -- Can't have more without some, so disable more in full
                    setMask(
                        band(getMask(), bnot(Notification.SOURCE_MORE)))
                else
                    setMask(
                        bor(getMask(), Notification.SOURCE_SOME))
                end
            end,
        },
        {
            text = _("More notifications from bottom menu"),
            help_text = _("Show notification popups for more bottom menu settings."),
            checked_func = moreEnabled,
            callback = function()
                if moreEnabled() then
                    -- We *can* keep some without more, so only disable the diff between the two
                    setMask(
                        band(getMask(), bnot(SOURCE_MORE)))
                else
                    -- But do enable the full set
                    setMask(
                        bor(getMask(), Notification.SOURCE_MORE))
                end
            end,
        },
        {
            text = _("Notifications from miscellaneous sources"),
            help_text = _("Show notification popups for even more bottom menu settings, as well as standalone & misc notifications."),
            checked_func = miscEnabled,
            callback = function()
                if miscEnabled() then
                    setMask(
                        band(getMask(), bnot(SOURCE_MISC)))
                else
                    setMask(
                        bor(getMask(), SOURCE_MISC))
                end
            end,
        },
        {
            text = _("Notifications from gestures and profiles"),
            help_text = _("Show notification popups for changes from gestures and the profiles plugin."),
            checked_func = dispatcherEnabled,
            callback = function()
                if dispatcherEnabled() then
                    setMask(
                        band(getMask(), bnot(Notification.SOURCE_DISPATCHER)))
                else
                    setMask(
                        bor(getMask(), Notification.SOURCE_DISPATCHER))
                end
            end,
            separator = true,
        },
        --[[
        {
            text = _("Notifications from everything"),
            help_text = _("Show all notification popups, no matter the source. This will flip all of the above at once."),
            checked_func = allEnabled,
            radio = true,
            callback = function()
                if allEnabled() then
                    setMask(
                        band(getMask(), bnot(Notification.SOURCE_ALL)))
                else
                    setMask(
                        bor(getMask(), Notification.SOURCE_ALL))
                end
            end,
            separator = true,
        },
        --]]
        {
            text = _("Show past notifications"),
            callback = function()
                local content = require("ui/widget/notification"):getPastMessages()

                if not content or #content == 0 then
                    content = _("No notifications available.")
                else
                    content = table.concat(content, "\n")
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
    }
}
