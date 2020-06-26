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
                    if G_reader_settings:readSetting("fm_rotation_mode") == 3 then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == 3
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", 3))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", 3)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.PORTRAIT
                    if G_reader_settings:readSetting("fm_rotation_mode") == 0 then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == 0
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", 0))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", 0)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.LANDSCAPE
                    if G_reader_settings:readSetting("fm_rotation_mode") == 1 then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == 1
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", 1))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", 1)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = S.PORTRAIT_ROTATED
                    if G_reader_settings:readSetting("fm_rotation_mode") == 2 then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == 2
                end,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", 2))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", 2)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end

        return rotation_table
    end,
}
