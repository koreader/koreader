-- Start with the english keyboard layout
local vi_keyboard = dofile("frontend/ui/data/keyboardlayouts/en_keyboard.lua")

local IME = require("ui/data/keyboardlayouts/generic_ime")
local util = require("util")

-- see https://www.hieuthi.com/blog/2017/03/21/all-vietnamese-syllables.html
local code_map = dofile("frontend/ui/data/keyboardlayouts/vi_telex_data.lua")
local ime = IME:new{
    code_map = code_map,
    partial_separators = {},
    has_case = true,
    exact_match = true,
}

local wrappedAddChars = function(inputbox, char)
    local lowercase = char:lower()
    ime:wrappedAddChars(inputbox, lowercase, char)
end

local function separate(inputbox)
    ime:separate(inputbox)
end

local function wrappedDelChar(inputbox)
    ime:wrappedDelChar(inputbox)
end

local function clear_stack()
    ime:clear_stack()
end

local wrapInputBox = function(inputbox)
    if inputbox._vi_wrapped == nil then
        inputbox._vi_wrapped = true
        local wrappers = {}

        -- Wrap all of the navigation and non-single-character-input keys with
        -- a callback to finish (separate) the input status, but pass through to the
        -- original function.

        -- -- Delete text.
        table.insert(wrappers, util.wrapMethod(inputbox, "delChar",          wrappedDelChar,   nil))
        table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, clear_stack))
        table.insert(wrappers, util.wrapMethod(inputbox, "clear",            nil, clear_stack))
        -- -- Navigation.
        table.insert(wrappers, util.wrapMethod(inputbox, "leftChar",  nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "rightChar", nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "upLine",    nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "downLine",  nil, separate))
        -- -- Move to other input box.
        table.insert(wrappers, util.wrapMethod(inputbox, "unfocus",         nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onCloseKeyboard", nil, separate))
        -- -- Gestures to move cursor.
        table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox",    nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox",   nil, separate))
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox",  nil, separate))

        -- addChars is the only method we need a more complicated wrapper for.
        table.insert(wrappers, util.wrapMethod(inputbox, "addChars", wrappedAddChars, nil))

        return function()
            if inputbox._vi_wrapped then
                for _, wrapper in ipairs(wrappers) do
                    wrapper:revert()
                end
                inputbox._vi_wrapped = nil
            end
        end
    end
end

vi_keyboard.wrapInputBox = wrapInputBox
vi_keyboard.keys[5][4].label = "dấu cách"

return vi_keyboard
