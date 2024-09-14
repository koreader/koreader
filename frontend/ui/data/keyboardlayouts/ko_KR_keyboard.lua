local logger = require("logger")

--------
-- # Korean 2-beolsik Keyboard layout
--------

local HgHelper = require("ui/data/keyboardlayouts/ko_KR_helper")

--------
-- UI handler implementation for communicating with text input box widget
--------
function HgHelper.UIHandler:put_char(char)
    HgHelper.UIHandler.inputbox:_addChars(char)
end
function HgHelper.UIHandler:del_char(char)
    HgHelper.UIHandler.inputbox:_delChar()
end
HgHelper.HgFSM:init(HgHelper.UIHandler)

--------
-- Custom key event handlers with Hangul support
--------
local wrapInputBox = function(inputbox)
    HgHelper.HgFSM.clean_state() -- reset helper

    if inputbox._wrapped == nil then
        inputbox._wrapped = true

        -- helper functions
        local copied_names = {}
        local function restore_func_references(obj)
            for __, name in ipairs(copied_names) do
                local orig_name = "_" .. name
                if obj[orig_name] then
                    obj[name] = obj[orig_name]
                    obj[orig_name] = nil
                end
            end
        end

        local function copy_func_reference(obj, name)
            obj["_" .. name] = obj[name]
            table.insert(copied_names, name)
        end

        -- override original implementations with helper object
        copy_func_reference(inputbox, "addChars")
        copy_func_reference(inputbox, "delChar")

        function inputbox:addChars(key)
            logger.dbg("ko_KR_kbd:addChar(", key, ")")
            HgHelper.UIHandler.inputbox = self
            HgHelper.HgFSM:process_char(key)
        end
        function inputbox:delChar()
            logger.dbg("ko_KR_kbd:delChar()")
            HgHelper.UIHandler.inputbox = self
            HgHelper.HgFSM:process_bsp()
        end

        -- override implementations: reset helper if we have to stop combining current syllable
        ---- helper function
        local function wrap_func_with_hghelper_reset(obj, name)
            copy_func_reference(obj, name)
            obj[name] = function(self)
                HgHelper.HgFSM.clean_state()
                self["_" .. name](self)
            end
        end

       ---- delete text
        wrap_func_with_hghelper_reset(inputbox, "delToStartOfLine")
        wrap_func_with_hghelper_reset(inputbox, "clear")

        ---- move cursor
        wrap_func_with_hghelper_reset(inputbox, "leftChar")
        wrap_func_with_hghelper_reset(inputbox, "rightChar")
        wrap_func_with_hghelper_reset(inputbox, "upLine")
        wrap_func_with_hghelper_reset(inputbox, "downLine")

        ---- unfocus: move to other inputbox
        wrap_func_with_hghelper_reset(inputbox, "unfocus")

        ---- tap/hold/swipe: move cursor
        ------ helper function
        local function wrap_touch_event_func_with_hghelper_reset(obj, name)
            copy_func_reference(obj, name)
            obj[name] = function(self, arg, ges)
                HgHelper.HgFSM.clean_state()
                return self["_" .. name](self, arg, ges)
            end
        end

        wrap_touch_event_func_with_hghelper_reset(inputbox, "onTapTextBox")
        wrap_touch_event_func_with_hghelper_reset(inputbox, "onHoldTextBox")
        wrap_touch_event_func_with_hghelper_reset(inputbox, "onSwipeTextBox")

        return function() -- return unwrap function
            restore_func_references(inputbox)
            inputbox._wrapped = nil
        end
    end
end

-- Belows are just same as the English keyboard popup
local en_popup = dofile("frontend/ui/data/keyboardlayouts/keypopup/en_popup.lua")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)

return {
    min_layer = 1,
    max_layer = 4,
    shiftmode_keys = {[""] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = false},  -- Disabled 'umlaut' keys
    keys = {
        -- [shift, unshift, symbol-shift, symbol-unshift]
        -- first row
        {  --  1       2       3       4
            { "ㅃ",    "ㅂ",   "￦",    "0", },
            { "ㅉ",    "ㅈ",    "!",    "1", },
            { "ㄸ",    "ㄷ",    _at,    "2", },
            { "ㄲ",    "ㄱ",    "#",    "3", },
            { "ㅆ",    "ㅅ",    "+",    _eq, },
            { "ㅛ",    "ㅛ",    "☆",    "(", },
            { "ㅕ",    "ㅕ",    "★",    ")", },
            { "ㅑ",    "ㅑ",    "♡",   "\\", },
            { "ㅒ",    "ㅐ",    "♥",    "/", },
            { "ㅖ",    "ㅔ",    "※",    "`", },
        },
        -- second row
        {  --  1       2       3       4
            { "ㅁ",    "ㅁ",    "…",    "@", },
            { "ㄴ",    "ㄴ",    "$",    "4", },
            { "ㅇ",    "ㅇ",    "%",    "5", },
            { "ㄹ",    "ㄹ",    "^",    "6", },
            { "ㅎ",    "ㅎ",    ":",    "'", },
            { "ㅗ",    "ㅗ",    "♩",   "\"", },
            { "ㅓ",    "ㅓ",    "♪",    "[", },
            { "ㅏ",    "ㅏ",    "♬",    "]", },
            { "ㅣ",    "ㅣ",    "™",    "-", },
        },
        -- third row
        {  --  1           2       3       4
            { label = "",
              width = 1.5
            },
            { "ㅋ",    "ㅋ",    "「",    "7", },
            { "ㅌ",    "ㅌ",    "」",    "8", },
            { "ㅊ",    "ㅊ",    "*",    "9", },
            { "ㅍ",    "ㅍ",    "❤",    com, },
            { "ㅠ",    "ㅠ",    "&",    prd, },
            { "ㅜ",    "ㅜ",    "『",    "↑", },
            { "ㅡ",    "ㅡ",    "』",    "↓", },
            { label = "",
              width = 1.5,
              bold = false
            },
        },
        -- fourth row
        {
            { "Sym",  "Sym",  "ABC",  "ABC",
              width = 1.5},
            { label = "🌐",
              width = 2,
            },
            -- { "Äéß",  "Äéß",  "Äéß",  "Äéß",},
            { label = "간격",
              " ",    " ",    " ",    " ",
              width = 3.0},
            { com,    com,    "“",    "←", },
            { prd,    prd,    "”",    "→", },
            { label = "⮠",
              "\n",    "\n",   "\n",   "\n",
              width = 1.5,
              bold = true
            },
        },
    },

    -- wrap InputBox for hooking events to the helper
    wrapInputBox = wrapInputBox,
}
