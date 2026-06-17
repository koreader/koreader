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
        east = "\u{201C}",
        west = "\u{201D}",
        south = "`",
        southeast = "\u{2018}",
        southwest = "\u{2019}",
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
        "+",
        "]",
    },
    zwj = {
        "‍",
        label = "ZWJ",
    },
    zwnj = {
        "‌",
        label = "ZWNJ"
    },
    -- vowels
    _a_in_ = { -- independent vowel
        "അ",
        north = "്",
    },
    _aa_ = { -- dependent vowel sign
        "ാ",
        north = "ആ",
    },
    _aa_in_ = {
        "ആ",
        north = "ാ",
    },
    _i_ = {
        "ി",
        north = "ഇ",
    },
    _i_in_ = {
        "ഇ",
        north = "ി",
    },
    _ii_ = {
        "ീ",
        north = "ഈ",
    },
    _ii_in_ = {
        "ഈ",
        north = "ീ",
    },
    _u_ = {
        "ു",
        north = "ഉ",
    },
    _u_in_ = {
        "ഉ",
        north = "ു",
    },
    _uu_ = {
        "ൂ",
        north = "ഊ",
    },
    _uu_in_ = {
        "ഊ",
        north = "ൂ",
    },
    _r_ = {
        "ൃ",
        north = "ഋ",
    },
    _r_in_ = {
        "ഋ",
        north = "ൃ",
    },
    _e_ = {
       "െ",
       north = "എ",
    },
    _e_in_ = {
       "എ",
       north = "െ",
    },
    _ee_ = {
        "േ",
        north = "ഏ",
        east = "ൈ",
        south = "ഐ",
    },
    _ee_in_ = {
        "ഏ",
        north = "േ",
        east = "ഐ",
        south = "ൈ",
    },
    _o_ = {
        "ൊ",
        north = "ഒ",
    },
    _o_in_ = {
        "ഒ",
        north = "ൊ",
    },
    _oo_ = {
        "ോ",
        north = "ഓ",
        east = "ൗ",
        south = "ഔ",
    },
    _oo_in_ = {
        "ഓ",
        north = "ോ",
        east = "ഔ",
        south = "ൗ",
    },
    -- varga consonants
    _ka_ = {
        "ക",
        north = "ഖ",
    },
    _kha_ = {
        "ഖ",
        north = "ക",
    },
    _ga_ = {
        "ഗ",
        north = "ഘ",
    },
    _gha_ = {
        "ഘ",
        north = "ഗ",
    },
    _nga_ = {
        "ങ",
        north = "ഞ",
        south = "ങ്ങ", -- ligature of ങ (doubled up, commonly used)
    },
    _ca_ = {
        "ച",
        north = "ഛ",
    },
    _cha_ = {
        "ഛ",
        north = "ച",
    },
    _ja_ = {
        "ജ",
        north = "ഝ",
    },
    _jha_ = {
        "ഝ",
        north = "ജ",
    },
    _nya_ = {
        "ഞ",
        north = "ങ",
        south = "ഞ്ഞ", -- ligature of ഞ (doubled up, commonly used)
    },
    _tta_ = {
        "ട",
        north = "ഠ",
    },
    _ttha_ = {
        "ഠ",
        north = "ട",
    },
    _dda_ = {
        "ഡ",
        north = "ഢ",
    },
    _ddha_ = {
        "ഢ",
        north = "ഡ",
    },
    _nna_ = {
        "ണ",
        north = "ൺ",
    },
    _ta_ = {
        "ത",
        north = "ഥ",
    },
    _tha_ = {
        "ഥ",
        north = "ത",
    },
    _da_ = {
        "ദ",
        north = "ധ",
    },
    _dha_ = {
        "ധ",
        north = "ദ",
    },
    _na_ = {
        "ന",
        north = "ൻ",
    },
    _pa_ = {
        "പ",
        north = "ഫ",
    },
    _pha_ = {
        "ഫ",
        north = "പ",
    },
    _ba_ = {
        "ബ",
        north = "ഭ",
    },
    _bha_ = {
        "ഭ",
        north = "ബ",
    },
    _ma_ = {
        "മ",
        north = "ം",
        alt_label = "ം",
    },
    -- other consonants
    _ya_ = {
        "യ",
        north = "്യ", -- alternative sign: ഞ +  ്യ = ഞ്യ
        alt_label = "്യ",
    },
    _ya_li_ = {
        "്യ",
        north = "യ",
    },
    _ra_ = {
        "ര",
        north = "്ര", -- alternative sign: ഞ +  ്ര = ഞ്ര
        alt_label = "്ര",
    },
    _ra_li_ = {
        "്ര",
        north = "ര",
    },
    _la_ = {
        "ല",
        north = "ൽ",
    },
    _va_ = {
        "വ",
        north = "്വ", -- alternative sign: ഞ +  ്വ = ഞ്വ
        alt_label = "്വ",
    },
    _va_li_ = {
        "്വ",
        north = "വ",
    },
    _sha_ = {
        "ശ",
        north = "ഷ",
    },
    _ssa_ = {
        "ഷ",
        north = "ശ",
    },
    _sa_ = {
        "സ",
    },
    _ha_ = {
        "ഹ",
        north = "ഃ",
        alt_label = "ഃ",
    },
    _lla_ = {
        "ള",
        north = "ൾ",
    },
    _llla_ = {
        "ഴ",
    },
    _rra_ = {
        "റ",
        north = "ർ",
    },
    -- virama, visarga, anusvara
    _virama_ = {
        "്",
        north = "അ",
    },
    _visarga_ = {
        "ഃ",
        north = "ഹ",
    },
    _anusvara_ = {
        "ം",
        north = "മ",
    },
    -- chillu
    _chillu_l_ = {
        "ൽ",
        north = "ല",
    },
    _chillu_ll_ = {
        "ൾ",
        north = "ള",
    },
    _chillu_rr_ = {
        "ർ",
        north = "റ",
    },
    _chillu_n_ = {
        "ൻ",
        north = "ന",
    },
    _chillu_nn_ = {
        "ൺ",
        north = "ണ",
    },
    -- others
    _1_ = { "1", north = "!", alt_label = "!", south = "൧",},
    _1p = { "!", north = "1", alt_label = "1", south = "൧", },
    _1n = { "1", north = "¹", northeast = "⅑", northwest = "൧", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },
    _1s = { "¹", north = "1", northeast = "⅑", northwest = "൧", east = "⅙", west = "¼", south = "₁", southwest = "½", southeast = "⅓", "⅕", "⅛", "⅒", },

    _2_ = { "2", north = "@", alt_label = "@", south = "൨", },
    _2p = { "@", north = "2", alt_label = "2", south = "൨", },
    _2n = { "2", north = "²", northeast = "⅖", northwest = "൨", east = "½", south = "₂", southeast = "⅔", },
    _2s = { "²", north = "2", northeast = "⅖", northwest = "൨", east = "½", south = "₂", southeast = "⅔", },

    _3_ = { "3", north = "#", alt_label = "#", south = "൩", },
    _3p = { "#", north = "3", alt_label = "3", south = "൩", },
    _3n = { "3", north = "³", northeast = "¾", northwest = "൩", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", },
    _3s = { "³", north = "3", northeast = "¾", northwest = "൩", east = "⅓", west = "⅗", southwest = "⅜", south = "₃", },

    _4_ = { "4", north = "₹", alt_label = "₹", south = "൪", },
    _4p = { "₹", north = "4", alt_label = "4", south = "൪", },
    _4n = { "4", north = "⁴", northwest = "൪", east = "¼", south = "₄", southeast = "⅘", },
    _4s = { "⁴", north = "4", northwest = "൪", east = "¼", south = "₄", southeast = "⅘", },

    _5_ = { "5", north = "%", alt_label = "%", south = "൫", },
    _5p = { "%", north = "5", alt_label = "5", south = "൫", },
    _5n = { "5", north = "⁵", northwest = "൫", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", },
    _5s = { "⁵", north = "5", northwest = "൫", northeast = "⅚", east = "⅕", south = "₅", southeast = "⅝", },

    _6_ = { "6", north = "^", alt_label = "^", south = "൬", },
    _6p = { "^", north = "6", alt_label = "6", south = "൬", },
    _6n = { "6", north = "⁶", northwest = "൬", east = "⅙", south = "₆", },
    _6s = { "⁶", north = "6", northwest = "൬", east = "⅙", south = "₆", },

    _7_ = { "7", north = "&", alt_label = "&", south = "൭", },
    _7p = { "&", north = "7", alt_label = "7", south = "൭", },
    _7n = { "7", north = "⁷", northwest = "൭", east = "⅐", south = "₇", southeast = "⅞", },
    _7s = { "⁷", north = "7", northwest = "൭", east = "⅐", south = "₇", southeast = "⅞", },

    _8_ = { "8", north = "*", alt_label = "*", south = "൮", },
    _8p = { "*", north = "8", alt_label = "8", south = "൮", },
    _8n = { "8", north = "⁸", northwest = "൮", east = "⅛", south = "₈", },
    _8s = { "⁸", north = "8", northwest = "൮", east = "⅛", south = "₈", },

    _9_ = { "9", north = "(", alt_label = "(", south = "൯", },
    _9p = { "(", north = "9", alt_label = "9", south = "൯", },
    _9n = { "9", north = "⁹", northwest = "൯", east = "⅑", south = "₉", },
    _9s = { "⁹", north = "9", northwest = "൯", east = "⅑", south = "₉", },

    _0_ = { "0", north = ")", alt_label = ")", south = "൦", },
    _0p = { ")", north = "0", alt_label = "0", south = "൦", },
    _0n = { "0", north = "⁰", northwest = "൦", south = "₀", },
    _0s = { "⁰", north = "0", northwest = "൦", south = "₀", },

    sla = { "/", north = "÷", alt_label = "÷", northeast = "⅟", east = "⁄", },
    sl2 = { "÷", north = "/", alt_label = "/", northeast = "⅟", east = "⁄", },

    eql = { "=", north = "≠", alt_label = "≠", northwest = "≃", west = "≡", south = "≈", southwest = "≉", },
    eq2 = { "≠", north = "=", alt_label = "=", northwest = "≃", west = "≡", south = "≈", southwest = "≉", },
    ls1 = { "<", north = "≤", alt_label = "≤", south = "≪", },
    ls2 = { "≤", north = "<", alt_label = "<", south = "≪", },
    mr1 = { ">", north = "≥", alt_label = "≥", south = "≫", },
    mr2 = { "≥", north = ">", alt_label = ">", south = "≫", },
    pls = { "+", north = "±", alt_label = "±", },
    pl2 = { "±", north = "+", alt_label = "+", },
    mns = { "-", north = "∓", alt_label = "∓", },
    mn2 = { "∓", north = "-", alt_label = "-", },
    dsh = { "-", north = "—", alt_label = "—", south = "–", },
    dgr = { "†", north = "‡", alt_label = "‡", },
    tpg = { "¶", north = "§", alt_label = "§", northeast = "™", northwest = "℠", east = "¤", west = "•", south = "®", southeast = "🄯", southwest = "©", },
    mth = { "∇", north = "∀", alt_label = "∀", northeast = "∃", northwest = "∄", east = "∈", west = "∉", south = "∅", southeast = "∩", southwest = "∪", "⊆", "⊂", "⊄", },
    mt2 = { "∞", north = "ℕ", alt_label = "ℕ", northeast = "ℤ", northwest = "ℚ", east = "𝔸", west = "ℝ", south = "𝕀", southeast = "ℂ", southwest = "𝕌", "⊇", "⊃", "⊅", },
    int = { "∫", north = "∬", alt_label = "∬", northeast = "⨌", northwest = "∭", east = "∑", west = "∏", south = "∮", southeast = "∰", southwest = "∯", "⊕", "ℍ", "⊗", },
    dif = { "∂", north = "√", alt_label = "√", northeast = "∴", east = "⇒", south = "⇔", southeast = "∵", },
    df2 = { "…", north = "⟂", alt_label = "⟂", northeast = "∡", northwest = "∟", east = "∝", west = "ℓ", },
    pdc = { "*", north = "⨯", alt_label = "⨯", south = "⋅", },
    pd2 = { "⨯", north = "*", alt_label = "*", south = "⋅", },
    bar = { "|", north = "¦", alt_label = "¦", },
    prm = { "‰", north = "‱", alt_label = "‱", },
    hsh = { "#", north = "№", alt_label = "№", },
    hs2 = { "№", north = "#", alt_label = "#", },
}
