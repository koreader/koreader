local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Trapper = require("ui/trapper")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local Wikipedia = require("ui/wikipedia")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local wikipedia_history = nil

-- Wikipedia as a special dictionary
local ReaderWikipedia = ReaderDictionary:extend{
    -- identify itself
    is_wiki = true,
    wiki_languages = {},
    disable_history = G_reader_settings:isTrue("wikipedia_disable_history"),
}

function ReaderWikipedia:init()
    self.ui.menu:registerToMainMenu(self)
    if not wikipedia_history then
        wikipedia_history = LuaData:open(DataStorage:getSettingsDir() .. "/wikipedia_history.lua", { name = "WikipediaHistory" })
    end
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
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
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
    menu_items.wikipedia_history = {
        text = _("Wikipedia history"),
        enabled_func = function()
            return wikipedia_history:has("wikipedia_history")
        end,
        callback = function()
            local wikipedia_history_table = wikipedia_history:readSetting("wikipedia_history")
            local kv_pairs = {}
            local previous_title
            self:initLanguages() -- so current lang is set
            for i = #wikipedia_history_table, 1, -1 do
                local value = wikipedia_history_table[i]
                if value.book_title ~= previous_title then
                    table.insert(kv_pairs, { value.book_title..":", "" })
                end
                previous_title = value.book_title
                local type_s = "▱ " -- lookup: small white parallelogram
                if value.page then
                    type_s = "▤ " -- full page: large square with lines
                end
                local lang_s = ""
                if value.lang ~= self.wiki_languages[1]:lower() then
                    -- We show item's lang only when different from current lang
                    lang_s = " ["..value.lang:upper().."]"
                end
                local text = type_s .. value.word .. lang_s
                table.insert(kv_pairs, {
                    os.date("%Y-%m-%d %H:%M:%S", value.time),
                    text,
                    callback = function()
                        self:onLookupWikipedia(value.word, nil, value.page, value.lang)
                    end
                })
            end
            UIManager:show(KeyValuePage:new{
                title = _("Wikipedia history"),
                kv_pairs = kv_pairs,
            })
        end,
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
                        description = _("Enter one or more Wikipedia language codes (the 2 or 3 letters before .wikipedia.org), in the order you wish to see them available, separated by a space. For example:\n    en fr zh\n\nFull list at https://en.wikipedia.org/wiki/List_of_Wikipedias"),
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
                    UIManager:show(wikilang_input)
                    wikilang_input:onShowKeyboard()
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Set Wikipedia 'Save as EPUB' directory"),
                callback = function()
                    local choose_directory = function()
                        -- Default directory as chosen by DictQuickLookup
                        local default_dir = G_reader_settings:readSetting("wikipedia_save_dir")
                        if not default_dir then default_dir = G_reader_settings:readSetting("home_dir") end
                        if not default_dir then default_dir = require("apps/filemanager/filemanagerutil").getDefaultDir() end
                        local dialog
                        dialog = ButtonDialogTitle:new{
                            title = T(_("Current Wikipedia 'Save as EPUB' directory:\n\n%1\n"), default_dir),
                            buttons = {
                                {
                                    {
                                        text = "Keep this directory",
                                        callback = function()
                                            UIManager:close(dialog)
                                        end,
                                    },
                                },
                                {
                                    {
                                    text = _("Change (select directory by long-pressing)"),
                                    callback = function()
                                        UIManager:close(dialog)
                                        -- Use currently read book's directory as starting point,
                                        -- so a user reading a wikipedia article can quickly select
                                        -- it to save related new articles in the same directory
                                        local dir = G_reader_settings:readSetting("wikipedia_save_dir")
                                        if not dir then dir = G_reader_settings:readSetting("home_dir") end
                                        if not dir then dir = require("apps/filemanager/filemanagerutil").getDefaultDir() end
                                        if not dir then dir = "/" end
                                        -- If this directory has no subdirectory, we would be displaying
                                        -- a single "..", so use parent directory in that case.
                                        local has_subdirectory = false
                                        for f in lfs.dir(dir) do
                                            local attributes = lfs.attributes(dir.."/"..f)
                                            if attributes and attributes.mode == "directory" then
                                                if f ~= "." and f ~= ".." and f:sub(-4) ~= ".sdr"then
                                                    has_subdirectory = true
                                                    break
                                                end
                                            end
                                        end
                                        if not has_subdirectory then
                                            dir = dir:match("(.*)/")
                                        end
                                        local PathChooser = require("ui/widget/pathchooser")
                                        local path_chooser = PathChooser:new{
                                            title = _("Wikipedia 'Save as EPUB' directory"),
                                            path = dir,
                                            show_hidden = G_reader_settings:readSetting("show_hidden"),
                                            onConfirm = function(path)
                                                -- hack to remove additional parent
                                                if path:sub(-3, -1) == "/.." then
                                                    path = path:sub(1, -4)
                                                end
                                                path = require("ffi/util").realpath(path)
                                                G_reader_settings:saveSetting("wikipedia_save_dir", path)
                                                UIManager:show(InfoMessage:new{
                                                    text = T(_("Wikipedia 'Save as EPUB' directory set to:\n%1"), path),
                                                })
                                            end
                                        }
                                        UIManager:show(path_chooser)
                                    end,
                                    },
                                },
                            },
                        }
                        UIManager:show(dialog)
                    end
                    -- If wikipedia_save_dir has not yet been set, propose to use
                    -- home_dir/Wikipedia/
                    if not G_reader_settings:readSetting("wikipedia_save_dir") then
                        local home_dir = G_reader_settings:readSetting("home_dir")
                        if not home_dir or not lfs.attributes(home_dir, "mode") == "directory" then
                            home_dir = require("apps/filemanager/filemanagerutil").getDefaultDir()
                        end
                        home_dir = home_dir:gsub("^(.-)/*$", "%1") -- remove trailing slash
                        if home_dir and lfs.attributes(home_dir, "mode") == "directory" then
                            local wikipedia_dir = home_dir.."/Wikipedia"
                            local text = _([[
Wikipedia articles can be saved as an EPUB for more comfortable reading.

You can select an existing directory, or use a default directory named "Wikipedia" in your reader's home directory.

Where do you want them saved?]])
                            UIManager:show(ConfirmBox:new{
                                text = text,
                                ok_text = _("Use ~/Wikipedia/"),
                                ok_callback = function()
                                    if not util.pathExists(wikipedia_dir) then
                                        lfs.mkdir(wikipedia_dir)
                                    end
                                    G_reader_settings:saveSetting("wikipedia_save_dir", wikipedia_dir)
                                    UIManager:show(InfoMessage:new{
                                        text = T(_("Wikipedia 'Save as EPUB' directory set to:\n%1"), wikipedia_dir),
                                    })
                                end,
                                cancel_text = _("Select directory"),
                                cancel_callback = function()
                                    choose_directory()
                                end,
                            })
                            return
                        end
                    end
                    -- If setting exists, or no home_dir found, let user choose directory
                    choose_directory()
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Save Wikipedia EPUB in current book directory"),
                checked_func = function()
                    return G_reader_settings:isTrue("wikipedia_save_in_book_dir")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("wikipedia_save_in_book_dir")
                end,
                separator = true,
            },
            {
                text = _("Enable Wikipedia history"),
                checked_func = function()
                    return not self.disable_history
                end,
                callback = function()
                    self.disable_history = not self.disable_history
                    G_reader_settings:saveSetting("wikipedia_disable_history", self.disable_history)
                end,
            },
            {
                text = _("Clean Wikipedia history"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clean Wikipedia history?"),
                        ok_text = _("Clean"),
                        ok_callback = function()
                            -- empty data table to replace current one
                            wikipedia_history:reset{}
                        end,
                    })
                end,
                separator = true,
            },
            { -- setting used in wikipedia.lua
                text = _("Show image in search results"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("wikipedia_show_image")
                end,
            },
            { -- setting used in wikipedia.lua
                text = _("Show more images in full article"),
                enabled_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                checked_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_more_images") and G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("wikipedia_show_more_images")
                end,
            },
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
    -- Wrapped through Trapper, as we may be using Trapper:dismissableRunInSubprocess() in it
    Trapper:wrap(function()
        self:lookupWikipedia(word, box, get_fullpage, forced_lang)
    end)
    return true
end

function ReaderWikipedia:lookupWikipedia(word, box, get_fullpage, forced_lang)
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
    local display_word = word:gsub("_", " ")

    if not self.disable_history then
        local book_title = self.ui.doc_settings and self.ui.doc_settings:readSetting("doc_props").title or _("Wikipedia lookup")
        if book_title == "" then -- no or empty metadata title
            if self.ui.document and self.ui.document.file then
                local directory, filename = util.splitFilePathName(self.ui.document.file) -- luacheck: no unused
                book_title = util.splitFileNameSuffix(filename)
            end
        end
        wikipedia_history:addTableItem("wikipedia_history", {
            book_title = book_title,
            time = os.time(),
            word = display_word,
            lang = lang:lower(),
            page = get_fullpage,
        })
    end

    -- Fix lookup message to include lang and set appropriate error texts
    local no_result_text, req_failure_text
    if get_fullpage then
        self.lookup_msg = T(_("Retrieving Wikipedia %2 article:\n%1"), "%1", lang:upper())
        req_failure_text = _("Failed to retrieve Wikipedia article.")
        no_result_text = _("Wikipedia article not found.")
    else
        self.lookup_msg = T(_("Searching Wikipedia %2 for:\n%1"), "%1", lang:upper())
        req_failure_text = _("Failed searching Wikipedia.")
        no_result_text = _("No Wikipedia articles matching search term.")
    end
    self:showLookupInfo(display_word)

    local results = {}
    local ok, pages
    local lookup_cancelled = false
    Wikipedia:setTrapWidget(self.lookup_progress_msg)
    if get_fullpage then
        ok, pages = pcall(Wikipedia.getFullPage, Wikipedia, word, lang)
    else
        ok, pages = pcall(Wikipedia.searchAndGetIntros, Wikipedia, word, lang)
    end
    Wikipedia:resetTrapWidget()
    if not ok and pages and string.find(pages, Wikipedia.dismissed_error_code) then
        -- So we can display an alternate dummy result
        lookup_cancelled = true
        -- Or we could just not show anything with:
        -- self:dismissLookupInfo()
        -- return
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
            local definition = page.extract or no_result_text
            if page.length then
                -- we get 'length' only for intro results
                -- let's append it to definition so we know
                -- how big/valuable the full page is
                local fullkb = math.ceil(page.length/1024)
                local more_factor = math.ceil( page.length / (1+definition:len()) ) -- +1 just in case len()=0
                definition = definition .. "\n" .. T(_("(full article : %1 kB, = %2 x this intro length)"), fullkb, more_factor)
            end
            local result = {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = page.title,
                definition = definition,
                is_fullpage = get_fullpage,
                lang = lang,
                images = page.images,
            }
            table.insert(results, result)
        end
        -- logger.dbg of results will be done by ReaderDictionary:showDict()
    else
        -- dummy results
        local definition
        if lookup_cancelled then
            definition = _("Wikipedia request canceled.")
        elseif ok then
            definition = no_result_text
        else
            definition = req_failure_text
            logger.dbg("error:", pages)
        end
        results = {
            {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = word,
                definition = definition,
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
