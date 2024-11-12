local Device = require("device")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
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
                    UIManager:broadcastEvent(Event:new("LockGSensor"))
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
            local optionsutil = require("ui/data/optionsutil")
            for i, mode in ipairs(optionsutil.rotation_modes) do
                table.insert(rotation_table, genMenuItem(optionsutil.rotation_labels[i], mode))
            end
        end

        rotation_table[#rotation_table].separator = true
        table.insert(rotation_table, {
            text = _("Image viewer rotation"),
            sub_item_table = {
                {
                    text = _("Invert default rotation in portrait mode"),
                    checked_func = function()
                        return G_reader_settings:isTrue("imageviewer_rotation_portrait_invert")
                    end,
                    callback = function()
                        G_reader_settings:flipNilOrFalse("imageviewer_rotation_portrait_invert")
                    end,
                },
                {
                    text = _("Invert default rotation in landscape mode"),
                    checked_func = function()
                        return G_reader_settings:isTrue("imageviewer_rotation_landscape_invert")
                    end,
                    callback = function()
                        G_reader_settings:flipNilOrFalse("imageviewer_rotation_landscape_invert")
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
