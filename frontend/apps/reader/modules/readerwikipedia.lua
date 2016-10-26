local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Translator = require("ui/translator")
local Wikipedia = require("ui/wikipedia")
local DEBUG = require("dbg")
local _ = require("gettext")

-- Wikipedia as a special dictionary
local ReaderWikipedia = ReaderDictionary:extend{
    -- identify itself
    wiki = true,
    no_page = _("No wiki page found."),
}

-- the super "class" ReaderDictionary has already registers a menu entry
-- we should override the init function in ReaderWikipedia
function ReaderWikipedia:init()
end

function ReaderWikipedia:onLookupWikipedia(word, box)
    -- set language from book properties
    local lang = self.view.document:getProps().language
    if lang == nil then
        -- or set laguage from KOReader settings
        lang = G_reader_settings:readSetting("language")
        if lang == nil then
            -- or detect language
            local ok_translator
            ok_translator, lang = pcall(Translator.detect, Translator, word)
            if not ok_translator then return end
        end
    end
    -- convert "zh-CN" and "zh-TW" to "zh"
    lang = lang:match("(.*)-") or lang
    -- strip punctuation characters around selected word
    word = string.gsub(word, "^%p+", '')
    word = string.gsub(word, "%p+$", '')
    -- seems lower case phrase has higher hit rate
    word = string.lower(word)
    local results = {}
    local ok, pages = pcall(Wikipedia.wikintro, Wikipedia, word, lang)
    if ok and pages then
        for pageid, page in pairs(pages) do
            local result = {
                dict = _("Wikipedia"),
                word = page.title,
                definition = page.extract or self.no_page,
            }
            table.insert(results, result)
        end
        DEBUG("lookup result:", word, results)
        self:showDict(word, results, box)
    else
        DEBUG("error:", pages)
        -- dummy results
        results = {
            {
                dict = _("Wikipedia"),
                word = word,
                definition = self.no_page,
            }
        }
        DEBUG("dummy result table:", word, results)
        self:showDict(word, results, box)
    end
end

-- override onSaveSettings in ReaderDictionary
function ReaderWikipedia:onSaveSettings()
end

return ReaderWikipedia
