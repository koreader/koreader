local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local ru_popup = require("ui/data/keyboardlayouts/keypopup/ru_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _Je_ = ru_popup._Je_
local _je_ = ru_popup._je_
local _Ye_ = ru_popup._Ye_
local _ye_ = ru_popup._ye_

-- the Russian soft/hard sign
local _SH_ = ru_popup._SH_
local _sh_ = ru_popup._sh_

-- Kazakh Cyrillic letters: ә і ң ғ ү ұ қ ө һ
local _KA_ = ru_popup._KA_
local _ka_ = ru_popup._ka_
local _KI_ = ru_popup._KI_
local _ki_ = ru_popup._ki_
local _KN_ = ru_popup._KN_
local _kn_ = ru_popup._kn_
local _KG_ = ru_popup._KG_
local _kg_ = ru_popup._kg_
local _KU_ = ru_popup._KU_
local _ku_ = ru_popup._ku_
local _KK_ = ru_popup._KK_
local _kk_ = ru_popup._kk_
local _KO_ = ru_popup._KO_
local _ko_ = ru_popup._ko_
local _KH_ = ru_popup._KH_
local _kh_ = ru_popup._kh_

-- Question mark, exclamation, quotes
local _qe_ = ru_popup._qe_


return {
    min_layer = 1,
    max_layer = 8,
    shiftmode_keys = {[""] = true, ["1/2"] = true, ["2/2"] = true},
    symbolmode_keys = {["123"] = true, ["АБВ"] = true, ["ещё"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["αβγ"] = true},
    keys = {
        -- first row
        {  --  1       2       3       4       5       6       7       8
            { "Й",    "й",    "'",    "`",    "∫",    "∂",    "∴",    "`", },
            { "Ц",    "ц",    "[",    "1",    "ς",    "ς",    "¹",    "1", },
            { _KU_,   _ku_,   "]",    "2",    "Ε",    "ε",    "²",    "2", },
            { _KK_,   _kk_,   "{",    "3",    "Ρ",    "ρ",    "³",    "3", },
            { _Ye_,   _ye_,   "}",    "4",    "Τ",    "τ",    "⁴",    "4", },
            { _KN_,   _kn_,   "#",    "5",    "Υ",    "υ",    "⁵",    "5", },
            { _KG_,   _kg_,   "%",    "6",    "Θ",    "θ",    "⁶",    "6", },
            { "Ш",    "ш",    "^",    "7",    "Ι",    "ι",    "⁷",    "7", },
            { "Щ",    "щ",    "*",    "8",    "Ο",    "ο",    "⁸",    "8", },
            { "З",    "з",    "+",    "9",    "Π",    "π",    "⁹",    "9", },
            { _KH_,   _kh_,   _eq,    "0",    "²",    "√",    "⁰",    "0", },
        },
        -- second row
        {  --  1       2       3       4       5       6       7       8
            { "Ф",    "ф",    "_",    "+",    "Α",    "α",    "„",    "«", },
            { _KI_,   _ki_,   "\\",   "-",    "Σ",    "σ",    "“",    "»", },
            { "В",    "в",    "_",    "/",    "Δ",    "δ",    "№",    "≤", },
            { _KA_,   _ka_,   "~",    ":",    "Φ",    "φ",    "†",    "≥", },
            { "П",    "п",    "<",    ";",    "Γ",    "γ",    "‡",    "≈", },
            { "Р",    "р",    ">",    "(",    "Η",    "η",    "©",    "≠", },
            { _KO_,   _ko_,   "€",    ")",    "Ξ",    "ξ",    "™",    "≡", },
            { "Л",    "л",    "£",    "$",    "Κ",    "κ",    "🄯",    "¶", },
            { "Д",    "д",    "¥",    "&",    "Λ",    "λ",    "®",    "§", },
            { _Je_,   _je_,   "₸",    _at,    "×",    "×",    "½",    "¤", },
            { "Э",    "э",    "¢",    "”",    "⋅",    "⋅",    "¼",    "‰", },
        },
        -- third row
        {  --  1       2       3       4       5       6       7       8
            { "",   "",   "2/2",  "1/2",   "",   "",   "",    "",
              width = 1.0
            },
            { "Я",    "я",    "–",    "–",    "Ζ",    "ζ",    "∪",    "±", },
            { "Ч",    "ч",    "—",    "—",    "Χ",    "χ",    "∩",    "º", },
            { "С",    "с",    com,    com,    "Ψ",    "ψ",    "∈",    "∞", },
            { "М",    "м",    prd,    prd,    "Ω",    "ω",    "∉",    "…", },
            { "И",    "и",    "?",    "?",    "Β",    "β",    "∅",    "¿", },
            { "Т",    "т",    "!",    "!",    "Ν",    "ν",    "∀",    "¡", },
            { _SH_,   _sh_,   "’",    "’",    "Μ",    "μ",    "∃",    "∝", },
            { "Б",    "б",    "↑",    "↑",    "≈",    "≈",    "↑",    "↑", },
            { "Ю",    "ю",    "|",    "|",    "∇",    "∇",    "|",    "|", },
            { label = "",
              width = 1.0,
              bold = false
            },
        },
        -- fourth row
        {  --  1       2       3       4       5       6       7       8
            { "123",  "123",  "АБВ",  "АБВ",  "ещё",  "ещё",  "ещё",  "ещё",
              width = 1.0},
            { label = "🌐", },
            { "αβγ",  "αβγ",  "αβγ",  "αβγ",  "αβγ",  "αβγ",  "αβγ",  "αβγ", },
            { label = "пробел",
              " ",        " ",    " ",    " ",   " ",    " ",    " ",    " ",
              width = 4.0},
            { _qe_,    _qe_,  "←",    "←",    _qe_,   _qe_,   "←",    "←", },
            { com,    com,    "↓",    "↓",    com,    com,    "↓",    "↓", }, -- arrow down
            { prd,    prd,    "→",    "→",    prd,    prd,    "→",    "→", },
            { label = "⮠",
              "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              width = 1.0,
              bold = true
            },
        },
    },
}
