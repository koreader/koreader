local _ = require("gettext")

-- largely thanks to https://tuxor1337.github.io/firedict/dictionaries.html
local dictionaries = {
    {
        name = "CIA World Factbook 2014",
        lang_in = "English",
        lang_out = "English",
        entries = 2577,
        license = _("Public Domain"),
        url = "http://build.koreader.rocks/download/dict/factbook.tar.gz",
    },
    {
        name = "GNU Collaborative International Dictionary of English",
        lang_in = "English",
        lang_out = "English",
        entries = 108121,
        license = "GPLv3+",
        url = "http://build.koreader.rocks/download/dict/gcide.tar.gz",
    },
    {
        name = "Douglas Harper's Online Etymology Dictionary",
        lang_in = "English",
        lang_out = "English",
        entries = 46133,
        license = "Unknown/©Douglas Harper",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/ce281fd8b5e83751d5c7b82d1e07a663/etymonline.tar.gz",
    },
    {
        name = "Folkets lexikon",
        lang_in = "English",
        lang_out = "Swedish",
        entries = 53618,
        license = "CC-BY-SA 2.5",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/619cbab2537b4d115d5503cdd023ce05/folkets_en-sv.tar.gz",
    },
    {
        name = "Folkets lexikon",
        lang_in = "Swedish",
        lang_out = "English",
        entries = 36513,
        license = "CC-BY-SA 2.5",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/53a0a9fea8cab8661cf930ddd2353a4c/folkets_sv-en.tar.gz",
    },
    {
        name = "Dictionnaire Littré (xmlittre)",
        lang_in = "French",
        lang_out = "French",
        entries = 78428,
        license = "CC-BY-SA 3.0",
        url = "http://http.debian.net/debian/pool/main/s/stardict-xmlittre/stardict-xmlittre_1.0.orig.tar.gz",
    },
    {
        name = "Dictionnaire de l'Académie Française: 8ème edition",
        lang_in = "French",
        lang_out = "French",
        entries = 31934,
        license = _("Public Domain (copyright expired, published 1935)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/b8e8ba6b8941a78762675ff2ef95d1d1/acadfran.tar.gz",
    },
    {
        name = "Pape: Handwörterbuch der griechischen Sprache",
        lang_in = "Ancient Greek",
        lang_out = "German",
        entries = 98893,
        license = _("Public Domain (copyright expired, published 1880)"),
        url = "http://build.koreader.rocks/download/dict/pape_gr-de.tar.gz",
    },
    {
        name = "Georges: Ausführliches lateinisch-deutsches Handwörterbuch",
        lang_in = "Latin",
        lang_out = "German",
        entries = 54831,
        license = _("Public Domain (copyright expired, published 1913)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/6339585b68ac485bedb8ee67892cb974/georges_lat-de.tar.gz",
    },
    {
        name = "Georges: Kleines deutsch-lateinisches Handwörterbuch",
        lang_in = "German",
        lang_out = "Latin",
        entries = 26608,
        license = _("Public Domain (copyright expired, published 1910)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/a04de66c7376e436913ca288a3ca608b/georges_de-lat.tar.gz",
    },
    {
        name = "Dicionário Aberto",
        lang_in = "Portuguese",
        lang_out = "Portuguese",
        entries = 128521,
        license = _("CC-BY-SA 2.5"),
        url = "http://www.dicionario-aberto.net/stardict-DicAberto.tar.bz2",
    },
    {
        name = "GNU/FDL Anglicko/Český slovník",
        lang_in = "English",
        lang_out = "Czech",
        entries = 178904, -- ~90000 each way
        license = _("GNU/FDL"),
        url = "http://http.debian.net/debian/pool/non-free/s/stardict-english-czech/stardict-english-czech_20161201.orig.tar.gz",
    },
    {
        name = "GNU/FDL Anglicko/Český slovník",
        lang_in = "Czech",
        lang_out = "English",
        entries = 178904, -- ~90000 each way
        license = _("GNU/FDL"),
        url = "http://http.debian.net/debian/pool/non-free/s/stardict-english-czech/stardict-english-czech_20161201.orig.tar.gz",
    },
    {
        name = "GNU/FDL Německo/Český slovník",
        lang_in = "German",
        lang_out = "Czech",
        entries = 2341, -- ~1200 each way
        license = _("GNU/FDL"),
        url = "http://http.debian.net/debian/pool/non-free/s/stardict-german-czech/stardict-german-czech_20161201.orig.tar.gz",
    },
    {
        name = "GNU/FDL Německo/Český slovník",
        lang_in = "Czech",
        lang_out = "German",
        entries = 2341, -- ~1200 each way
        license = _("GNU/FDL"),
        url = "http://http.debian.net/debian/pool/non-free/s/stardict-german-czech/stardict-german-czech_20161201.orig.tar.gz",
    },
    -- Dictionaries mirrored from Sourceforge, see https://github.com/koreader/koreader/pull/3176#issuecomment-447085441
    {
        name = "Afrikaans-English dictionary",
        lang_in = "Afrikaans",
        lang_out = "English",
        entries = 4198,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_afrikaans-english-2.4.2.tar.gz"
    },
    {
        name = "Chinese-English dictionary",
        lang_in = "Chinese",
        lang_out = "English",
        entries = 26017,
        license = "from CEDICT http://www.mandarintools.com/cedict",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_chinese-eng-2.4.2.tar.gz"
    },
    {
        name = "Chinese-English dictionary",
        lang_in = "Chinese",
        lang_out = "English",
        entries = 26017,
        license = "from CEDICT http://www.mandarintools.com/cedict",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_sdict02_chinese-eng-2.4.2.tar.gz"
    },
    {
        name = "Computer Security (En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 12300,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_xn_secvoc_formatted_en-ru-2.4.2.tar.gz"
    },
    {
        name = "Construction Dictionary (En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 36936,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_xn_stroika_en-ru-2.4.2.tar.gz"
    },
    {
        name = "CyberLexicon(En-Es)",
        lang_in = "English",
        lang_out = "Spanish",
        entries = 861,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_cyber_lexicon_en-es-2.4.2.tar.gz"
    },
    {
        name = "Czech-Russian dictionary",
        lang_in = "Czech",
        lang_out = "Russian",
        entries = 9656,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_sdict02_czech-rus-2.4.2.tar.gz"
    },
    {
        name = "Danish-English dictionary",
        lang_in = "Danish",
        lang_out = "English",
        entries = 3323,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_danish-english-2.4.2.tar.gz"
    },
    {
        name = "Deutsch-Russian dictionary",
        lang_in = "Deutsch",
        lang_out = "Russian",
        entries = 12950,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/deutsch.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_deutsch_de-ru-2.4.2.tar.gz"
    },
    {
        name = "Dictionnaire des idées reçues, de Gustave Flaubert (1912).",
        lang_in = "French",
        lang_out = "French",
        entries = 960,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002e/stardict-user_hctr01_ideesrecues8-2.4.2.tar.gz"
    },
    {
        name = "Dutch monolingual dictionary",
        lang_in = "Dutch",
        lang_out = "Dutch",
        entries = 3194,
        license = "http://www.muiswerk.nl/WRDNBOEK/INHOUD.HTM",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_muiswerk-2.4.2.tar.gz"
    },
    {
        name = "Dutch-English dictionary",
        lang_in = "Dutch",
        lang_out = "English",
        entries = 18244,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_dutch-english-2.4.2.tar.gz"
    },
    {
        name = "Engligh Idioms (eng-eng)",
        lang_in = "English",
        lang_out = "English",
        entries = 8560,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_idioms_eng_eng-2.4.2.tar.gz"
    },
    {
        name = "Engligh Idioms (eng-rus)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 9739,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_idioms_eng_rus-2.4.2.tar.gz"
    },
    {
        name = "English explanatory dictionary (main)",
        lang_in = "English",
        lang_out = "English",
        entries = 45897,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_eng_main-2.4.2.tar.gz"
    },
    {
        name = "English explanatory dictionary (new words)",
        lang_in = "English",
        lang_out = "English",
        entries = 1159,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_eng_nw-2.4.2.tar.gz"
    },
    {
        name = "English-Arabic dictionary",
        lang_in = "English",
        lang_out = "Arabic",
        entries = 87423,
        license = "from www.arabeyes.org",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_arabic-2.4.2.tar.gz"
    },
    {
        name = "English-Belarusian Computer Dictionary",
        lang_in = "English",
        lang_out = "Belarusian",
        entries = 88,
        license = "http://mova.org",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_compbe-2.4.2.tar.gz"
    },
    {
        name = "English-Bulgarian computer dictionary",
        lang_in = "English",
        lang_out = "Bulgarian",
        entries = 523,
        license = "SA Dictionary, http://sa.dir.bg/sa.htm",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_bulg_comp-2.4.2.tar.gz"
    },
    {
        name = "English-Finnish dictionary",
        lang_in = "English",
        lang_out = "Finnish",
        entries = 17851,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_fin-2.4.2.tar.gz"
    },
    {
        name = "English-German dictionary",
        lang_in = "English",
        lang_out = "German",
        entries = 128707,
        license = "http://www.dict.cc/",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_English_German-2.4.2.tar.gz"
    },
    {
        name = "English-Hungarian dictionary",
        lang_in = "English",
        lang_out = "Hungarian",
        entries = 67262,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng-hung-2.4.2.tar.gz"
    },
    {
        name = "English-Russian business dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 12673,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_bus-2.4.2.tar.gz"
    },
    {
        name = "English-Russian computer dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 13163,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_comp-2.4.2.tar.gz"
    },
    {
        name = "English-Russian economic dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 14436,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_eco-2.4.2.tar.gz"
    },
    {
        name = "English-Russian full dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 526873,
        license = "GNU Public License.",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_full-2.4.2.tar.gz"
    },
    {
        name = "English-Russian short dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 46650,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_short-2.4.2.tar.gz"
    },
    {
        name = "English-Russian slang dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 850,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_rus_slang-2.4.2.tar.gz"
    },
    {
        name = "English-Serbian dictionary",
        lang_in = "English",
        lang_out = "Serbian",
        entries = 27546,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng_serb-2.4.2.tar.gz"
    },
    {
        name = "English-Spanish dictionary",
        lang_in = "English",
        lang_out = "Spanish",
        entries = 22527,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_eng-spa-2.4.2.tar.gz"
    },
    {
        name = "Esperanto-Russian dictionary",
        lang_in = "Esperanto",
        lang_out = "Russian",
        entries = 1378,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_Esperanto-Russian-2.4.2.tar.gz"
    },
    {
        name = "Estonian-Russian dictionary",
        lang_in = "Estonian",
        lang_out = "Russian",
        entries = 63825,
        license = "from ER-DICT: http://sourceforge.net/projects/er-dict",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_est-rus-2.4.2.tar.gz"
    },
    {
        name = "Finnish-English dictionary",
        lang_in = "Finnish",
        lang_out = "English",
        entries = 2063,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_finnish-english-2.4.2.tar.gz"
    },
    {
        name = "Finnish-English dictionary",
        lang_in = "Finnish",
        lang_out = "English",
        entries = 29180,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_fin_eng-2.4.2.tar.gz"
    },
    {
        name = "French-English dictionary",
        lang_in = "French",
        lang_out = "English",
        entries = 41398,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_french-english-2.4.2.tar.gz"
    },
    {
        name = "French-Hungarian dictionary",
        lang_in = "French",
        lang_out = "Hungarian",
        entries = 5473,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_fr_hung-2.4.2.tar.gz"
    },
    {
        name = "Geological English-Russian dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 2275,
        license = "ftp://Somewhere/geologe.zip",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_geology_en-ru-2.4.2.tar.gz"
    },
    {
        name = "Geological Russian-English dictionary",
        lang_in = "Russian",
        lang_out = "English",
        entries = 1951,
        license = "ftp://Somewhere/geologe.zip",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_geology_ru-en-2.4.2.tar.gz"
    },
    {
        name = "German-English dictionary",
        lang_in = "German",
        lang_out = "English",
        entries = 79276,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_german_english-2.4.2.tar.gz"
    },
    {
        name = "German-English dictionary",
        lang_in = "German",
        lang_out = "English",
        entries = 96743,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_ger_eng-2.4.2.tar.gz"
    },
    {
        name = "German-English dictionary",
        lang_in = "German",
        lang_out = "English",
        entries = 96803,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_german-english-2.4.2.tar.gz"
    },
    {
        name = "German-Hungarian dictionary",
        lang_in = "German",
        lang_out = "Hungarian",
        entries = 22092,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_ger_hung-2.4.2.tar.gz"
    },
    {
        name = "German-Russian dictionary",
        lang_in = "German",
        lang_out = "Russian",
        entries = 12802,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_german_rus-2.4.2.tar.gz"
    },
    {
        name = "German-Russian dictionary (2)",
        lang_in = "German",
        lang_out = "Russian",
        entries = 94047,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_german_rus2-2.4.2.tar.gz"
    },
    {
        name = "Glazunov(En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 15168,
        license = nil,
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dsl02_glazunov-2.4.2.tar.gz"
    },
    {
        name = "Grand dictionnaire de cuisine (1873)",
        lang_in = "French",
        lang_out = "French",
        entries = 2463,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002e/stardict-user_hctr01_dictionnaireCuisine38-2.4.2.tar.gz"
    },
    {
        name = "Hungarian-English Expressions dictionary",
        lang_in = "Hungarian",
        lang_out = "English",
        entries = 28215,
        license = "jDictionary project, http://jdictionary.info",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_hung_eng_expr-2.4.2.tar.gz"
    },
    {
        name = "Hungarian-English dictionary",
        lang_in = "Hungarian",
        lang_out = "English",
        entries = 131568,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_hungarian-english-2.4.2.tar.gz"
    },
    {
        name = "Islandsko-český slovník 1.3",
        lang_in = "Icelandic",
        lang_out = "Czech",
        entries = 4902,
        license = "http://www.hvalur.org",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002e/stardict-user_ales01_is_cz_dict-2.4.2.tar.gz"
    },
    {
        name = "Italian-English dictionary",
        lang_in = "Italian",
        lang_out = "English",
        entries = 12156,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_italian-english-2.4.2.tar.gz"
    },
    {
        name = "Japanese(Kanji)-English dictionary",
        lang_in = "Japanese",
        lang_out = "English",
        entries = 108472,
        license = "from http://ftp.cc.monash.edu.au/pub/nihongo/",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_jap-eng-2.4.2.tar.gz"
    },
    {
        name = "Latin-English dictionary",
        lang_in = "Latin",
        lang_out = "English",
        entries = 4453,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_latin-english-2.4.2.tar.gz"
    },
    {
        name = "Lingvo GSM E (En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 3996,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_lingvo_gsm_formatted_en-ru-2.4.2.tar.gz"
    },
    {
        name = "Mueller English-Russian Dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 45962,
        license = "http://www.chat.ru/~mueller_dic",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_mueller7-2.4.2.tar.gz"
    },
    {
        name = "Mueller English-Russian Dictionary (24th Edition)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 67066,
        license = "GPL (from http://mueller-dic.chat.ru/)",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_mueller24-2.4.2.tar.gz"
    },
    {
        name = "New Dictionary of Contemporary Informal English (Глазунов)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 15116,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_sdict02_eng_rus_glazunov-2.4.2.tar.gz"
    },
    {
        name = "Norwegian-English dictionary",
        lang_in = "Norwegian",
        lang_out = "English",
        entries = 8440,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_norwegian-english-2.4.2.tar.gz"
    },
    {
        name = "Portuguese-English dictionary",
        lang_in = "Portuguese",
        lang_out = "English",
        entries = 6106,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_portuguese-english-2.4.2.tar.gz"
    },
    {
        name = "Russian-Deutsch dictionary",
        lang_in = "Russian",
        lang_out = "Deutsch",
        entries = 12101,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/deutsch.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_deutsch_ru-de-2.4.2.tar.gz"
    },
    {
        name = "Russian-English full dictionary",
        lang_in = "Russian",
        lang_out = "English",
        entries = 372553,
        license = "GNU Public License.",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_rus_eng_full-2.4.2.tar.gz"
    },
    {
        name = "Russian-English short dictionary",
        lang_in = "Russian",
        lang_out = "English",
        entries = 69117,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_rus_eng_short-2.4.2.tar.gz"
    },
    {
        name = "Russian-German dictionary",
        lang_in = "Russian",
        lang_out = "German",
        entries = 32001,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_rus_ger-2.4.2.tar.gz"
    },
    {
        name = "Russian-Russian Big Encyclopaedic Dictionary",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 70769,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_rus_bigencdic-2.4.2.tar.gz"
    },
    {
        name = "Russian-Swedish dictionary",
        lang_in = "Russian",
        lang_out = "Swedish",
        entries = 9917,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/deutsch.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_swedish_ru-sv-2.4.2.tar.gz"
    },
    {
        name = "Security (En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 2216,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_Security_v8-2.4.2.tar.gz"
    },
    {
        name = "Sociology (En-Ru)",
        lang_in = "English",
        lang_out = "Russian",
        entries = 14688,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_xn_sociology_en-ru-2.4.2.tar.gz"
    },
    {
        name = "Spain-Russian Dictionary (Sadikov) dictionary",
        lang_in = "Spain",
        lang_out = "Russian",
        entries = 18534,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_sdict02_spa_rus_sadikov-2.4.2.tar.gz"
    },
    {
        name = "Spanish-English dictionary",
        lang_in = "Spanish",
        lang_out = "English",
        entries = 23670,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_spanish-english-2.4.2.tar.gz"
    },
    {
        name = "Suomen kielen perussanakirja (pieni versio)",
        lang_in = "Finnish",
        lang_out = "Finnish",
        entries = 93488,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_fifi_norm-2.4.2.tar.gz"
    },
    {
        name = "Suomen kielen perussanakirja (suuri versio)",
        lang_in = "Finnish",
        lang_out = "Finnish",
        entries = 695069,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_fifi_plus-2.4.2.tar.gz"
    },
    {
        name = "Swahili-English dictionary",
        lang_in = "Swahili",
        lang_out = "English",
        entries = 759,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_swahili-english-2.4.2.tar.gz"
    },
    {
        name = "Swedish-English dictionary",
        lang_in = "Swedish",
        lang_out = "English",
        entries = 30260,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_swedish-english-2.4.2.tar.gz"
    },
    {
        name = "Swedish-Russian dictionary",
        lang_in = "Swedish",
        lang_out = "Russian",
        entries = 10386,
        license = "ftp://ftp.dvo.ru/pub/dicts/src/schweden.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_swedish_sv-ru-2.4.2.tar.gz"
    },
    {
        name = "The Open English-Russian Computer Dictionary",
        lang_in = "English",
        lang_out = "Russian",
        entries = 1259,
        license = "http://www.chat.ru/~mueller_dic",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_engcom-2.4.2.tar.gz"
    },
    {
        name = "Tradeport Business Glossary (En)",
        lang_in = "English",
        lang_out = "English",
        entries = 2993,
        license = "Tradeport Business Glossary http://www.englspace.com/dl/details/dic_tradebusglossary.shtml",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002b/stardict-comn_dls03_tradeport_gloss_en-en-2.4.2.tar.gz"
    },
    {
        name = "U.S. Gazetteer (1990)",
        lang_in = "English",
        lang_out = "English",
        entries = 52991,
        license = "Public Domain",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_gazetteer-2.4.2.tar.gz"
    },
    {
        name = "Universal(Sp-Ru)",
        lang_in = "Spanish",
        lang_out = "Russian",
        entries = 19191,
        license = nil,
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dsl02_sadikov-2.4.2.tar.gz"
    },
    {
        name = "Universale(It-Ru)",
        lang_in = "Italian",
        lang_out = "Russian",
        entries = 64231,
        license = nil,
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dsl02_zorko-2.4.2.tar.gz"
    },
    {
        name = "WordNet (r) 1.7",
        lang_in = "English",
        lang_out = "English",
        entries = 136970,
        license = "http://www.cogsci.princeton.edu/~wn/",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_wn-2.4.2.tar.gz"
    },
    {
        name = "eng-rus_computer",
        lang_in = "English",
        lang_out = "Russian",
        entries = 5152,
        license = "GPL? See http://gambit.com.ru/~wolf/dic/ ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_eng-rus_computer-2.4.2.tar.gz"
    },
    {
        name = "eng-rus_math-alexandrov",
        lang_in = "English",
        lang_out = "Russian",
        entries = 2084,
        license = "GPL",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_eng-rus_math-alexandrov-2.4.2.tar.gz"
    },
    {
        name = "eng-rus_math_alexandrov",
        lang_in = "English",
        lang_out = "Russian",
        entries = 6912,
        license = "GPL",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_eng-rus_math_alexandrov-2.4.2.tar.gz"
    },
    {
        name = "eng-transcr_0107",
        lang_in = "English",
        lang_out = "Russian",
        entries = 45888,
        license = "Electronic Version by E.S.Cymbalyuk 1999 under GNU GPL, ver. 0.8",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_eng-transcr_0107-2.4.2.tar.gz"
    },
    {
        name = "korolew_enru",
        lang_in = "English",
        lang_out = "Russian",
        entries = 32791,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/korolew_enru.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_korolew_en-ru-2.4.2.tar.gz"
    },
    {
        name = "korolew_ru-en",
        lang_in = "Russian",
        lang_out = "English",
        entries = 31671,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/korolew_ruen.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_korolew_ru-en-2.4.2.tar.gz"
    },
    {
        name = "rus-eng_korolew",
        lang_in = "Russian",
        lang_out = "English",
        entries = 32366,
        license = "GPL? See http://gambit.com.ru/~wolf/dic/ ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-eng_korolew-2.4.2.tar.gz"
    },
    {
        name = "rus-rus_beslov",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 65372,
        license = "See translation for &lt;&lt;00-database-...&gt;&gt; ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-rus_beslov-2.4.2.tar.gz"
    },
    {
        name = "rus-rus_brok_efr",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 4893,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-rus_brok_efr-2.4.2.tar.gz"
    },
    {
        name = "rus-rus_ozhshv",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 38845,
        license = "See translation for &lt;&lt;00-database-...&gt;&gt; ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-rus_ozhshv-2.4.2.tar.gz"
    },
    {
        name = "rus-rus_ushakov",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 81573,
        license = "See translation for &lt;&lt;00-database-...&gt;&gt; ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-rus_ushakov-2.4.2.tar.gz"
    },
    {
        name = "rus-ukr_slovnyk",
        lang_in = "Russian",
        lang_out = "Ukrainian",
        entries = 458787,
        license = "See translation for &lt;&lt;00-database-...&gt;&gt; ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_rus-ukr_slovnyk-2.4.2.tar.gz"
    },
    {
        name = "sinyagin_general_er",
        lang_in = "English",
        lang_out = "Russian",
        entries = 17303,
        license = "http://sinyagin.pp.ru/engrus-mirrors.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_sinyagin_general_er-2.4.2.tar.gz"
    },
    {
        name = "sinyagin_general_re",
        lang_in = "Russian",
        lang_out = "English",
        entries = 20357,
        license = "http://sinyagin.pp.ru/engrus-mirrors.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_sinyagin_general_re-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_be-en",
        lang_in = "Belarusian",
        lang_out = "English",
        entries = 4967,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_be-en-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_be-pl",
        lang_in = "Belarusian",
        lang_out = "Polish",
        entries = 1344,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_be-pl-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_be-ru",
        lang_in = "Belarusian",
        lang_out = "Russian",
        entries = 7738,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_be-ru-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_be-uk",
        lang_in = "Belarusian",
        lang_out = "Ukrainian",
        entries = 6826,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_be-uk-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_en-be",
        lang_in = "English",
        lang_out = "Belarusian",
        entries = 10866,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_en-be-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_en-pl",
        lang_in = "English",
        lang_out = "Polish",
        entries = 15420,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_en-pl-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_en-ru",
        lang_in = "English",
        lang_out = "Russian",
        entries = 57508,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_en-ru-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_en-uk",
        lang_in = "English",
        lang_out = "Ukrainian",
        entries = 62785,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_en-uk-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_pl-be",
        lang_in = "Polish",
        lang_out = "Belarusian",
        entries = 3532,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_pl-be-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_pl-en",
        lang_in = "Polish",
        lang_out = "English",
        entries = 20084,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_pl-en-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_pl-ru",
        lang_in = "Polish",
        lang_out = "Russian",
        entries = 12789,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_pl-ru-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_pl-uk",
        lang_in = "Polish",
        lang_out = "Ukrainian",
        entries = 17430,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_pl-uk-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_ru-be",
        lang_in = "Russian",
        lang_out = "Belarusian",
        entries = 12524,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_ru-be-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_ru-en",
        lang_in = "Russian",
        lang_out = "English",
        entries = 55815,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_ru-en-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_ru-pl",
        lang_in = "Russian",
        lang_out = "Polish",
        entries = 15488,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_ru-pl-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_ru-uk",
        lang_in = "Russian",
        lang_out = "Ukrainian",
        entries = 458782,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_ru-uk-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_uk-be",
        lang_in = "Ukrainian",
        lang_out = "Belarusian",
        entries = 11864,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_uk-be-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_uk-en",
        lang_in = "Ukrainian",
        lang_out = "English",
        entries = 53938,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_uk-en-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_uk-pl",
        lang_in = "Ukrainian",
        lang_out = "Polish",
        entries = 16734,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_uk-pl-2.4.2.tar.gz"
    },
    {
        name = "slovnyk_uk-ru",
        lang_in = "Ukrainian",
        lang_out = "Russian",
        entries = 440072,
        license = "http://www.slovnyk.org/prg/gszotar/index.html",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_slovnyk_uk-ru-2.4.2.tar.gz"
    },
    {
        name = "sokrat_enru",
        lang_in = "English",
        lang_out = "Russian",
        entries = 55823,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/sokrat_enru.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_sokrat_en-ru-2.4.2.tar.gz"
    },
    {
        name = "sokrat_ruen",
        lang_in = "Russian",
        lang_out = "English",
        entries = 49856,
        license = "ftp://ftp.ifmo.ru/unix/unix-soft/utils/dictionaries/slowo/dicts/sokrat_ruen.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_sokrat_ru-en-2.4.2.tar.gz"
    },
    {
        name = "ukr-rus_slovnyk",
        lang_in = "Ukrainian",
        lang_out = "Russian",
        entries = 440077,
        license = "See translation for &lt;&lt;00-database-...&gt;&gt; ",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-atla02_ukr-rus_slovnyk-2.4.2.tar.gz"
    },
    {
        name = "Белорусско-русский словарь",
        lang_in = "Belarusian",
        lang_out = "Russian",
        entries = 52010,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_BelRusVorvul-2.4.2.tar.gz"
    },
    {
        name = "Большая Советская Энциклопедия",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 95058,
        license = "GNU Public License",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_rus_bse-2.4.2.tar.gz"
    },
    {
        name = "Большой Энциклопедический Словарь",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 65390,
        license = "ftp://ftp.spez.kharkov.ua/pub/fileecho/book/beslov01.ha ftp://ftp.spez.kharkov.ua/pub/fileecho/book/beslov02.ha",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_beslov-2.4.2.tar.gz"
    },
    {
        name = "Большой Юридический словарь",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 6800,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_rus_big_jurid-2.4.2.tar.gz"
    },
    {
        name = "Латинско-русский словарь",
        lang_in = "Latin",
        lang_out = "Russian",
        entries = 7812,
        license = "http://ornemus.da.ru/",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_latrus-2.4.2.tar.gz"
    },
    {
        name = "Медицинский словарь",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 1191,
        license = "http://users.i.com.ua/~viorell/meddic.rar",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_meddict-2.4.2.tar.gz"
    },
    {
        name = "Новый Большой англо-русский словарь",
        lang_in = "English",
        lang_out = "Russian",
        entries = 109600,
        license = "http://transmagus-dic.chat.ru/magus.tgz",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_magus-2.4.2.tar.gz"
    },
    {
        name = "Русско-Белорусский математический словарь",
        lang_in = "Russian",
        lang_out = "Belarusian",
        entries = 2366,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_RusBelMath-2.4.2.tar.gz"
    },
    {
        name = "Русско-Белорусский универсальный словарь",
        lang_in = "Russian",
        lang_out = "Belarusian",
        entries = 106449,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_RusBelUniversal-2.4.2.tar.gz"
    },
    {
        name = "Русско-Белорусский физико-математический словарь",
        lang_in = "Russian",
        lang_out = "Belarusian",
        entries = 18496,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002d/stardict-comn_sdict_axm05_RusBelFizmat-2.4.2.tar.gz"
    },
    {
        name = "Русско-английский словарь идиом",
        lang_in = "Russian",
        lang_out = "English",
        entries = 682,
        license = "http://www.lingvo.ru/upload//contents/336/idioms.zip",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_idioms-2.4.2.tar.gz"
    },
    {
        name = "Словарь Ефремовой",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 135598,
        license = "Converted from ftp://files.zipsites.ru/slovari/ by swaj",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_sdict02_ru_efremova-2.4.2.tar.gz"
    },
    {
        name = "Толковый словарь Ожегова",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 38832,
        license = "http://speakrus.narod.ru/zaliznyak/ozhegovw.zip",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_ozhegov-2.4.2.tar.gz"
    },
    {
        name = "Толковый словарь Ушакова",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 81261,
        license = "http://ushdict.narod.ru/archive/ushak1.zip http://ushdict.narod.ru/archive/ushak2.zip",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_ushakov-2.4.2.tar.gz"
    },
    {
        name = "Толковый словарь живого великорусского языка",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 43992,
        license = "http://www.booksite.ru/fulltext/RUSSIAN/DICTION/DALF.RAR",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/001/stardict-comn_dictd03_dalf-2.4.2.tar.gz"
    },
    {
        name = "Энциклопедический словарь / Брокгауз Ф.А. Ефрон И.А.",
        lang_in = "Russian",
        lang_out = "Russian",
        entries = 120237,
        license = "",
        url = "https://gitlab.com/avsej/dicts-stardict-form-xdxf/raw/d636cc5e8d4a47e22ac7466f4af6d435a8a3f650/002c/stardict-comn_sdict05_brokg-2.4.2.tar.gz"
    },
}

return dictionaries
