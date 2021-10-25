--------
-- Japanese 12-key flick keyboard layout, modelled after Android's flick
-- keyboard. Rather than being modal, it has the ability to apply modifiers to
-- the previous character.
--------

-- Hiragana swipe keys (swipe directions correspond to columns, with
-- non-swipe corresponding to the あ-column). The や and わ rows have
-- symbols in the missing spots in the 五十音 grid (and the わ row is
-- organised slightly strangely), to match Android.
local h_a = { "あ", west = "い", north = "う", east = "え", south = "お" }
local hKa = { "か", west = "き", north = "く", east = "け", south = "こ" }
local hSa = { "さ", west = "し", north = "す", east = "せ", south = "そ" }
local hTa = { "た", west = "ち", north = "つ", east = "て", south = "と" }
local hNa = { "な", west = "に", north = "ぬ", east = "ね", south = "の" }
local hHa = { "は", west = "ひ", north = "ふ", east = "へ", south = "ほ" }
local hMa = { "ま", west = "み", north = "む", east = "め", south = "も" }
local hYa = { alt_label = "（）",
              "や", west = "(",  north = "ゆ", east = ")",  south = "よ" }
local hRa = { "ら", west = "り", north = "る", east = "れ", south = "ろ" }
local hWa = { alt_label = "ー〜",
              "わ", west = "を", north = "ん", east = "ー", south = "〜" }
local h_P = { alt_label = "。！？…",
              "、", west = "。", north = "？", east = "！", south = "…"  } -- punctuation button

-- Same as above but for katakana characters (shift mode). Most swipe
-- keyboards do not have a shift mode (because the IME is clever enough to
-- suggest katakana versions of the typed text) but we have to have them
-- explicitly.
local k_a = { "ア", west = "イ", north = "ウ", east = "エ", south = "オ" }
local kKa = { "カ", west = "キ", north = "ク", east = "ケ", south = "コ" }
local kSa = { "サ", west = "シ", north = "ス", east = "セ", south = "ソ" }
local kTa = { "タ", west = "チ", north = "ツ", east = "テ", south = "ト" }
local kNa = { "ナ", west = "ニ", north = "ヌ", east = "ネ", south = "ノ" }
local kHa = { "ハ", west = "ヒ", north = "フ", east = "ヘ", south = "ホ" }
local kMa = { "マ", west = "ミ", north = "ム", east = "メ", south = "モ" }
local kYa = { "ヤ", west = "（", north = "ユ", east = "）", south = "ヨ" }
local kRa = { "ラ", west = "リ", north = "ル", east = "レ", south = "ロ" }
local kWa = { "ワ", west = "ヲ", north = "ン", east = "-",  south = "~"  }
local k_P = { ",",  west = ".",  north = "?",  east = "!"                } -- punctuation button

-- Latin alphabet keys (arranged similar to T9).
local l_1 = { label = "@-_/", alt_label = "１",
              "@", west = "-", north = "_", east = "/", south = "１" }
local l_2 = { label = "abc", alt_label = "２",
              "a", west = "b", north = "c",             south = "２" }
local l_3 = { label = "def", alt_label = "３",
              "d", west = "e", north = "f",             south = "３" }
local l_4 = { label = "ghi", alt_label = "４",
              "g", west = "h", north = "i",             south = "４" }
local l_5 = { label = "jkl", alt_label = "５",
              "j", west = "k", north = "l",             south = "５" }
local l_6 = { label = "mno", alt_label = "６",
              "m", west = "n", north = "o",             south = "６" }
local l_7 = { label = "pqrs", alt_label = "７",
              "p", west = "q", north = "r", east = "s", south = "７" }
local l_8 = { label = "tuv", alt_label = "８",
              "t", west = "u", north = "v",             south = "８" }
local l_9 = { label = "wxyz", alt_label = "９",
              "w", west = "x", north = "y", east = "z", south = "９" }
local l_0 = { label = "'\":;", alt_label = "０",
              "'", west = '"', north = ":", east = ";", south = "０" }
local l_S = { label = ".,?!",
              ".", west = ",", north = "?", east = "!",              }

-- Keypad and symbols.
local s_1 = { alt_label = "☆♪",
             --- @todo We cannot output → because it's used internally.
              "1", west = "☆", north = "♪",--[[ east = "→",]] }
local s_2 = { alt_label = "¥$€",
              "2", west = "¥", north = "$", east = "€", }
local s_3 = { alt_label = "%゜#",
              "3", west = "%", north = "゜", east = "#", }
local s_4 = { alt_label = "○*・",
              "4", west = "○", north = "*", east = "・", }
local s_5 = { alt_label = "+×÷",
              "5", west = "+", north = "×", east = "÷", }
local s_6 = { alt_label = "<=>",
              "6", west = "<", north = "=", east = ">", }
local s_7 = { alt_label = "「」:",
              "7", west = "「", north = "」", east = ":", }
local s_8 = { alt_label = "〒々〆",
              "8", west = "〒", north = "々", east = "〆", }
local s_9 = { alt_label = "^|\\",
              "9", west = "^", north = "|", east = "\\", }
local s_0 = { alt_label = "~…@",
              "0", west = "~", north = "…", east = "@", }
local s_b = { label = "()[]",
              "(", west = ")", north = "[", east = "]", }
local s_p = { label = ".,-/",
              ".", west = ",", north = "-", east = "/", }


local M_l = { label = "←", } -- Arrow left
local M_r = { label = "→", } -- Arrow right
local Msw = { label = "🌐", } -- Switch keyboard
local Mbk = { label = "", bold = false, } -- Backspace

local JaModifiers = require("ui/data/keyboardlayouts/ja_keyboard_modifiers")

local logger = require("logger")

local function wrappedAddChars(inputbox, char)
    local modifier_table = JaModifiers.MODIFIER_TABLE[char]
    if not modifier_table then
        -- Regular key, just add it as normal.
        inputbox:_addChars(char)
        return
    end
    -- Skip if there are no characters.
    if #inputbox.charlist == 0 then return end
    -- Get the previous character to apply the modifier.
    local current_char = inputbox.charlist[inputbox.charpos-1]
    local new_char = modifier_table[current_char]
    if new_char then
        inputbox:delChar()
        inputbox:_addChars(new_char)
    end
end

local function wrapInputBox(inputbox)
    if inputbox._wrapped == nil then
        inputbox._wrapped = true
        -- We only need to wrap addChars in order to support our modifiers.
        inputbox._addChars = inputbox.addChars
        inputbox.addChars = wrappedAddChars
        return function()
            inputbox.addChars = inputbox._addChars
            inputbox._wrapped = nil
        end
    end
end

-- Modifier key for kana input.
local Mmd = { label = "◌゙ ◌゚", alt_label = "大小",
              JaModifiers.MODIFIER_CYCLIC,
              west = JaModifiers.MODIFIER_DAKUTEN,
              east = JaModifiers.MODIFIER_HANDAKUTEN, }
-- Modifier key for latin input.
local Msh = { label = "大小",
              JaModifiers.MODIFIER_SHIFT }

-- Shift keys and labels.
local Sh_abc = { label = "ABC\0", alt_label = "ひらがな", bold = true, }
local Sh_sym = { label = "記号\0", bold = true, }
local Sh_hir = { label = "ひらがな\0", bold = true, }
local Sh_kat = { label = "カタカナ\0", bold = true, }

local Sy_abc = { label = "ABC", alt_label = "記号", bold = true, }
local Sy_sym = { label = "記号", bold = true, }
local Sy_hir = { label = "ひらがな", bold = true, }
local Sy_kat = { label = "カタカナ", bold = true, }

return {
    min_layer = 1,
    max_layer = 4,
    wrapInputBox = wrapInputBox,
    -- In order to emulate the tri-modal system of 12-key keyboards we treat
    -- shift and symbol modes as being used to specify which of the three
    -- target layers to.
    --
    -- As such we need to give different keys the same name at certain times,
    -- so we append a \0 to one set so that the VirtualKeyboard can
    -- differentiate them even though they look the same to the user.
    shiftmode_keys = {["ABC\0"] = true, ["記号\0"] = true, ["カタカナ\0"] = true, ["ひらがな\0"] = true},
    symbolmode_keys = {["ABC"] = true, ["記号"] = true, ["ひらがな"] = true,  ["カタカナ"] = true},
    utf8mode_keys = {["🌐"] = true},
    keys = {
        -- first row [<>, あ, か, さ, <bksp>]
        {  --  R      r       S       s
            Msw,
            { k_a,    h_a,    s_1,    l_1, },
            { kKa,    hKa,    s_2,    l_2, },
            { kSa,    hSa,    s_3,    l_3, },
            Mbk,
        },
        -- second row [←, た, な, は, →]
        {  --  R      r       S       s
            M_l,
            { kTa,    hTa,    s_4,    l_4, },
            { kNa,    hNa,    s_5,    l_5, },
            { kHa,    hHa,    s_6,    l_6, },
            M_r,
        },
        -- third row [shift, ま, や, ら, 空白]
        {  --  R      r       S       s
            --Msh,
            { Sh_hir, Sh_kat, Sh_abc, Sh_sym, }, -- Shift
            { kMa,    hMa,    s_7,    l_7, },
            { kYa,    hYa,    s_8,    l_8, },
            { kRa,    hRa,    s_9,    l_9, },
            { label = "␣",
              "　",   "　",   " ",    " ",} -- whitespace
        },
        -- fourth row [symbol, modifier, わ, 。, enter]
        {  --  R      r       S       s
            { Sy_sym, Sy_abc, Sy_kat, Sy_hir, }, -- Symbols
            { Mmd,    Mmd,    s_b,     Msh, },
            { kWa,    hWa,    s_0,     l_0, },
            { k_P,    h_P,    s_p,     l_S, },
            { label = "⮠", bold = true,
              "\n",   "\n",   "\n",   "\n",}, -- newline
        },
    },
}
