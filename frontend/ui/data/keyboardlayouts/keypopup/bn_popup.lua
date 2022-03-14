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
        north = {
            key = "‍",
            label = "ZWJ",
        },
        alt_label = "ZWJ",
        northeast = "'",
        northwest = "=",
        east = "!",
        west = "?",
        south = "|",
        southeast = ":",
        southwest = "/",
        "\\",
        '^',
        "&",
        "$",
    },
    cop = { -- colon + period
        "‍",
        label = "ZWJ",
        north = ".",
        alt_label = ".",
        northeast = "'",
        northwest = "=",
        east = "!",
        west = "?",
        south = "|",
        southeast = ":",
        southwest = "/",
        "\\",
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
    _da_ = {
        "দ",
        north = "ধ",
        alt_label = "ধ",
    },
    _dha_ = {
        "ধ",
        north = "দ",
        alt_label = "দ",
    },
    _U_kaar_ = {
        "ূ",
        north = "ঊ",
        alt_label = "ঊ",
    },
    _U_ = {
        "ঊ",
        north = "ূ",
        alt_label = "ূ",
    },
    _I_kaar_ = {
        "ী",
        north = "ঈ",
        alt_label = "ঈ",
    },
    _I_ = {
        "ঈ",
        north = "ী",
        alt_label = "ী",

    },
    _ra_ = {
        "র",
        north = "ড়",
        alt_label = "ড়",
        northeast = "Ð",
        northwest = "Ď",
        east = "$", -- Dollar currency
        west = "Đ",
        south = "∂", -- partial derivative
        southeast = "Δ", -- Greek delta
    },
    _rda_ = {
        "ড়",
        north = "র",
        alt_label = "র",
    },
    _Ta_ = {
        "ট",
        north = "ঠ",
        alt_label = "ঠ",
    },
    _Tha_ = {
        "ঠ",
        north = "ট",
        alt_label = "ট",
    },
    _e_ = {
        "এ",
        north = "ঐ",
        alt_label = "ঐ",
    },
    _oi_ = {
        "ঐ",
        north = "এ",
        alt_label = "এ",
    },
    _u_kaar_ = {
        "ু",
        north = "উ",
        alt_label = "উ",
    },
    _u_ = {
        "উ",
        north = "ু",
        alt_label = "ু",
    },
    _i_kaar_ = {
        "ি",
        north = "ই",
        alt_label = "ই",
    },
    _i_ = {
        "ই",
        north = "ি",
        alt_label = "ি",
    },
    _o_ = {
        "ও",
        north = "ঔ",
        alt_label = "ঔ",

    },
    _ou_ = {
        "ঔ",
        north = "ও",
        alt_label = "ও",

    },
    _pa_ = {
        "প",
        north = "ফ",
        alt_label = "ফ",
    },
    _pha_ = {
        "ফ",
        north = "প",
        alt_label = "প",
    },
    _e_kaar_ = {
        "ে",
        north = "ৈ",
        alt_label = "ৈ",
    },
    _oi_kaar_ = {
        "ৈ",
        north = "ে",
        alt_label = "ে",
    },
    _o_kaar_ = {
        "ো",
        north = "ৌ",
        alt_label = "ৌ",
    },
    _ou_kaar_ = {
        "ৌ",
        north = "ো",
        alt_label = "ো",
    },
    _aa_kaar_ = {
        "া",
        north = "অ",
        alt_label = "অ",
    },
    _a_ = {
        "অ",
        north = "া",
        alt_label = "া",
    },
    _sa_ = {
        "স",
        north = "ষ",
        alt_label = "ষ",

    },
    _sHa_ = {
        "ষ",
        north = "স",
        alt_label = "স",

    },
    _Da_ = {
        "ড",
        north = "ঢ",
        alt_label = "ঢ",
    },
    _Dha_ = {
        "ঢ",
        north = "ড",
        alt_label = "ড",
    },
    _ta_ = {
        "ত",
        north = "থ",
        alt_label = "থ",
    },
    _tha_ = {
        "থ",
        north = "ত",
        alt_label = "ত",
    },
    _ga_ = {
        "গ",
        north = "ঘ",
        alt_label = "ঘ",
    },
    _gha_ = {
        "ঘ",
        north = "গ",
        alt_label = "গ",
    },
    _ha_ = {
        "হ",
        north = "ঃ",
        alt_label = "ঃ",
    },
    _bisarga_ = {
        "ঃ",
        north = "হ",
        alt_label = "হ",
    },
    _ja_ = {
        "জ",
        north = "ঝ",
        alt_label = "ঝ",
    },
    _jha_ = {
        "ঝ",
        north = "জ",
        alt_label = "জ",
    },
    _ka_ = {
        "ক",
        north = "খ",
        alt_label = "খ",

    },
    _kha_ = {
        "খ",
        north = "ক",
        alt_label = "ক",
    },
    _la_ = {
        "ল",
        north = "ং",
        alt_label = "ং",
    },
    _anuswara_ = {
        "ং",
        north = "ল",
        alt_label = "ল",

    },
    _jya_ = {
        "য",
        north = "য়",
        alt_label = "য়",

    },
    _ya_ = {
        "য়",
        north = "য",
        alt_label = "য",

    },
    _sha_ = {
        "শ",
        north = "ঢ়",
        alt_label = "ঢ়",

    },
    _Rha_ = {
        "ঢ়",
        north = "শ",
        alt_label = "শ",
    },
    _cha_ = {
        "চ",
        north = "ছ",
        alt_label = "ছ",
    },
    _Cha_ = {
        "ছ",
        north = "চ",
        alt_label = "চ",
    },
    _aa_ = {
        "আ",
        north = "ঋ",
        alt_label = "ঋ",
    },
    _rwi_ = {
        "ঋ",
        north = "আ",
        alt_label = "আ",
    },
    _ba_ = {
        "ব",
        north = "ভ",
        alt_label = "ভ",
    },
    _bha_ = {
        "ভ",
        north = "ব",
        alt_label = "ব",
    },
    _na_ = {
        "ন",
        north = "ণ",
        alt_label = "ণ",

    },
    _Na_ = {
        "ণ",
        north = "ন",
        alt_label = "ন",
    },
    _ma_ = {
        "ম",
        north = "ঙ",
        alt_label = "ঙ",

    },
    _uma_ = {
        "ঙ",
        north = "ম",
        alt_label = "ম",

    },
    _rwi_kaar_ = {
        "ৃ",
        north = ",",
        alt_label = ","
    },
    _chandrabindu_ = {
        "ঁ",
        north = "।",
        alt_label = "।",
    },
    --  Bengali Pancuations
    com2 = {
        ",",
        north = "ৃ",
        alt_label = "ৃ",
    },
    daari = {
        "।",
        north = "ঁ",
        alt_label = "ঁ",
    },
    hashanto = {
        "্",
        north = "?",
        alt_label = "?",

    },
    question2 = {
        "?",
        north = "্",
        alt_label = "্",

    },
  -- _1_ and _1p: numeric key 1 and its popup sibling (they have north swipe ups of each other, the rest is the same)
  -- _1n and _1s: numpad key 1 (layer 2), -- superscript key 1 (layer 2, shifted)
  _1_ = { "১", north = "!", alt_label = "!", northeast = "¡", south = "'", southeast = "¿", east = "?", },
  _1p = { "!", north = "১", alt_label = "১", northeast = "¡", south = "'", southeast = "¿", east = "?", },
  _1n = { "১", north = "¹", northeast = "⅑", northwest = "⅐", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },
  _1s = { "¹", north = "১", northeast = "⅑", northwest = "⅐", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },

  _2_ = { "২", north = "@", alt_label = "@", northeast = "~", northwest = "http://", east = "-", west = "https://", south = '"', southeast = "…", southwest = "/", },
  _2p = { "@", north = "২", alt_label = "২", northeast = "~", northwest = "http://", east = "-", west = "https://", south = '"', southeast = "…", southwest = "/", },
  _2n = { "২", north = "²", northeast = "⅖", east = "½", south = "₂", southeast = "⅔", }, -- numpad 2
  _2s = { "²", north = "২", northeast = "⅖", east = "½", south = "₂", southeast = "⅔", }, -- superscript 2

  _3_ = { "৩", north = "#", alt_label = "#", northeast = "☑", northwest = "★", east = "☐", west = "•", south = "№", southeast = "☒", southwest = "☆", ":)", ":|", ":(", },
  _3p = { "#", north = "৩", alt_label = "৩", northeast = "☑", northwest = "★", east = "☐", west = "•", south = "№", southeast = "☒", southwest = "☆", ":)", ":|", ":(", },
  _3n = { "৩", north = "³", northwest = "¾", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", }, -- numpad 3
  _3s = { "³", north = "৩", northwest = "¾", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", }, -- superscript 3

  _4_ = { "৪", north = "৳", alt_label = "$", northeast = "₹", northwest = "¥",  east = "₽", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
  _4p = { "৳", north = "৪", alt_label = "৪", northeast = "₹", northwest = "¥",  east = "₽", west = "£", south = "€", southeast = "¢", southwest = "₪", "₹", "₿", "₺", },
  _4n = { "৪", north = "⁴", east = "¼", south = "₄", southeast = "⅘", }, -- numpad 4
  _4s = { "⁴", north = "৪", east = "¼", south = "₄", southeast = "⅘", }, -- superscript 4

  _5_ = { "৬", north = "%", alt_label = "%", northeast = "‱", northwest = "‰", east = "⅓", west = "¼", south = "½", southeast = "⅔", southwest = "¾", },
  _5p = { "%", north = "৬", alt_label = "৫", northeast = "‱", northwest = "‰", east = "⅓", west = "¼", south = "½", southeast = "⅔", southwest = "¾", },
  _5n = { "৫", north = "⁵", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", }, -- numpad 5
  _5s = { "⁵", north = "৫", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", }, -- superscript 5

  -- diacritics. Symbols in quotation marks might look weird, however they should work fine.
  _6_ = {
  "৬",
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
  north = "৬",
  alt_label = "৬",
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
  _6n = { "৬", north = "⁶", east = "⅙", south = "₆", }, -- numpad 6
  _6s = { "⁶", north = "৬", east = "⅙", south = "₆", }, -- superscript 6

  _7_ = { "৭", north = "ঞ", alt_label = "ঞ", northeast = "»", northwest = "«", east = "¶", west = "§", south = "¤", southeast = "⟩", southwest = "⟨", "†", "■", "‡", },
  _7p = { "ঞ", north = "৭", alt_label = "৭", northeast = "»", northwest = "«", east = "¶", west = "§", south = "¤", southeast = "⟩", southwest = "⟨", "†", "■", "‡", },
  _7n = { "৭", north = "⁷", east = "⅐", south = "₇", southeast = "⅞", }, -- numpad 7
  _7s = { "⁷", north = "৭", east = "⅐", south = "₇", southeast = "⅞", }, -- superscript 7

  _8_ = { "৮", north = "ৎ", alt_label = "ৎ", northeast = "=", northwest = "≠", east = "+", west = "-", south = "/", southeast = ">", southwest = "<", "≤", "≈", "≥", },
  _8p = { "ৎ", north = "৮", alt_label = "৮", northeast = "=", northwest = "≠", east = "+", west = "-", south = "/", southeast = ">", southwest = "<", "≤", "≈", "≥", },
  _8n = { "৮", north = "⁸", east = "⅛", south = "₈", }, -- numpad 8
  _8s = { "⁸", north = "৮", east = "⅛", south = "₈", }, -- superscript 8

  _9_ = { "৯", north = "(", alt_label = "(", northeast = "_", northwest = "“", east = "-", west = "{", south = "[", southeast = "—", southwest = "‘", },
  _9p = { "(", north = "৯", alt_label = "৯", northeast = "_", northwest = "“", east = "-", west = "{", south = "[", southeast = "—", southwest = "‘", },
  _9n = { "৯", north = "⁹", east = "⅑", south = "₉", }, -- numpad 9
  _9s = { "⁹", north = "৯", east = "⅑", south = "₉", }, -- superscript 9


  _0_ = { "০", north = ")", alt_label = ")", northwest = "”", west = "}", south = "]", southwest = "’", },
  _0p = { ")", north = "০", alt_label = "০", northwest = "”", west = "}", south = "]", southwest = "’", },
  _0n = { "০", north = "⁰", south = "₀", }, -- numpad 0
  _0s = { "⁰", north = "০", south = "₀", }, -- superscript 0

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
