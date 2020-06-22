local Featured = {
    -- recommended fonts, both from gfonts and custom repos
    fonts = {
	"Bitter",
        "Crimson Text",
        "Gentium Book Basic",
        "Ibarra Real Nova",
        "Literata",
        "Merriweather",
        "Source Serif Pro",
    },

    -- we'll use custom versions of the following font families:
    own_fonts = {
	-- NiLuJe build of Literata 3 goes here
        ["Literata"] = {
            family = "Literata",
            version = "custom description here",
            lastModified = "2020-04-21",
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
                "500italic",
            },
            files = {
                ["regular"] = "http://some.site.com/regular.ttf",
                ["500italic"] = "http://some.site.com/mediumitalic.ttf",
            },
        }
    }
}


function Featured:getFonts(t)
    local featured_ok = {}
    for _, family in ipairs(self.fonts) do
        -- use our own info first, if available
        local own_info = self.own_fonts[family]
        if type(own_info) == "table" then
            table.insert(featured_ok, #featured_ok + 1, own_info)
        else
            -- check against google
            for __, font in ipairs(t) do
                if font.family == family then
                    table.insert(featured_ok, #featured_ok + 1, font)
                end
            end
        end
    end
    return featured_ok
end

return Featured
