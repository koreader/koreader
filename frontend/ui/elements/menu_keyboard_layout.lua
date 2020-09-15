local FFIUtil = require("ffi/util")
local Language = require("ui/language")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")

local sub_item_table = {}

for k, _ in FFIUtil.orderedPairs(VirtualKeyboard.lang_to_keyboard_layout) do
    table.insert(sub_item_table, {
        text_func = function()
            local text = Language:getLanguageName(k)
            if VirtualKeyboard:getKeyboardLayout() == k then
                text = text .. "   ★"
            end
            return text
        end,
        checked_func = function()
            local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
            return keyboard_layouts[k] == true
        end,
        callback = function()
            local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
            keyboard_layouts[k] = not keyboard_layouts[k]
            G_reader_settings:saveSetting("keyboard_layouts", keyboard_layouts)
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:saveSetting("keyboard_layout", k)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

return sub_item_table
