-- This is adapted en_popup
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
    _А_ = {
        "А",
        north = "а",
        northeast = "Á",
        northwest = "À",
        east = "Â",
        west = "Ã",
        south = "Ą",
        southeast = "Ä",
        southwest = "Å",
        "Ā",
        "Ǎ",
        "Æ",
    },
    _а_ = {
        "а",
        north = "А",
        northeast = "á",
        northwest = "à",
        east = "â",
        west = "ã",
        south = "ą",
        southeast = "ä",
        southwest = "å",
        "ā",
        "ǎ",
        "æ",
    },
    _Б_ = {
        "Б",
        north = "б",
        east = "Β", -- Greek beta
        west = "♭",
    },
    _б_ = {
        "б",
        north = "Б",
        east = "β", -- Greek beta
        west = "♭",
    },
    _В_ = {
        "В",
        north = "в", -- open-mid back unrounded vowel IPA
        northeast = "ʌ",
        northwest = "Ʋ", -- v with hook
        east = "Ꜹ",
        west = "Ṽ",
    },
    _в_ = {
        "в",
        north = "В",
        northeast = "ʌ", -- open-mid back unrounded vowel IPA
        northwest = "ʋ", -- v with hook, labiodental approximant IPA
        east = "ꜹ",
        west = "ṽ",
    },
    _Г_ = {
        "Г",
        north = "г",
        northeast = "Γ", -- Greek gamma
        east = "ɣ", -- voiced velar fricative IPA
    },
    _г_ = {
        "г",
        north = "Г",
        northeast = "γ", -- Greek gamma
        east = "ɣ", -- voiced velar fricative IPA
    },
    _Д_ = {
        "Д",
        north = "д",
        northeast = "Ð",
        northwest = "Ď",
        east = "$", -- Dollar currency
        west = "Đ",
        south = "∂", -- partial derivative
        southeast = "Δ", -- Greek delta
    },
    _д_ = {
        "д",
        north = "Д",
        northeast = "ð",
        northwest = "ď",
        east = "$", -- Dollar currency
        west = "đ",
        south = "∂", -- partial derivative
        southeast = "δ", -- Greek delta
    },
    _Ђ_ = {
        "Ђ",
        north = "ђ",
        northeast = "Ð",
        east = "đ", -- Dollar currency
    },
    _ђ_ = {
        "ђ",
        north = "Ђ",
        northeast = "Đ",
        east = "đ", -- Dollar currency
    },
    _Е_ = {
        "Е",
        north = "е",
        northeast = "É",
        northwest = "È",
        east = "Ê",
        west = "Ẽ",
        south = "Ę",
        southeast = "Ë",
        southwest = "Ė",
        "Ē",
        "Ě",
        "€", -- Euro currency
    },
    _е_ = {
        "е",
        north = "Е",
        northeast = "é",
        northwest = "è",
        east = "ê",
        west = "ẽ",
        south = "ę",
        southeast = "ë",
        southwest = "ė",
        "ē",
        "ě",
        "€", -- Euro currency
    },
    _Ж_ = {
        "Ж",
        north = "ж",
        northeast = "Ž",
        east = "ž", -- Dollar currency
    },
    _ж_ = {
        "ж",
        north = "Ж",
        northeast = "Ž",
        east = "ž", -- Dollar currency
    },
    _З_ = {
        "З",
        north = "з",
        northeast = "Ζ", -- Greek zeta
        east = "Ź",
        west = "Ž",
        south = "ʐ", -- voiced retroflex sibilant fricative IPA
        southeast = "ʒ", -- ezh, voiced palato-alveolar fricative IPA
        southwest = "Ż",
    },
    _з_ = {
        "з",
        north = "З",
        northeast = "ζ", -- Greek zeta
        east = "ź",
        west = "ž",
        south = "ʐ", -- voiced retroflex sibilant fricative IPA
        southeast = "ʒ", -- ezh, voiced palato-alveolar fricative IPA
        southwest = "ż",
    },
    _И_ = {
        "И",
        north = "и",
        northeast = "Í",
        northwest = "Ì",
        east = "Î",
        west = "Ĩ",
        south = "Į",
        southeast = "Ï",
        southwest = "ɪ",
        "Ī",
        "Ι", -- Greek iota
        "I", -- dotless I (Turkish)
    },
    _и_ = {
        "и",
        north = "И",
        northeast = "í",
        northwest = "ì",
        east = "î",
        west = "ĩ",
        south = "į",
        southeast = "ï",
        southwest = "ɪ",
        "ī",
        "ι", -- Greek iota
        "ı", -- dotless i (Turkish)
    },
    _Ј_ = {
        "Ј",
        north = "ј",
        east = "ʝ", -- voiced palatal fricative
    },
    _ј_ = {
        "ј",
        north = "Ј",
        east = "ʝ", -- voiced palatal fricative
    },
    _К_ = {
        "К",
        north = "к",
        northwest = "Κ", -- Greek kappa
        west = "Ķ",
    },
    _к_ = {
        "к",
        north = "К",
        northwest = "κ", -- Greek kappa
        west = "ķ",
    },
    _Л_ = {
        "Л",
        north = "л",
        northeast = "Ĺ",
        northwest = "Ľ",
        west = "Ł",
        south = "Ļ",
        southeast = "Λ", -- Greek lambda
        southwest = "ꝉ", -- abbreviation for vel (Latin or)
        east = "ɫ", -- dark l, velarized alveolar lateral approximant IPA
    },
    _л_ = {
        "л",
        north = "Л",
        northeast = "ĺ",
        northwest = "ľ",
        west = "ł",
        south = "ļ",
        southeast = "λ", -- Greek lambda
        southwest = "ꝉ", -- abbreviation for vel (Latin or)
        east = "ɫ", -- dark l, velarized alveolar lateral approximant IPA
    },
    _Љ_ = {
        "Љ",
        north = "љ",
        northeast = "LJ",
        northwest = "Lj",
        west = "lj",
    },
    _љ_ = {
        "љ",
        north = "Љ",
        northeast = "LJ",
        northwest = "Lj",
        west = "lj",
    },
    _М_ = {
        "М",
        north = "м",
        northeast = "Μ", -- Greek mu
        east = "ɱ", -- labiodental nasal IPA
    },
    _м_ = {
        "м",
        north = "М",
        northeast = "μ", -- Greek mu
        east = "ɱ", -- labiodental nasal IPA
    },
    _Н_ = {
        "Н",
        north = "н",
        northeast = "Ń",
        northwest = "Ǹ",
        east = "ɲ", -- palatal nasal IPA
        west = "Ñ",
        south = "Ņ",
        southeast = "Ŋ", -- uppercase letter eng (ligature of N and G)
        southwest = "Ν", -- Greek nu
        "Ň", -- Czech
    },
    _н_ = {
        "н",
        north = "Н",
        northeast = "ń",
        northwest = "ǹ",
        east = "ɲ", -- palatal nasal IPA
        west = "ñ",
        south = "ņ",
        southeast = "ŋ", -- letter eng (ligature of N and G), velar nasal IPA
        southwest = "ν", -- Greek nu
        "ň", -- Czech
    },
    _Њ_ = {
        "Њ",
        north = "њ",
        northeast = "NJ",
        northwest = "Nj",
        west = "nj",
    },
    _њ_ = {
        "њ",
        north = "Њ",
        northeast = "NJ",
        northwest = "Nj",
        west = "nj",
    },
    _О_ = {
        "О",
        north = "о",
        northeast = "Ó",
        northwest = "Ò",
        east = "Ô",
        west = "Õ",
        south = "Ǫ",
        southeast = "Ö",
        southwest = "Ø",
        "Ō",
        "ɔ", -- open o, open-mid back rounded vowel IPA
        "Œ",
    },
    _о_ = {
        "о",
        north = "О",
        northeast = "ó",
        northwest = "ò",
        east = "ô",
        west = "õ",
        south = "ǫ",
        southeast = "ö",
        southwest = "ø",
        "ō",
        "ɔ", -- open o, open-mid back rounded vowel IPA
        "œ",
    },
    _П_ = {
        "П",
        north = "п",
        northwest = "Π", -- Greek pi
        west = "§", -- section sign
        south = "℗",
        southwest = "£", -- British pound currency
        "Φ", -- Greek phi
        "Ψ", -- Greek psi
    },
    _п_ = {
        "п",
        north = "П",
        northwest = "π", -- Greek pi
        west = "¶", -- pilcrow (paragraph) sign
        south = "℗",
        southwest = "£", -- British pound currency
        "φ", -- Greek phi
        "ψ", -- Greek psi
    },
    _Р_ = {
        "Р",
        north = "р",
        northeast = "Ŕ",
        northwest = "® ",
        east = "Ř", -- alveolar flap or tap IPA
        west = "ɾ", -- r with háček (Czech)
        south = "Ŗ", -- r cedilla (Latvian)
        southeast = "ɻ", -- retroflex approximant IPA
        southwest = "ɹ", -- alveolar approximant IPA
        "ʀ", -- uvular trill IPA
        "ʁ", -- voiced uvular fricative IPA
        "₽", -- Russian ruble
    },
    _р_ = {
        "р",
        north = "Р",
        northeast = "ŕ",
        northwest = "® ",
        east = "ř", -- alveolar flap or tap IPA
        west = "ɾ", -- r with háček (Czech)
        south = "ŗ", -- r cedilla (Latvian)
        southeast = "ɻ", -- retroflex approximant IPA
        southwest = "ɹ", -- alveolar approximant IPA
        "ʀ", -- uvular trill IPA
        "ʁ",
        "₽", -- Russian ruble currency
    },
    _С_ = {
        "С",
        north = "с",
        northeast = "Ś",
        northwest = "ʃ", -- esh, voiceless palato-alveolar fricative IPA
        east = "Ŝ",
        west = "Š",
        south = "Ş",
        southeast = "ẞ", -- German eszett uppercase
        southwest = "Ṣ",
        "℠",
        "ſ", -- long s
        "Σ", -- Greek sigma
    },
    _с_ = {
        "с",
        north = "С",
        northeast = "ś",
        northwest = "ʃ", -- esh, voiceless palato-alveolar fricative IPA
        east = "ŝ",
        west = "š",
        south = "ş",
        southeast = "ß", -- German eszett
        southwest = "ṣ",
        "℠",
        "ſ", -- long s
        "σ", -- Greek sigma (beginning or the middle of the word)
    },
    _Т_ = {
        "Т",
        north = "т",
        northeast = "Þ",
        northwest = "Ț",
        east = "Ʈ",
        west = "Ť",
        south = "Ţ",
        southeast = "™",
        southwest = "Ṭ",
        "₸", -- Kazakhstani tenge currency
        "Θ", -- Greek theta
        "Τ", -- Greek tau
    },
    _т_ = {
        "т",
        north = "Т",
        northeast = "þ",
        northwest = "ț",
        east = "ʈ",
        west = "ť",
        south = "ţ",
        southeast = "™",
        southwest = "ṭ",
        "₸", -- Kazakhstani tenge currency
        "θ", -- Greek theta
        "τ", -- Greek tau
    },
    _Ћ_ = {
        "Ћ",
        north = "ћ",
        northeast = "Ć",
        west = "ć",
    },
    _ћ_ = {
        "ћ",
        north = "Ћ",
        northeast = "Ć",
        west = "ć",
    },
    _У_ = {
        "У",
        north = "у",
        northeast = "Ú",
        northwest = "Ù",
        east = "Û",
        west = "Ũ",
        south = "Ų",
        southeast = "Ü",
        southwest = "Ů",
        "Ū",
        "ɒ", -- turned alpha, open back rounded vowel IPA
        "Ŭ", -- U with breve from Belarusan Latin alphabet
    },
    _у_ = {
        "у",
        north = "У",
        northeast = "ú",
        northwest = "ù",
        east = "û",
        west = "ũ",
        south = "ų",
        southeast = "ü",
        southwest = "ů",
        "ū",
        "ɒ", -- turned alpha, open back rounded vowel IPA
        "ŭ", -- u with breve from Belarusan Latin alphabet
    },
    _Ф_ = {
        "Ф",
        north = "ф",
        east = "ƒ", -- Guilder/Florin
    },
    _ф_ = {
        "ф",
        north = "Ф",
        east = "ƒ", -- Guilder/Florin
    },
    _Х_ = {
        "Х",
        north = "х",
        east = "ɥ", -- labialized palatal approximant (like a combination between /w/ and /y/)
    },
    _х_ = {
        "х",
        north = "Х",
        east = "ɥ", -- labialized palatal approximant (like a combination between /w/ and /y/)
    },
    _Ц_ = {
        "Ц",
        north = "ц",
        northeast = "Ć",
        northwest = "🄯", -- copyleft symbol
        east = "Ĉ",
        west = "Č",
        south = "Ç",
        southeast = "©", -- copyright symbol
        southwest = "Ċ", -- cent sign
        "¢",
    },
    _ц_ = {
        "ц",
        north = "Ц",
        northeast = "ć",
        northwest = "🄯", -- copyleft symbol
        east = "ĉ",
        west = "č",
        south = "ç",
        southeast = "©", -- copyright symbol
        southwest = "ċ", -- cent sign
        "¢",
    },
    _Ч_ = {
        "Ч",
        north = "ч",
        northeast = "Č",
        west = "č",
    },
    _ч_ = {
        "ч",
        north = "Ч",
        northeast = "Č",
        west = "č",
    },
    _Џ_ = {
        "Џ",
        north = "џ",
        northeast = "DŽ",
        northwest = "Dž",
        west = "dž",
    },
    _џ_ = {
        "џ",
        north = "Џ",
        northeast = "DŽ",
        northwest = "Dž",
        west = "dž",
    },
    _Ш_ = {
        "Ш",
        north = "ш",
        northeast = "Š",
        west = "š",
    },
    _ш_ = {
        "ш",
        north = "Ш",
        northeast = "Š",
        west = "š",
    },
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
  bul = { "·", north = "•", alt_label = "•", }, -- bullet and middle dot
  bu2 = { "•", north = "·", alt_label = "·", }, -- (popup sibling)
  cl1 = { "♠", north = "♣", alt_label = "♣", }, -- spade and club
  cl2 = { "♣", north = "♠", alt_label = "♠", }, -- (popup sibling)
  cl3 = { "♡", north = "♢", alt_label = "♢", }, -- heart and diamond
  cl4 = { "♢", north = "♡", alt_label = "♡", }, -- (popup sibling)
}
