local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

return {
    text = _("Rotation"),
    sub_item_table_func = function()
        local rotation_table = {}

        if Device:hasGSensor() then
            table.insert(rotation_table, {
                text = _("Ignore accelerometer rotation events"),
                help_text = _("This will inhibit automatic rotations triggered by your device's gyro."),
                checked_func = function()
                    return G_reader_settings:isTrue("input_ignore_gsensor")
                end,
                callback = function()
                    UIManager:broadcastEvent(Event:new("ToggleGSensor"))
                end,
            })
        end

        if Device:hasGSensor() then
            table.insert(rotation_table, {
                text = _("Lock auto rotation to current orientation"),
                help_text = _([[
When checked, the gyro will only be honored when switching between the two inverse variants of your current rotation,
i.e., Portrait <-> Inverted Portrait OR Landscape <-> Inverted Landscape.
Switching between (Inverted) Portrait and (Inverted) Landscape will be inhibited.
If you need to do so, you'll have to use the UI toggles.]]),
                enabled_func = function()
                    return G_reader_settings:nilOrFalse("input_ignore_gsensor")
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("input_lock_gsensor")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("input_lock_gsensor")
                    Device:lockGSensor(G_reader_settings:isTrue("input_lock_gsensor"))
                end,
            })
        end

        table.insert(rotation_table, {
            text = _("Keep current rotation across views"),
            help_text = _([[
When checked, the current rotation will be kept when switching between the file browser and the reader, in both directions, and that no matter what the document's saved rotation or the default reader or file browser rotation may be.
This means that nothing will ever sneak a rotation behind your back, you choose your device's rotation, and it stays that way.
When unchecked, the default rotation of the file browser and the default/saved reader rotation will not affect each other (i.e., they will be honored), and may very well be different.]]),
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
                    local text = C_("Rotation", "⤹ 90°")
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
                end,
                radio = true,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = C_("Rotation", "↑ 0°")
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.DEVICE_ROTATED_UPRIGHT then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPRIGHT
                end,
                radio = true,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPRIGHT))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.DEVICE_ROTATED_UPRIGHT)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = C_("Rotation", "⤸ 90°")
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.DEVICE_ROTATED_CLOCKWISE then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.DEVICE_ROTATED_CLOCKWISE
                end,
                radio = true,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_CLOCKWISE))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.DEVICE_ROTATED_CLOCKWISE)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
            table.insert(rotation_table, {
                text_func = function()
                    local text = C_("Rotation", "↓ 180°")
                    if G_reader_settings:readSetting("fm_rotation_mode") == Screen.DEVICE_ROTATED_UPSIDE_DOWN then
                        text = text .. "   ★"
                    end
                    return text
                end,
                checked_func = function()
                    return Screen:getRotationMode() == Screen.DEVICE_ROTATED_UPSIDE_DOWN
                end,
                radio = true,
                callback = function(touchmenu_instance)
                    UIManager:broadcastEvent(Event:new("SetRotationMode", Screen.DEVICE_ROTATED_UPSIDE_DOWN))
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                end,
                hold_callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("fm_rotation_mode", Screen.DEVICE_ROTATED_UPSIDE_DOWN)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end

        return rotation_table
    end,
}
