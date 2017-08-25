local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local Wikipedia = require("ui/wikipedia")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

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
                    text = _("Search Wikipedia"),
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

function ReaderWikipedia:addToMainMenu(menu_items)
    menu_items.wikipedia_lookup =  {
        text = _("Wikipedia lookup"),
        callback = function()
            if NetworkMgr:isOnline() then
                self:lookupInput()
            else
                NetworkMgr:promptWifiOn()
            end
        end
    }
    menu_items.wikipedia_settings = {
        text = _("Wikipedia settings"),
        sub_item_table = {
            {
                text = _("Set Wikipedia languages"),
                callback = function()
                    local wikilang_input
                    local function save_wikilang()
                        local wiki_languages = {}
                        local langs = wikilang_input:getInputText()
                        for lang in langs:gmatch("%S+") do
                            if not lang:match("^[%a-]+$") then
                                UIManager:show(InfoMessage:new{
                                    text = T(_("%1 does not look like a valid Wikipedia language."), lang)
                                })
                                return
                            end
                            lang = lang:lower()
                            table.insert(wiki_languages, lang)
                        end
                        G_reader_settings:saveSetting("wikipedia_languages", wiki_languages)
                        -- re-init languages
                        self.wiki_languages = {}
                        self:initLanguages()
                        UIManager:close(wikilang_input)
                    end
                    -- Use the list built by initLanguages (even if made from UI
                    -- and document languages) as the initial value
                    self:initLanguages()
                    local curr_languages = table.concat(self.wiki_languages, " ")
                    wikilang_input = InputDialog:new{
                        title = _("Wikipedia languages"),
                        input = curr_languages,
                        input_hint = "en fr zh",
                        input_type = "text",
                        description = _("Enter one or more Wikipedia language codes (the 2 or 3 letters before .wikipedia.org), in the order you wish to see them available, separated by space(s) (example: en fr zh)\nFull list at https://en.wikipedia.org/wiki/List_of_Wikipedias"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(wikilang_input)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = save_wikilang,
                                },
                            }
                        },
                    }
                    wikilang_input:onShowKeyboard()
                    UIManager:show(wikilang_input)
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Set Wikipedia 'Save as EPUB' directory"),
                callback = function()
                    local folder_path_input
                    local function save_folder_path()
                        local folder_path = folder_path_input:getInputText()
                        folder_path = folder_path:gsub("^%s*(.-)%s*$", "%1") -- trim spaces
                        folder_path = folder_path:gsub("^(.-)/*$", "%1") -- remove trailing slash
                        if folder_path == "" then
                            G_reader_settings:delSetting("wikipedia_save_dir", folder_path)
                        else
                            if lfs.attributes(folder_path, "mode") == "directory" then -- existing directory
                                G_reader_settings:saveSetting("wikipedia_save_dir", folder_path)
                            elseif lfs.attributes(folder_path) then -- already exists, but not a directory
                                UIManager:show(InfoMessage:new{
                                    text = _("A path with that name already exists, but is not a directory.")
                                })
                                return
                            else -- non-existing path, we may create it
                                local parent_dir, sub_dir = util.splitFilePathName(folder_path) -- luacheck: no unused
                                if lfs.attributes(parent_dir, "mode") == "directory" then -- existing directory
                                    lfs.mkdir(folder_path)
                                    if lfs.attributes(folder_path, "mode") == "directory" then -- existing directory
                                        G_reader_settings:saveSetting("wikipedia_save_dir", folder_path)
                                        UIManager:show(InfoMessage:new{
                                            text = _("Directory created."),
                                        })
                                    else
                                        UIManager:show(InfoMessage:new{
                                            text = _("Creating directory failed.")
                                        })
                                        return
                                    end
                                else
                                    -- We don't create more than one directory, in case of bad input
                                    UIManager:show(InfoMessage:new{
                                        text = _("Parent directory does not exist. Please create intermediate directories first.")
                                    })
                                    return
                                end
                            end
                        end
                        UIManager:close(folder_path_input)
                    end
                    -- for initial value, use the same logic as in dictquicklookup to decide save directory
                    -- suggest to use a "Wikipedia" sub-directory of some directories
                    local default_dir = require("apps/filemanager/filemanagerutil").getDefaultDir()
                    default_dir = default_dir .. "/Wikipedia"
                    local dir = G_reader_settings:readSetting("wikipedia_save_dir")
                    if not dir then
                        dir = G_reader_settings:readSetting("home_dir")
                        if not dir then dir = default_dir end
                        dir = dir:gsub("^(.-)/*$", "%1") -- remove trailing slash
                        dir = dir .. "/Wikipedia"
                    end
                    folder_path_input = InputDialog:new{
                        title = _("Wikipedia 'Save as EPUB' directory"),
                        input = dir,
                        input_hint = default_dir,
                        input_type = "text",
                        description = _("Enter the full path to a directory"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    callback = function()
                                        UIManager:close(folder_path_input)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = save_folder_path,
                                },
                            }
                        },
                    }
                    folder_path_input:onShowKeyboard()
                    UIManager:show(folder_path_input)
                end,
            }
        }
    }
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
        if self.view then
            addLanguage(self.view.document:getProps().language)
        end
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
    self:showLookupInfo(word)
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
    self:showDict(word, results, box)
end

-- override onSaveSettings in ReaderDictionary
function ReaderWikipedia:onSaveSettings()
end

return ReaderWikipedia
