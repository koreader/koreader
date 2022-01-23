return {
    pco = { -- period + colon
        ".",
        north = ":",
        alt_label = ":",
        northeast = "'",
        northwest = "=",
        east = "!",
        west = "?",
        south = "|",
        southeast = "\\",
        southwest = "/",
        '^',
        "&",
        "$",
    },
    cop = { -- colon + period
        ":",
        north = ".",
        alt_label = ".",
        northeast = "'",
        northwest = "=",
        east = "!",
        west = "?",
        south = "|",
        southeast = "\\",
        southwest = "/",
        '^',
        "&",
        "$",
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
        width = 1.0,
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
        width = 1.0,
    },

     -- Russian layout, top row of letters (11 keys): й ц у к е/ё н г ш щ з х
    _YK = { "Й", north = "й", },
    _yk = { "й", north = "Й", },
    _TS = { "Ц", north = "ц", },
    _ts = { "ц", north = "Ц", },
    _UU = { "У", north = "у", northeast = "ұ", east = "Ұ", }, --  with Kazakh letter(s)
    _uu = { "у", north = "У", northeast = "Ұ", east = "ұ", }, --  with Kazakh letter(s)
    _KK = { "К", north = "к", northeast = "қ", east = "Қ", }, --  with Kazakh letter(s)
    _kk = { "к", north = "К", northeast = "Қ", east = "қ", }, --  with Kazakh letter(s)
    _YE = { "Е", north = "е", northwest = "ё", west = "Ё", },
    _ye = { "е", north = "Е", northwest = "Ё", west = "ё", },
    _EN = { "Н", north = "н", northeast = "ң", east = "Ң", }, --  with Kazakh letter(s)
    _en = { "н", north = "Н", northeast = "Ң", east = "ң", }, --  with Kazakh letter(s)
    _GG = { "Г", north = "г", northeast = "ғ", northwest = "ґ", east = "Ғ", west = "Ґ", }, --  with Kazakh and Ukrainian letter(s)
    _gg = { "г", north = "Г", northeast = "Ғ", northwest = "Ґ", east = "ғ", west = "ґ", }, --  with Kazakh and Ukrainian letter(s)
    _WA = { "Ш", north = "ш", },
    _wa = { "ш", north = "Ш", },
    _WE = { "Щ", north = "щ", },
    _we = { "щ", north = "Щ", },
    _ZE = { "З", north = "з", },
    _ze = { "з", north = "З", },
    _HA = { "Х", north = "х", northeast = "һ", east = "Һ", }, --  with Kazakh letter(s)
    _ha = { "х", north = "Х", northeast = "Һ", east = "һ", }, --  with Kazakh letter(s)

    -- Russian layout, middle row of letters (11 keys): ф ы в а п р о л д ж э
    _EF = { "Ф", north = "ф", },
    _ef = { "ф", north = "Ф", },
    _YY = { "Ы", north = "ы", northwest = "і", west = "І", },
    _yy = { "ы", north = "Ы", northwest = "І", west = "і", },
    _VE = { "В", north = "в", },
    _ve = { "в", north = "В", },
    _AA = { "А", north = "а", northeast = "ә", east = "Ә", }, --  with Kazakh letter(s)
    _aa = { "а", north = "А", northeast = "Ә", east = "ә", }, --  with Kazakh letter(s)
    _PE = { "П", north = "п", },
    _pe = { "п", north = "П", },
    _ER = { "Р", north = "р", },
    _er = { "р", north = "Р", },
    _OO = { "О", north = "о", northeast = "ө", east = "Ө", }, --  with Kazakh letter(s)
    _oo = { "о", north = "О", northeast = "Ө", east = "ө", }, --  with Kazakh letter(s)
    _EL = { "Л", north = "л", },
    _el = { "л", north = "Л", },
    _DE = { "Д", north = "д", },
    _de = { "д", north = "Д", },
    _JE = { "Ж", north = "ж", northwest = "ӂ", west = "Ӂ", }, -- Ж with breve (Moldavian)
    _je = { "ж", north = "Ж", northwest = "Ӂ", west = "ӂ", }, -- ж with breve (Moldavian)
    _EE = { "Э", north = "э", northwest = "є", west = "Є", }, -- with Ukrainian letter(s)
    _ee = { "э", north = "Э", northwest = "Є", west = "є", }, -- with Ukrainian letter(s)

    -- Russian layout, bottom row of letters (9 keys): я ч с м и т ь/ъ б ю
    _YA = { "Я", north = "я", }, -- width is changed is that Shift and Backspace can be 1.5 wide
    _ya = { "я", north = "Я", },
    _CH = { "Ч", north = "ч", },
    _ch = { "ч", north = "Ч", },
    _ES = { "С", north = "с", },
    _es = { "с", north = "С", },
    _EM = { "М", north = "м", },
    _em = { "м", north = "М", },
    _II = { "И", north = "и", northeast = "і", northwest = "ї", west = "ї", east = "і", }, -- with Kazakh and Ukrainian letter(s)
    _ii = { "и", north = "И", northeast = "I", northwest = "Ї", west = "ї", east = "і", }, -- with Kazakh and Ukrainian letter(s)
    _TE = { "Т", north = "т", },
    _te = { "т", north = "Т", },
    _SH = { "Ь", north = "ь", northwest = "ъ", west = "Ъ", },
    _sh = { "ь", north = "Ь", northwest = "Ъ", west = "ъ", },
    _BE = { "Б", north = "б", },
    _be = { "б", north = "Б", },
    _YU = { "Ю", north = "ю", northeast = "ү", east = "Ү", }, -- with Kazakh letter(s)
    _yu = { "ю", north = "Ю", northeast = "Ү", east = "ү", }, -- with Kazakh letter(s)

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

  _4_ = { "4", north = "$", alt_label = "$", northeast = "₸", northwest = "¥",  east = "₽", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
  _4p = { "$", north = "4", alt_label = "4", northeast = "₸", northwest = "¥",  east = "₽", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
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
  eq2 = { "≠", north = "=", alt_label = "=", northwest = "≃",  west = "≡", south = "≈", southwest = "≉", },  -- popup sibling
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
  mth = { "∇", north = "∀", alt_label = "∀", northeast = "∃", northwest = "∄", east = "∈", west = "∉", south = "∅", southeast = "∩", southwest = "∪", "⊆", "⊂", "⊄", }, -- math operations 1
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
