--------
-- Japanese 12-key flick keyboard layout, modelled after Android's flick
-- keyboard. Rather than being modal, it has the ability to apply modifiers to
-- the previous character. In addition, users can tap a kana key to cycle
-- through the various kana in that kana row (and associated small kana).
--
-- Note that because we cannot have tri-state buttons (and we want to be able
-- to input katakana) we emulate a quad-state button using the symbol and shift
-- layers. Users just have to tap whatever mode they want and they should be
-- able to get there easily.
--------

local logger = require("logger")
local util = require("util")
local time = require("ui/time")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = require("ffi/util").template

local K = dofile("frontend/ui/data/keyboardlayouts/ja_keyboard_keys.lua")

local DEFAULT_KEITAI_TAP_INTERVAL_S = 2

-- "Keitai input" is an input mode similar to T9 mobile input, where you tap a
-- key to cycle through several candidate characters. The tap interval is how
-- long we are going to wait before committing to the current character. See
-- <https://en.wikipedia.org/wiki/Japanese_input_method#Mobile_phones> for more
-- information.

local function getKeitaiTapInterval()
    return time.s(G_reader_settings:readSetting("keyboard_japanese_keitai_tap_interval", DEFAULT_KEITAI_TAP_INTERVAL_S))
end

local function setKeitaiTapInterval(interval)
    G_reader_settings:saveSetting("keyboard_japanese_keitai_tap_interval", time.to_s(interval))
end

local function exitKeitaiMode(inputbox)
    logger.dbg("ja_kbd: clearing keitai window last tap tv")
    inputbox._ja_last_tap_time = nil
end

local function wrappedAddChars(inputbox, char)
    -- Find the relevant modifier cycle tables.
    local modifier_table = K.MODIFIER_TABLE[char]
    local keitai_cycle = K.KEITAI_TABLE[char]

    -- For keitai buttons, are we still in the tap interval?
    local within_tap_window
    if keitai_cycle then
        if inputbox._ja_last_tap_time then
            within_tap_window = time.since(inputbox._ja_last_tap_time) < getKeitaiTapInterval()
        end
        inputbox._ja_last_tap_time = time.now()
    else
        -- This is a non-keitai or non-tap key, so break out of keitai window.
        exitKeitaiMode(inputbox)
    end

    -- Get the character behind the cursor and figure out how to modify it.
    local new_char
    local current_char = inputbox:getChar(-1)
    if modifier_table then
        new_char = modifier_table[current_char]
    elseif keitai_cycle and keitai_cycle[current_char] and within_tap_window then
        new_char = keitai_cycle[current_char]
    else
        -- Regular key, just add it as normal.
        inputbox.addChars:raw_method_call(char)
        return
    end

    -- Replace character if there was a valid replacement.
    logger.dbg("ja_kbd: applying", char, "key to", current_char, "yielded", new_char)
    if not current_char then return end -- no character to modify
    if new_char then
        -- Use the raw methods to avoid calling the callbacks.
        inputbox.delChar:raw_method_call()
        inputbox.addChars:raw_method_call(new_char)
    end
end

local function wrapInputBox(inputbox)
    if inputbox._ja_wrapped == nil then
        inputbox._ja_wrapped = true
        local wrappers = {}

        -- Wrap all of the navigation and non-single-character-input keys with
        -- a callback to clear the tap window, but pass through to the
        -- original function.

        -- Delete text.
        table.insert(wrappers, util.wrapMethod(inputbox, "delChar",          nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "delToStartOfLine", nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "clear",            nil, exitKeitaiMode))
        -- Navigation.
        table.insert(wrappers, util.wrapMethod(inputbox, "leftChar",  nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "rightChar", nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "upLine",    nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "downLine",  nil, exitKeitaiMode))
        -- Move to other input box.
        table.insert(wrappers, util.wrapMethod(inputbox, "unfocus", nil, exitKeitaiMode))
        -- Gestures to move cursor.
        table.insert(wrappers, util.wrapMethod(inputbox, "onTapTextBox",   nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "onHoldTextBox",  nil, exitKeitaiMode))
        table.insert(wrappers, util.wrapMethod(inputbox, "onSwipeTextBox", nil, exitKeitaiMode))

        -- addChars is the only method we need a more complicated wrapper for.
        table.insert(wrappers, util.wrapMethod(inputbox, "addChars", wrappedAddChars, nil))

        return function()
            if inputbox._ja_wrapped then
                for _, wrapper in ipairs(wrappers) do
                    wrapper:revert()
                end
                inputbox._ja_last_tap_time = nil
                inputbox._ja_wrapped = nil
            end
        end
    end
end

local function genMenuItems(self)
    return {
        {
            text_func = function()
                local interval = getKeitaiTapInterval()
                if interval ~= 0 then
                    -- @translators Keitai input is a kind of Japanese keyboard input mode (similar to T9 keypad input). See <https://en.wikipedia.org/wiki/Japanese_input_method#Mobile_phones> for more information.
                    return T(N_("Keitai tap interval: %1 second", "Keitai tap interval: %1 seconds", time.to_s(interval)), time.to_s(interval))
                else
                    -- @translators Flick and keitai are kinds of Japanese keyboard input modes. See <https://en.wikipedia.org/wiki/Japanese_input_method#Mobile_phones> for more information.
                    return _("Keitai input: disabled (flick-only input)")
                end
            end,
            help_text = _("How long to wait for the next tap when in keitai input mode before committing to the current character. During this window, tapping a single key will loop through candidates for the current character being input. Any other input will cause you to leave keitai mode."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local SpinWidget = require("ui/widget/spinwidget")
                local UIManager = require("ui/uimanager")
                local Screen = require("device").screen
                local items = SpinWidget:new{
                    title_text = _("Keitai tap interval"),
                    info_text = _([[
How long to wait (in seconds) for the next tap when in keitai input mode before committing to the current character. During this window, tapping a single key will loop through candidates for the current character being input. Any other input will cause you to leave keitai mode.

If set to 0, keitai input is disabled entirely and only flick input can be used.]]),
                    width = math.floor(Screen:getWidth() * 0.75),
                    value = time.to_s(getKeitaiTapInterval()),
                    value_min = 0,
                    value_max = 10,
                    value_step = 1,
                    unit = C_("Time", "s"),
                    ok_text = _("Set interval"),
                    default_value = DEFAULT_KEITAI_TAP_INTERVAL_S,
                    callback = function(spin)
                        setKeitaiTapInterval(time.s(spin.value))
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                }
                UIManager:show(items)
            end,
        },
    }
end

-- Basic modifier keys.
local M_l = { label = "←", } -- Arrow left
local M_r = { label = "→", } -- Arrow right
local Msw = { label = "🌐", } -- Switch keyboard
local Mbk = { label = "", bold = false, } -- Backspace

-- Modifier key for kana input.
local Mmd = { label = "◌゙ ◌゚", alt_label = "大⇔小",
              K.MODIFIER_KEY_CYCLIC,
              west = K.MODIFIER_KEY_DAKUTEN,
              north = K.MODIFIER_KEY_SMALLKANA,
              east = K.MODIFIER_KEY_HANDAKUTEN, }
-- Modifier key for latin input.
local Msh = { label = "a⇔A",
              K.MODIFIER_KEY_SHIFT }

-- In order to emulate the tri-modal system of 12-key keyboards we treat shift
-- and symbol modes as being used to specify which of the three target layers
-- to use. The four modes are hiragana (default), katakana (shift), English
-- letters (symbol), numbers and symbols (shift+symbol).
--
-- In order to make it easy for users to know which button will take them to a
-- specific mode, we need to give different keys the same name at certain
-- times, so we append a \0 to one set so that the VirtualKeyboard can
-- differentiate them on key tap even though they look the same to the user.

-- Shift-mode toggle button.
local Sh_abc = { label = "ABC\0", alt_label = "ひらがな", bold = true, }
local Sh_sym = { label = "記号\0", bold = true, } -- Switch to numbers and symbols.
local Sh_hir = { label = "ひらがな\0", bold = true, } -- Switch to hiragana.
local Sh_kat = { label = "カタカナ\0", bold = true, } -- Switch to katakana.
-- Symbol-mode toggle button.
local Sy_abc = { label = "ABC", alt_label = "記号", bold = true, }
local Sy_sym = { label = "記号", bold = true, } -- Switch to numbers and symbols.
local Sy_hir = { label = "ひらがな", bold = true, } -- Switch to hiragana.
local Sy_kat = { label = "カタカナ", bold = true, } -- Switch to katakana.

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = {["ABC\0"] = true, ["記号\0"] = true, ["カタカナ\0"] = true, ["ひらがな\0"] = true},
    symbolmode_keys = {["ABC"] = true, ["記号"] = true, ["ひらがな"] = true,  ["カタカナ"] = true},
    utf8mode_keys = {["🌐"] = true},
    keys = {
        -- first row [🌐, あ, か, さ, <bksp>]
        {  -- R         r         S         s
            Msw,
            { K.k_a,    K.h_a,    K.s_1,    K.l_1, },
            { K.kKa,    K.hKa,    K.s_2,    K.l_2, },
            { K.kSa,    K.hSa,    K.s_3,    K.l_3, },
            Mbk,
        },
        -- second row [←, た, な, は, →]
        {  -- R         r         S         s
            M_l,
            { K.kTa,    K.hTa,    K.s_4,    K.l_4, },
            { K.kNa,    K.hNa,    K.s_5,    K.l_5, },
            { K.kHa,    K.hHa,    K.s_6,    K.l_6, },
            M_r,
        },
        -- third row [<shift>, ま, や, ら, < >]
        {  -- R         r         S         s
            { Sh_hir,   Sh_kat,   Sh_abc,   Sh_sym, }, -- Shift
            { K.kMa,    K.hMa,    K.s_7,    K.l_7, },
            { K.kYa,    K.hYa,    K.s_8,    K.l_8, },
            { K.kRa,    K.hRa,    K.s_9,    K.l_9, },
            { label = "␣",
              "　",     "　",     " ",      " ",} -- whitespace
        },
        -- fourth row [symbol, modifier, わ, 。, enter]
        {  -- R         r         S         s
            { Sy_sym,   Sy_abc,   Sy_kat,   Sy_hir, }, -- Symbols
            { Mmd,      Mmd,      K.s_b,    Msh, },
            { K.kWa,    K.hWa,    K.s_0,    K.l_0, },
            { K.k_P,    K.h_P,    K.s_p,    K.l_P, },
            { label = "⮠", bold = true,
              "\n",     "\n",     "\n",     "\n",}, -- newline
        },
    },

    -- Methods.
    wrapInputBox = wrapInputBox,
    genMenuItems = genMenuItems,
}
