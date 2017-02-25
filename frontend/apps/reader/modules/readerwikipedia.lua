local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Translator = require("ui/translator")
local Wikipedia = require("ui/wikipedia")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local NetworkMgr = require("ui/network/manager")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")

-- Wikipedia as a special dictionary
local ReaderWikipedia = ReaderDictionary:extend{
    -- identify itself
    is_wiki = true,
    wiki_languages = {},
    no_page = _("No wiki page found."),
}

function ReaderWikipedia:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderWikipedia:lookupInput()
    self.input_dialog = InputDialog:new{
        title = _("Enter words to look up on Wikipedia"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(self.input_dialog)
                        self:onLookupWikipedia(self.input_dialog:getInputText())
                    end,
                },
            }
        },
    }
    self.input_dialog:onShowKeyboard()
    UIManager:show(self.input_dialog)
end

function ReaderWikipedia:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.search, {
        text = _("Wikipedia lookup"),
        callback = function()
            if NetworkMgr:isOnline() then
                self:lookupInput()
            else
                NetworkMgr:promptWifiOn()
            end
        end
    })
end

function ReaderWikipedia:initLanguages(word)
    if #self.wiki_languages > 0 then -- already done
        return
    end
    -- Fill self.wiki_languages with languages to propose
    local wikipedia_languages = G_reader_settings:readSetting("wikipedia_languages")
    if type(wikipedia_languages) == "table" and #wikipedia_languages > 0 then
        -- use this setting, no need to guess
        self.wiki_languages = wikipedia_languages
    else
        -- guess some languages
        self.seen_lang = {}
        local addLanguage = function(lang)
            if lang and lang ~= "" then
                -- convert "zh-CN" and "zh-TW" to "zh"
                lang = lang:match("(.*)-") or lang
                if lang == "C" then lang="en" end
                lang = lang:lower()
                if not self.seen_lang[lang] then
                    table.insert(self.wiki_languages, lang)
                    self.seen_lang[lang] = true
                end
            end
        end
        -- use book and UI languages
        addLanguage(self.view.document:getProps().language)
        addLanguage(G_reader_settings:readSetting("language"))
        if #self.wiki_languages == 0 and word then
            -- if no language at all, do a translation of selected word
            local ok_translator, lang
            ok_translator, lang = pcall(Translator.detect, Translator, word)
            if ok_translator then
                addLanguage(lang)
            end
        end
        -- add english anyway, so we have at least one language
        addLanguage("en")
    end
end

function ReaderWikipedia:onLookupWikipedia(word, box, get_fullpage, forced_lang)
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
        return
    end
    -- word is the text to query. If get_fullpage is true, it is the
    -- exact wikipedia page title we want the full page of.
    self:initLanguages(word)
    local lang
    if forced_lang then
        -- use provided lang (from readerlink when noticing that an external link is a wikipedia url)
        lang = forced_lang
    else
        -- use first lang from self.wiki_languages, which may have been rotated by DictQuickLookup
        lang = self.wiki_languages[1]
    end
    logger.dbg("lookup word:", word, box, get_fullpage)
    -- no need to clean word if get_fullpage, as it is the exact wikipetia page title
    if word and not get_fullpage then
        -- escape quotes and other funny characters in word
        word = self:cleanSelection(word)
        -- no need to lower() word with wikipedia search
    end
    logger.dbg("stripped word:", word)
    if word == "" then
        return
    end

    -- Fix lookup message to include lang
    if get_fullpage then
        self.lookup_msg = T(_("Getting Wikipedia %2 page:\n%1"), "%1", lang:upper())
    else
        self.lookup_msg = T(_("Searching Wikipedia %2 for:\n%1"), "%1", lang:upper())
    end
    self:onLookupStarted(word)
    local results = {}
    local ok, pages
    if get_fullpage then
        ok, pages = pcall(Wikipedia.wikifull, Wikipedia, word, lang)
    else
        ok, pages = pcall(Wikipedia.wikintro, Wikipedia, word, lang)
    end
    if ok and pages then
        -- sort pages according to 'index' attribute if present (not present
        -- in fullpage results)
        local sorted_pages = {}
        local has_indexes = false
        for pageid, page in pairs(pages) do
            if page.index ~= nil then
                sorted_pages[page.index+1] = page
                has_indexes = true
            end
        end
        if has_indexes then
            pages = sorted_pages
        end
        for pageid, page in pairs(pages) do
            local definition = page.extract or self.no_page
            if page.length then
                -- we get 'length' only for intro results
                -- let's append it to definition so we know
                -- how big/valuable the full page is
                local fullkb = math.ceil(page.length/1024)
                local more_factor = math.ceil( page.length / (1+definition:len()) ) -- +1 just in case len()=0
                definition = definition .. "\n" .. T(_("(full page : %1 kB, = %2 x this intro length)"), fullkb, more_factor)
            end
            local result = {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = page.title,
                definition = definition,
                is_fullpage = get_fullpage,
                lang = lang,
            }
            table.insert(results, result)
        end
        logger.dbg("lookup result:", word, results)
    else
        logger.dbg("error:", pages)
        -- dummy results
        results = {
            {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = word,
                definition = self.no_page,
                is_fullpage = get_fullpage,
                lang = lang,
            }
        }
        logger.dbg("dummy result table:", word, results)
    end
    self:onLookupDone()
    self:showDict(word, results, box)
end

-- override onSaveSettings in ReaderDictionary
function ReaderWikipedia:onSaveSettings()
end

return ReaderWikipedia
