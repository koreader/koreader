local _ = require("gettext")

-- largely thanks to https://tuxor1337.github.io/firedict/dictionaries.html
local dictionaries = {
    {
        name = "CIA World Factbook 2014",
        lang_in = "English",
        lang_out = "English",
        entries = 2577,
        license = _("Public Domain"),
        url = "http://build.koreader.rocks/download/dict/factbook.tar.lz",
    },
    {
        name = "GNU Collaborative International Dictionary of English",
        lang_in = "English",
        lang_out = "English",
        entries = 108121,
        license = "GPLv3+",
        url = "http://build.koreader.rocks/download/dict/gcide.tar.lz",
    },
    {
        name = "Douglas Harper's Online Etymology Dictionary",
        lang_in = "English",
        lang_out = "English",
        entries = 46133,
        license = "Unknown/©Douglas Harper",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/1f3a66fe3f776e718590a66958df1b9b/etymonline.tar.lz",
    },
    {
        name = "Folkets lexikon",
        lang_in = "English",
        lang_out = "Swedish",
        entries = 53618,
        license = "CC-BY-SA 2.5",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/fad990cc29c6dd448f22469ce8648825/folkets_en-sv.tar.lz",
    },
    {
        name = "Folkets lexikon",
        lang_in = "Swedish",
        lang_out = "English",
        entries = 36513,
        license = "CC-BY-SA 2.5",
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/fdc4265bbfc9af27fa4b1742ce3bdadd/folkets_sv-en.tar.lz",
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
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/a8b3027e84f344f64723fb7fe5c63c04/acadfran.tar.lz",
    },
    {
        name = "Pape: Handwörterbuch der griechischen Sprache",
        lang_in = "Ancient Greek",
        lang_out = "German",
        entries = 98893,
        license = _("Public Domain (copyright expired, published 1880)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/3ee9cb3acaca679bb9a95d845b813673/pape_gr-de.tar.lz",
    },
    {
        name = "Georges: Ausführliches lateinisch-deutsches Handwörterbuch",
        lang_in = "Latin",
        lang_out = "German",
        entries = 54831,
        license = _("Public Domain (copyright expired, published 1913)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/8d1e52d6c28d3b6865415979bc221fa6/georges_lat-de.tar.lz",
    },
    {
        name = "Georges: Kleines deutsch-lateinisches Handwörterbuch",
        lang_in = "German",
        lang_out = "Latin",
        entries = 26608,
        license = _("Public Domain (copyright expired, published 1910)"),
        url = "https://gitlab.com/koreader/stardict-dictionaries/uploads/a66b2a7655a4b102150fb5c6f1789cc5/georges_de-lat.tar.lz",
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
}

return dictionaries
