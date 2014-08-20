local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local EventListener = require("ui/widget/eventlistener")
local Translator = require("ui/translator")
local Wikipedia = require("ui/wikipedia")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local JSON = require("JSON")
local DEBUG = require("dbg")
local _ = require("gettext")

-- Wikipedia as a special dictionary
local ReaderWikipedia = ReaderDictionary:new{
    -- identify itself
    wiki = true,
    no_page = _("No wiki page found."),
}

function ReaderWikipedia:onLookupWikipedia(word, box)
    local lang = Translator:detect(word) or "en"
    -- convert "zh-CN" and "zh-TW" to "zh"
    lang = lang:match("(.*)-") or lang
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
        self:showDict(results, box)
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
        self:showDict(results, box)
    end
end

return ReaderWikipedia
