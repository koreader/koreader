local Language = require("ui/language")
local VirtualKeyboard = require("ui/widget/virtualkeyboard")
local orderedPairs = require("ffi/util").orderedPairs

local sub_item_table = {}

for k, _ in orderedPairs(VirtualKeyboard.lang_to_keyboard_locale) do
    table.insert(sub_item_table, {
        text = Language:getLanguageName(k),
        checked_func = function()
            return VirtualKeyboard:getKeyboardLocale() == k
        end,
        callback = function()
            G_reader_settings:saveSetting("keyboard_layout", k)
        end,
    })
end

return sub_item_table
