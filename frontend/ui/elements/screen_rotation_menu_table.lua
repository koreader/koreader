local _ = require("gettext")
local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
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
        text = _("Lock rotation"),
        help_text = _("When checked the rotation of the filemanager and reader will not affect each other"),
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
            text = S.PORTRAIT,
            checked_func = function()
                return G_reader_settings:readSetting("fm_rotation_mode") == 0
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("SetRotationMode", 0))
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("fm_rotation_mode", 0)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
        table.insert(rotation_table, {
            text = S.LANDSCAPE,
            checked_func = function()
                return G_reader_settings:readSetting("fm_rotation_mode") == 1
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("SetRotationMode", 1))
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("fm_rotation_mode", 1)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
        table.insert(rotation_table, {
            text = S.PORTRAIT_ROTATED,
            checked_func = function()
                return G_reader_settings:readSetting("fm_rotation_mode") == 2
            end,
            callback = function()
                UIManager:broadcastEvent(Event:new("SetRotationMode", 2))
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("fm_rotation_mode", 2)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
        table.insert(rotation_table, {
            text = S.LANDSCAPE_ROTATED,
            checked_func = function()
                return G_reader_settings:readSetting("fm_rotation_mode") == 3
            end,
            callback = function(touchmenu_instance)
--require("logger").warn("@@@@@@@@@@@@@", touchmenu_instance)
                UIManager:broadcastEvent(Event:new("SetRotationMode", 3))
            end,
            hold_callback = function(touchmenu_instance)
                G_reader_settings:saveSetting("fm_rotation_mode", 3)
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    return rotation_table
    end,
}
