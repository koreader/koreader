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

local function isEnabled(source)
    return band(getMask(), source) == source
end

-- Helper function to avoid repeating boilerplate code, as we just flip a few bits one way or the other
local function genMenuItem(source, label, help, separator)
    return {
        text = label,
        help_text = help,
        checked_func = function() return isEnabled(source) end,
        callback = function()
            if isEnabled(source) then
                setMask(
                    band(getMask(), bnot(source)))
            else
                setMask(
                    bor(getMask(), source))
            end
        end,
        separator = separator,
    }
end

-- NOTE: Default is MORE + DISPATCHER; i.e., BOTTOM_MENU_FINE + BOTTOM_MENU_MORE + BOTTOM_MENU_PROGRESS + DISPATCHER
return {
    text = _("Notifications"),
    help_text = _([[Notification popups may be shown at the top of screen on various occasions.
This allows selecting which to show or hide.]]),
    checked_func = function()
        local value = G_reader_settings:readSetting("notification_sources_to_show_mask") or Notification.SOURCE_DEFAULT
        return  value ~= 0
    end,
    sub_item_table = {
        genMenuItem(Notification.SOURCE_BOTTOM_MENU_ICON, _("From bottom menu icons")),
        genMenuItem(Notification.SOURCE_BOTTOM_MENU_TOGGLE, _("From bottom menu toggles")),
        genMenuItem(Notification.SOURCE_BOTTOM_MENU_FINE, _("From bottom menu ± buttons")), -- Poor man's +/- w/ \u{207a}\u{2044}\u{208b} doesn't look too great because subscript minus sits on the baseline in most fonts...
        genMenuItem(Notification.SOURCE_BOTTOM_MENU_MORE, _("From bottom menu ⋮ buttons")),
        genMenuItem(Notification.SOURCE_BOTTOM_MENU_PROGRESS, _("From bottom menu progress bars")),
        genMenuItem(Notification.SOURCE_DISPATCHER, _("From gestures and profiles")),
        genMenuItem(Notification.SOURCE_OTHER, _("From all other sources"), nil, true),
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
