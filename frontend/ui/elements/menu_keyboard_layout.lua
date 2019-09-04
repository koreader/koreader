local VirtualKeyboard = require("ui/widget/virtualkeyboard")

local sub_item_table = {}

for k, _ in pairs(VirtualKeyboard.lang_to_keyboard_layout) do
    table.insert(sub_item_table, {
        text = k,
        checked_func = function()
            return VirtualKeyboard:getKeyboardLayout() == k
        end,
        callback = function()
            G_reader_settings:saveSetting("keyboard_layout", k)
        end,
    })
end

return sub_item_table
