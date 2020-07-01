local _ = require("gettext")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local S = require("ui/data/strings")

return {
    text = _("Rotation"),
    sub_item_table_func = function()
        local rotation_table = {}

        if Device:canToggleGSensor() then
            table.insert(rotation_table, {
                text = _("Ignore accelerometer rotation events"),
                checked_func = function()
                    return G_reader_settings:isTrue("input_ignore_gsensor")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("input_ignore_gsensor")
                    Device:toggleGSensor(not G_reader_settings:isTrue("input_ignore_gsensor"))
                end,
            })
        end

        table.insert(rotation_table, {
            text = _("Keep file browser rotation"),
            help_text = _("When checked the rotation of the file browser and the reader will not affect each other"),
            checked_func = function()
                return G_reader_settings:isTrue("lock_rotation")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("lock_rotation")
            end,
            separator = true,
        })

        if FileManager.instance then
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.LANDSCAPE_ROTATED
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.ORIENTATION_LANDSCAPE_ROTATED then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.ORIENTATION_LANDSCAPE_ROTATED
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.ORIENTATION_LANDSCAPE_ROTATED))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.ORIENTATION_LANDSCAPE_ROTATED)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.PORTRAIT
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.ORIENTATION_PORTRAIT then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.ORIENTATION_PORTRAIT
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.ORIENTATION_PORTRAIT))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.ORIENTATION_PORTRAIT)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.LANDSCAPE
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.ORIENTATION_LANDSCAPE then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.ORIENTATION_LANDSCAPE
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.ORIENTATION_LANDSCAPE))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.ORIENTATION_LANDSCAPE)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.PORTRAIT_ROTATED
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.ORIENTATION_PORTRAIT_ROTATED then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.ORIENTATION_PORTRAIT_ROTATED
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.ORIENTATION_PORTRAIT_ROTATED))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.ORIENTATION_PORTRAIT_ROTATED)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end

        return rotation_table
    end,
}
