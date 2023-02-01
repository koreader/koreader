return {
    com = {
        ",",
        north = ";",
        alt_label = ";",
        northeast = "(",
        northwest = "¿",
        east = "„",
        west = "?",
    },
    prd = {
        ".",
        north = ":",
        alt_label = ":",
        northeast = ")",
        northwest = "¡",
        east = "…",
        west = "!",
    },
    _at = {
        "@",
        north = "Ⓒ",
        alt_label = "Ⓒ",
        northeast = "™",
        northwest = "Ⓡ",
    },
    _eq = {
        "=",
        north = "_",
        alt_label = "_",
        northwest = "-",
        west = "≈",
        south = "≥",
        southwest = "≤",
    },
    pco = { -- period + colon
        ".",
        east = ",",
        alt_label = ",",
        west = ":",
        south = "|",
        southeast = "\\",
        southwest = "/",
    },
    cop = { -- colon + period
        ",",
        east = ".",
        alt_label = ".",
        west = ":",
        south = "|",
        southeast = "\\",
        southwest = "/",
    },
    quo = {
        '"',
        north = "'",
        alt_label = "'",
        northeast = "»",
        northwest = "«",
        east = "”",
        west = "“",
        south = "`",
        southeast = "’",
        southwest = "‘",
        "‹",
        "›",
    },
    cse = { -- comma + semicolon
        ",",
        north = ";",
        alt_label = ";",
        northeast = "}",
        northwest = "{",
        east = { label = "!…", key = "!important;" },
        west = "-",
        south = "*",
        southwest = "0",
        southeast = ">",
        "[",
        "+",
        "]",
    },
    sec = { -- semicolon + comma
        ";",
        north = ",",
        alt_label = ",",
        northeast = "}",
        northwest = "{",
        east = { label = "!…", key = "!important;" },
        west = "-",
        south = "*",
        southwest = "0",
        southeast = ">",
        "[",
        "*",
        "]",
    },
    Apo = {"'", north = "ʼ", alt_label = "ʼ"}, -- apostrophe
    apo = {"ʼ", north = "'", alt_label = "'"}, -- apostrophe
    _A_ = {"А", north = "а", },
    _a_ = {"а", north = "А", },
    _B_ = {"Б", north = "б", },
    _b_ = {"б", north = "Б", },
    _V_ = {"В", north = "в", },
    _v_ = {"в", north = "В", },
    _H_ = {"Г", north = "г", northeast = "ґ", east = "Ґ", alt_label = "Ґ",},
    _h_ = {"г", north = "Г", northeast = "Ґ", east = "ґ", alt_label = "ґ",},
    _G_ = {"Ґ", north = "ґ", },
    _g_ = {"ґ", north = "Ґ", },
    _D_ = {"Д", north = "д", },
    _d_ = {"д", north = "Д", },
    _E_ = {"Е", north = "е", northwest = "ё", west = "Ё", },
    _e_ = {"е", north = "Е", northwest = "Ё", west = "ё", },
    _Ye_ = {"Є", north = "є", northwest = "э", west = "Э", },
    _ye_ = {"є", north = "Є", northwest = "Э", west = "э", },
    _Zh_ = {"Ж", north = "ж", },
    _zh_ = {"ж", north = "Ж", },
    _Z_ = {"З", north = "з", },
    _z_ = {"з", north = "З", },
    _Y_ = {"И", north = "и", northwest = "ы", west = "Ы", },
    _y_ = {"и", north = "И", northwest = "Ы", west = "ы", },
    _I_ = {"І", north = "і", northeast = "ї", east = "Ї", alt_label = "Ї",},
    _i_ = {"і", north = "І", northeast = "Ї", east = "ї", alt_label = "ї",},
    _Yi_ = {"Ї", north = "ї", },
    _yi_ = {"ї", north = "Ї", },
    _Yot_ = {"Й", north = "й", },
    _yot_ = {"й", north = "Й", },
    _K_ = {"К", north = "к", },
    _k_ = {"к", north = "К", },
    _L_ = {"Л", north = "л", },
    _l_ = {"л", north = "Л", },
    _M_ = {"М", north = "м", },
    _m_ = {"м", north = "М", },
    _N_ = {"Н", north = "н", },
    _n_ = {"н", north = "Н", },
    _O_ = {"О", north = "о", },
    _o_ = {"о", north = "О", },
    _P_ = {"П", north = "п", },
    _p_ = {"п", north = "П", },
    _R_ = {"Р", north = "р", },
    _r_ = {"р", north = "Р", },
    _S_ = {"С", north = "с", },
    _s_ = {"с", north = "С", },
    _T_ = {"Т", north = "т", },
    _t_ = {"т", north = "Т", },
    _U_ = {"У", north = "у", northwest = "ў", west = "Ў", },
    _u_ = {"у", north = "У", northwest = "Ў", west = "ў", },
    _F_ = {"Ф", north = "ф", },
    _f_ = {"ф", north = "Ф", },
    _Kh_ = {"Х", north = "х", },
    _kh_ = {"х", north = "Х", },
    _Ts_ = {"Ц", north = "ц", },
    _ts_ = {"ц", north = "Ц", },
    _Ch_ = {"Ч", north = "ч", },
    _ch_ = {"ч", north = "Ч", },
    _Sh_ = {"Ш", north = "ш", },
    _sh_ = {"ш", north = "Ш", },
    _Shch_ = {"Щ", north = "щ", },
    _shch_ = {"щ", north = "Щ", },
    _Ssn_ = {"Ь", north = "ь", northeast = "ъ", east = "Ъ", }, -- soft sign
    _ssn_ = {"ь", north = "Ь", northeast = "Ъ", east = "ъ", },
    _Yu_ = {"Ю", north = "ю", },
    _yu_ = {"ю", north = "Ю", },
    _Ya_ = {"Я", north = "я", },
    _ya_ = {"я", north = "Я", },
  -- _1_ and _1p: numeric key 1 and its popup sibling (they have north swipe ups of each other, the rest is the same)
  -- _1n and _1s: numpad key 1 (layer 2), -- superscript key 1 (layer 2, shifted)
  _1_ = { "1", north = "!", alt_label = "!", northeast = "¡", south = "'", southeast = "¿", east = "?", },
  _1p = { "!", north = "1", alt_label = "1", northeast = "¡", south = "'", southeast = "¿", east = "?", },
  _1n = { "1", north = "¹", northeast = "⅑", northwest = "⅐", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },
  _1s = { "¹", north = "1", northeast = "⅑", northwest = "⅐", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },

  _2_ = { "2", north = "@", alt_label = "@", northeast = "~", northwest = "http://", east = "-", west = "https://", south = '"', southeast = "…", southwest = "/", },
  _2p = { "@", north = "2", alt_label = "2", northeast = "~", northwest = "http://", east = "-", west = "https://", south = '"', southeast = "…", southwest = "/", },
  _2n = { "2", north = "²", northeast = "⅖", east = "½", south = "₂", southeast = "⅔", }, -- numpad 2
  _2s = { "²", north = "2", northeast = "⅖", east = "½", south = "₂", southeast = "⅔", }, -- superscript 2

  _3_ = { "3", north = "#", alt_label = "#", northeast = "☑", northwest = "★", east = "☐", west = "•", south = "№", southeast = "☒", southwest = "☆", ":)", ":|", ":(", },
  _3p = { "#", north = "3", alt_label = "3", northeast = "☑", northwest = "★", east = "☐", west = "•", south = "№", southeast = "☒", southwest = "☆", ":)", ":|", ":(", },
  _3n = { "3", north = "³", northwest = "¾", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", }, -- numpad 3
  _3s = { "³", north = "3", northwest = "¾", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", }, -- superscript 3

  _4_ = { "4", north = "$", alt_label = "$", northeast = "₸", northwest = "¥",  east = "₴", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
  _4p = { "$", north = "4", alt_label = "4", northeast = "₸", northwest = "¥",  east = "₴", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
  _4n = { "4", north = "⁴", east = "¼", south = "₄", southeast = "⅘", }, -- numpad 4
  _4s = { "⁴", north = "4", east = "¼", south = "₄", southeast = "⅘", }, -- superscript 4

  _5_ = { "5", north = "%", alt_label = "%", northeast = "‱", northwest = "‰", east = "⅓", west = "¼", south = "½", southeast = "⅔", southwest = "¾", },
  _5p = { "%", north = "5", alt_label = "5", northeast = "‱", northwest = "‰", east = "⅓", west = "¼", south = "½", southeast = "⅔", southwest = "¾", },
  _5n = { "5", north = "⁵", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", }, -- numpad 5
  _5s = { "⁵", north = "5", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", }, -- superscript 5

  -- diacritics. Symbols in quotation marks might look weird, however they should work fine.
  _6_ = {
  "6",
  north = "^",
  alt_label = "^",
  northeast = { label = "◌́", key = "́", }, -- Combining Acute Accent
  northwest = { label = "◌̀", key = "̀", }, -- Combinig Grave Accent
  east = { label = "◌̂", key = "̂", }, -- Combining Circumflex Accent
  west = { label = "◌̃", key = "̃", }, -- Combining Tilde
  south = { label = "◌̧", key = "̧", }, -- Combining Cedilla
  southeast = { label = "◌̈", key = "̈", }, -- Combining Diaeresis (Umlaut)
  southwest = { label = "◌̇", key = "̇", }, -- Combining Dot Above
  { label = "◌̄", key = "̄", }, -- Combining Macron
  { label = "◌̌", key = "̌", }, -- Combining Caron
  { label = "◌̨", key = "̨", }, -- Combining Ogonek
  },
  _6p = {
  "^",
  north = "6",
  alt_label = "6",
  northeast = { label = "◌́", key = "́", }, -- Combining Acute Accent
  northwest = { label = "◌̀", key = "̀", }, -- Combinig Grave Accent
  east = { label = "◌̂", key = "̂", }, -- Combining Circumflex Accent
  west = { label = "◌̃", key = "̃", }, -- Combining Tilde
  south = { label = "◌̧", key = "̧", }, -- Combining Cedilla
  southeast = { label = "◌̈", key = "̈", }, -- Combining Diaeresis (Umlaut)
  southwest = { label = "◌̇", key = "̇", }, -- Combining Dot Above
  { label = "◌̄", key = "̄", }, -- Combining Macron
  { label = "◌̌", key = "̌", }, -- Combining Caron
  { label = "◌̨", key = "̨", }, -- Combining Ogonek
  },
  _6n = { "6", north = "⁶", east = "⅙", south = "₆", }, -- numpad 6
  _6s = { "⁶", north = "6", east = "⅙", south = "₆", }, -- superscript 6

  _7_ = { "7", north = "&", alt_label = "&", northeast = "»", northwest = "«", east = "¶", west = "§", south = "¤", southeast = "⟩", southwest = "⟨", "†", "■", "‡", },
  _7p = { "&", north = "7", alt_label = "7", northeast = "»", northwest = "«", east = "¶", west = "§", south = "¤", southeast = "⟩", southwest = "⟨", "†", "■", "‡", },
  _7n = { "7", north = "⁷", east = "⅐", south = "₇", southeast = "⅞", }, -- numpad 7
  _7s = { "⁷", north = "7", east = "⅐", south = "₇", southeast = "⅞", }, -- superscript 7

  _8_ = { "8", north = "*", alt_label = "*", northeast = "=", northwest = "≠", east = "+", west = "-", south = "/", southeast = ">", southwest = "<", "≤", "≈", "≥", },
  _8p = { "*", north = "8", alt_label = "8", northeast = "=", northwest = "≠", east = "+", west = "-", south = "/", southeast = ">", southwest = "<", "≤", "≈", "≥", },
  _8n = { "8", north = "⁸", east = "⅛", south = "₈", }, -- numpad 8
  _8s = { "⁸", north = "8", east = "⅛", south = "₈", }, -- superscript 8

  _9_ = { "9", north = "(", alt_label = "(", northeast = "_", northwest = "“", east = "-", west = "{", south = "[", southeast = "—", southwest = "‘", },
  _9p = { "(", north = "9", alt_label = "9", northeast = "_", northwest = "“", east = "-", west = "{", south = "[", southeast = "—", southwest = "‘", },
  _9n = { "9", north = "⁹", east = "⅑", south = "₉", }, -- numpad 9
  _9s = { "⁹", north = "9", east = "⅑", south = "₉", }, -- superscript 9

  _0_ = { "0", north = ")", alt_label = ")", northwest = "”", west = "}", south = "]", southwest = "’", },
  _0p = { ")", north = "0", alt_label = "0", northwest = "”", west = "}", south = "]", southwest = "’", },
  _0n = { "0", north = "⁰", south = "₀", }, -- numpad 0
  _0s = { "⁰", north = "0", south = "₀", }, -- superscript 0

  sla = { "/", north = "÷", alt_label = "÷", northeast = "⅟", east = "⁄", }, -- numpad slash
  sl2 = { "÷", north = "/", alt_label = "/", northeast = "⅟", east = "⁄", }, -- superscript slash

  eql = { "=", north = "≠", alt_label = "≠", northwest = "≃",  west = "≡", south = "≈", southwest = "≉", }, -- equality
  eq2 = { "≠", north = "=", alt_label = "=", northwest = "≃", west = "≡", south = "≈", southwest = "≉", },  -- popup sibling
  ls1 = { "<", north = "≤", alt_label = "≤", south = "≪", }, -- "less than" sign
  ls2 = { "≤", north = "<", alt_label = "<", south = "≪", }, -- (popup sibling)
  mr1 = { ">", north = "≥", alt_label = "≥", south = "≫", }, -- "more than"
  mr2 = { "≥", north = ">", alt_label = ">", south = "≫", }, -- (popup sibling)
  pls = { "+", north = "±", alt_label = "±", }, -- plus sign
  pl2 = { "±", north = "+", alt_label = "+", }, -- (popup sibling)
  mns = { "-", north = "∓", alt_label = "∓", }, -- minus sign
  mn2 = { "∓", north = "-", alt_label = "-", }, -- (popup sibling)
  dsh = { "-", north = "—", alt_label = "—", south = "–", }, -- dashes
  dgr = { "†", north = "‡", alt_label = "‡", }, -- dagger
  tpg = { "¶", north = "§", alt_label = "§", northeast = "™", northwest = "℠", east = "¤", west = "•", south = "®", southeast = "🄯", southwest = "©", }, -- typography symbols
  mth = { "∇", north = "∀",alt_label = "∀",  northeast = "∃", northwest = "∄", east = "∈", west = "∉", south = "∅", southeast = "∩", southwest = "∪", "⊆", "⊂", "⊄", }, -- math operations 1
  mt2 = { "∞", north = "ℕ", alt_label = "ℕ", northeast = "ℤ", northwest = "ℚ", east = "𝔸", west = "ℝ", south = "𝕀", southeast = "ℂ", southwest = "𝕌", "⊇", "⊃", "⊅", }, -- math operations 2
  int = { "∫", north = "∬", alt_label = "∬", northeast = "⨌", northwest = "∭", east = "∑", west = "∏", south = "∮", southeast = "∰", southwest = "∯", "⊕", "ℍ", "⊗", }, -- integrals
  dif = { "∂", north = "√", alt_label = "√", northeast = "∴", east = "⇒", south = "⇔", southeast = "∵", }, -- math operations 3
  df2 = { "…", north = "⟂", alt_label = "⟂", northeast = "∡", northwest = "∟", east = "∝", west = "ℓ", }, -- math operations 4
  pdc = { "*", north = "⨯", alt_label = "⨯", south = "⋅", }, -- asterisk, cross-product and dot-prodcuts symbols
  pd2 = { "⨯", north = "*", alt_label = "*", south = "⋅", },
  bar = { "|", north = "¦", alt_label = "¦", }, -- bars like pipe and broken bar
  prm = { "‰", north = "‱", alt_label = "‱", }, -- per mile types
  hsh = { "#", north = "№", alt_label = "№", }, -- hash and "No." sign
  hs2 = { "№", north = "#", alt_label = "#", },
}
