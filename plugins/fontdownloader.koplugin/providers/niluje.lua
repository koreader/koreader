local FontRepo = require "fontrepo"

local repo = FontRepo:new{
    id = "NiLuJe fonts",
    url = "local",
}

local fonts = {
    -- http://trac.ak-team.com/trac/browser/niluje/Configs/trunk/Kindle/Kobo_Hacks/Patches/REMINDER#L125
    ["Lit3rata"] = {
        format = "otf",
        version = "Mangled Literata 3",
        lastModified = "2020-06-22",
        category = "serif",
        subsets = {
            "cyrillic",
            "greek",
            "greek-ext",
            "latin",
            "latin-ext",
            "vietnamese",
        },
        variants = {
            "regular",
            "italic",
            "700",
            "700italic",
        },
        files = {
            ["regular"] = "https://storage.sbg.cloud.ovh.net/v1/AUTH_2ac4bfee353948ec8ea7fd1710574097/koreader-pub/Lit3rata-Regular.otf",
            ["italic"] = "https://storage.sbg.cloud.ovh.net/v1/AUTH_2ac4bfee353948ec8ea7fd1710574097/koreader-pub/Lit3rata-Italic.otf",
            ["700" ] = "https://storage.sbg.cloud.ovh.net/v1/AUTH_2ac4bfee353948ec8ea7fd1710574097/koreader-pub/Lit3rata-Bold.otf",
            ["700italic"] = "https://storage.sbg.cloud.ovh.net/v1/AUTH_2ac4bfee353948ec8ea7fd1710574097/koreader-pub/Lit3rata-BoldItalic.otf",
        },
    },
}

function repo:fontTable()
    local t = {}
    for key, value in pairs(fonts) do
        local font = value
        font.family = key
        table.insert(t, #t + 1, font)
    end
    return t
end

return repo
