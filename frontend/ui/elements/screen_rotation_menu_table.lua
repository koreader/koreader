local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local function genMenuItem(text, mode)
    return {
        text_func = function()
            return G_reader_settings:readSetting("fm_rotation_mode") == mode and text .. "   ★" or text
        end,
        checked_func = function()
            return Screen:getRotationMode() == mode
        end,
        radio = true,
        callback = function(touchmenu_instance)
            UIManager:broadcastEvent(Event:new("SetRotationMode", mode))
            touchmenu_instance:closeMenu()
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("fm_rotation_mode", mode)
            touchmenu_instance:updateItems()
        end,
    }
end

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
            table.insert(rotation_table, genMenuItem(C_("Rotation", "⤹ 90°"), Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE))
            table.insert(rotation_table, genMenuItem(C_("Rotation", "↑ 0°"), Screen.DEVICE_ROTATED_UPRIGHT))
            table.insert(rotation_table, genMenuItem(C_("Rotation", "⤸ 90°"), Screen.DEVICE_ROTATED_CLOCKWISE))
            table.insert(rotation_table, genMenuItem(C_("Rotation", "↓ 180°"), Screen.DEVICE_ROTATED_UPSIDE_DOWN))
        end

        rotation_table[#rotation_table].separator = true
        table.insert(rotation_table, {
            text = _("Image viewer rotation"),
            sub_item_table = {
                {
                    -- The default if unset, probably more practical for right handed users.
                    text = _("Rotate image \u{2938} when in portrait mode"),
                    radio = true,
                    checked_func = function()
                        return G_reader_settings:nilOrTrue("imageviewer_portrait_rotate_clockwise")
                    end,
                    callback = function()
                        G_reader_settings:makeTrue("imageviewer_portrait_rotate_clockwise")
                    end,
                },
                {
                    text = _("Rotate image \u{2939} when in portrait mode"),
                    radio = true,
                    checked_func = function()
                        return G_reader_settings:isFalse("imageviewer_portrait_rotate_clockwise")
                    end,
                    callback = function()
                        G_reader_settings:makeFalse("imageviewer_portrait_rotate_clockwise")
                    end,
                    separator = true,
                },
                {
                    text = _("Rotate image \u{2938} when in landscape mode"),
                    radio = true,
                    checked_func = function()
                        return G_reader_settings:isTrue("imageviewer_landscape_rotate_clockwise")
                    end,
                    callback = function()
                        G_reader_settings:makeTrue("imageviewer_landscape_rotate_clockwise")
                    end,
                },
                {
                    -- The default if unset, probably more practical for right handed users (if they prefer
                    -- to have the device's bottom in their right hand, this rotation will bring the image
                    -- bottom to the device's bottom).
                    text = _("Rotate image \u{2939} when in landscape mode"),
                    radio = true,
                    checked_func = function()
                        return G_reader_settings:nilOrFalse("imageviewer_landscape_rotate_clockwise")
                    end,
                    callback = function()
                        G_reader_settings:makeFalse("imageviewer_landscape_rotate_clockwise")
                    end,
                    separator = true,
                },
                {
                    text = _("Auto-rotate for best fit"),
                    help_text = _("Auto-rotate the image to best match screen and image aspect ratios on image viewer launch (ie. if in portrait mode, a landscape image will be rotated).");
                    checked_func = function()
                        return G_reader_settings:isTrue("imageviewer_rotate_auto_for_best_fit")
                    end,
                    callback = function()
                        G_reader_settings:flipTrue("imageviewer_rotate_auto_for_best_fit")
                    end,
                }
            }
        })
        return rotation_table
    end,
}
