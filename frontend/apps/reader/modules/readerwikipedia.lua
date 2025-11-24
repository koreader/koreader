local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
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
local filemanagerutil = require("apps/filemanager/filemanagerutil")
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
    disable_history = G_reader_settings:isTrue("wikipedia_disable_history"),
}

function ReaderWikipedia:init()
    self:registerKeyEvents()
    self.wiki_languages = {}
    self.ui.menu:registerToMainMenu(self)
    if not wikipedia_history then
        wikipedia_history = LuaData:open(DataStorage:getSettingsDir() .. "/wikipedia_history.lua", "WikipediaHistory")
    end
end

function ReaderWikipedia:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowWikipediaLookup = { { "Alt", "W" }, { "Ctrl", "W" } }
        if Device.k3_alt_plus_key_kernel_translated then
            self.key_events.ShowWikipediaLookup = { { Device.k3_alt_plus_key_kernel_translated["W"] } }
        end
    end
end

function ReaderWikipedia:lookupInput()
    self.input_dialog = InputDialog:new{
        title = _("Enter a word or phrase to look up"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("Search Wikipedia"),
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        UIManager:close(self.input_dialog)
                        -- Trust that input text does not need any cleaning (allows querying for "-suffix")
                        self:onLookupWikipedia(self.input_dialog:getInputText(), true)
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
        callback = function() self:onShowWikipediaLookup() end,
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
                        -- Word had been cleaned before being added to history
                        self:onLookupWikipedia(value.word, true, nil, value.page, value.lang)
                    end
                })
            end
            UIManager:show(KeyValuePage:new{
                title = _("Wikipedia history"),
                value_overflow_align = "right",
                kv_pairs = kv_pairs,
            })
        end,
    }
    local function genChoiceMenuEntry(title, setting, value, default)
        return {
            text = title,
            checked_func = function()
                return G_reader_settings:readSetting(setting, default) == value
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting(setting, value)
            end,
        }
    end
    menu_items.wikipedia_settings = {
        text = _("Wikipedia settings"),
        sub_item_table = {
            {
                text = _("Set Wikipedia languages"),
                keep_menu_open = true,
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
                                    id = "close",
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
                separator = true,
            },
            { -- setting used by dictquicklookup
                text = _("Set Wikipedia 'Save as EPUB' folder"),
                keep_menu_open = true,
                help_text = _([[
Wikipedia articles can be saved as an EPUB for more comfortable reading.

You can choose an existing folder, or use a default folder named "Wikipedia" in your reader's home folder.]]),
                callback = function()
                    local title_header = _("Current Wikipedia 'Save as EPUB' folder:")
                    local current_path = G_reader_settings:readSetting("wikipedia_save_dir")
                    local default_path = DictQuickLookup.getWikiSaveEpubDefaultDir()
                    local caller_callback = function(path)
                        G_reader_settings:saveSetting("wikipedia_save_dir", path)
                        if not util.pathExists(path) then
                            lfs.mkdir(path)
                        end
                    end
                    filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Save Wikipedia EPUB in current book folder"),
                checked_func = function()
                    return G_reader_settings:isTrue("wikipedia_save_in_book_dir")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("wikipedia_save_in_book_dir")
                end,
            },
            { -- setting used in wikipedia.lua
                text_func = function()
                    local include_images = _("ask")
                    if G_reader_settings:readSetting("wikipedia_epub_include_images") == true then
                        include_images = _("always")
                    elseif G_reader_settings:readSetting("wikipedia_epub_include_images") == false then
                        include_images = _("never")
                    end
                    return T(_("Include images in EPUB: %1"), include_images)
                end,
                sub_item_table = {
                    genChoiceMenuEntry(_("Ask"), "wikipedia_epub_include_images", nil),
                    genChoiceMenuEntry(_("Include images"), "wikipedia_epub_include_images", true),
                    genChoiceMenuEntry(_("Don't include images"), "wikipedia_epub_include_images", false),
                },
            },
            { -- setting used in wikipedia.lua
                text_func = function()
                    local images_quality = _("ask")
                    if G_reader_settings:readSetting("wikipedia_epub_highres_images") == true then
                        images_quality = _("higher")
                    elseif G_reader_settings:readSetting("wikipedia_epub_highres_images") == false then
                        images_quality = _("standard")
                    end
                    return T(_("Images quality in EPUB: %1"), images_quality)
                end,
                enabled_func = function()
                    return G_reader_settings:readSetting("wikipedia_epub_include_images") ~= false
                end,
                sub_item_table = {
                    genChoiceMenuEntry(_("Ask"), "wikipedia_epub_highres_images", nil),
                    genChoiceMenuEntry(_("Standard quality"), "wikipedia_epub_highres_images", false),
                    genChoiceMenuEntry(_("Higher quality"), "wikipedia_epub_highres_images", true),
                },
                separator = true,
            },
            {
                text = _("Wikipedia lookup history"),
                checked_func = function()
                    return not self.disable_history
                end,
                sub_item_table = {
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
                        enabled_func = function()
                            return wikipedia_history:has("wikipedia_history")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            UIManager:show(ConfirmBox:new{
                                text = _("Clean Wikipedia history?"),
                                ok_text = _("Clean"),
                                ok_callback = function()
                                    -- empty data table to replace current one
                                    wikipedia_history:reset{}
                                    touchmenu_instance:updateItems()
                                end,
                            })
                        end,
                    },
                },
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
        -- use this setting, no need to guess: we reference the setting table, so
        -- any update to it will have it saved in settings
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
            addLanguage(self.ui.doc_props.language)
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

function ReaderWikipedia:onLookupWikipedia(word, is_sane, box, get_fullpage, forced_lang, dict_close_callback)
    -- Wrapped through Trapper, as we may be using Trapper:dismissableRunInSubprocess() in it
    Trapper:wrap(function()
        self:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang, dict_close_callback)
    end)
    return true
end

function ReaderWikipedia:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang, dict_close_callback)
    if NetworkMgr:willRerunWhenOnline(function() self:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang, dict_close_callback) end) then
        -- Not online yet, nothing more to do here, NetworkMgr will forward the callback and run it once connected!
        return
    end

    -- word is the text to query. If get_fullpage is true, it is the
    -- exact wikipedia page title we want the full page of.
    self:initLanguages(word)
    local lang
    if forced_lang then
        -- use provided lang (from readerlink when noticing that an external link is a wikipedia url,
        -- of from Wikipedia lookup history, or when switching to next language in DictQuickLookup)
        lang = forced_lang
    else
        -- use first lang from self.wiki_languages
        lang = self.wiki_languages[1]
    end
    logger.dbg("lookup word:", word, box, get_fullpage)
    -- no need to clean word if get_fullpage, as it is the exact wikipetia page title
    if word and not get_fullpage then
        -- escape quotes and other funny characters in word
        word = self:cleanSelection(word, is_sane)
        -- no need to lower() word with wikipedia search
    end
    logger.dbg("stripped word:", word)
    if word == "" then
        return
    end
    local display_word = word:gsub("_", " ")

    if not self.disable_history then
        local book_title = self.ui.doc_props and self.ui.doc_props.display_title or _("Wikipedia lookup")
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
        no_result_text = _("No results.")
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
            local definition = page.extract or (page.length and _("No introduction.")) or no_result_text
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
                is_wiki_fullpage = get_fullpage,
                lang = lang,
                rtl_lang = Wikipedia:isWikipediaLanguageRTL(lang),
                images = page.images,
            }
            table.insert(results, result)
        end
        -- logger.dbg of results will be done by ReaderDictionary:showDict()
    else
        -- dummy results
        local definition
        if lookup_cancelled then
            definition = _("Wikipedia request interrupted.")
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
                is_wiki_fullpage = get_fullpage,
                lang = lang,
            }
        }
        -- Also put this as a k/v into the results array: if we end up with this
        -- after lang rotation, DictQuickLookup will not update this lang rotation.
        results.no_result = true
        logger.dbg("dummy result table:", word, results)
    end
    self:showDict(word, results, box, nil, dict_close_callback)
end

function ReaderWikipedia:getWikiLanguages(first_lang)
    -- Always return a copy of ours
    local wiki_languages = {unpack(self.wiki_languages)}
    local is_first_lang = first_lang == wiki_languages[1]
    if not is_first_lang then
        -- return a wiki_languages with requested lang at first
        if util.arrayContains(wiki_languages, first_lang) then
            -- first_lang in the list: rotate until it is first
            while wiki_languages[1] ~= first_lang do
                table.insert(wiki_languages, table.remove(wiki_languages, 1))
            end
        else
            -- first_lang not in the list: add it first
            table.insert(wiki_languages, 1, first_lang)
        end
    end
    local update_wiki_languages_on_close = false
    if DictQuickLookup.rotated_update_wiki_languages_on_close ~= nil then
        -- Flag set by DictQuickLookup when rotating, forwarding the flag
        -- of the rotated out DictQuickLookup instance: trust it
        update_wiki_languages_on_close = DictQuickLookup.rotated_update_wiki_languages_on_close
        DictQuickLookup.rotated_update_wiki_languages_on_close = nil
    else
        -- Not a rotation. Only if it's the first request with the current
        -- first language, we will have it (and any lang rotation from it)
        -- update the main ReaderWikipedia.wiki_languages. That is, queries
        -- from Wikipedia url links for another language, or from Wikipedia
        -- lookup history with other languages (and any lang rotation made
        -- from them) won't update it.
        if is_first_lang then
            update_wiki_languages_on_close = true
            for i = #DictQuickLookup.window_list-1, 1, -1 do -- (ignore the last one, which is the one calling this)
                if DictQuickLookup.window_list[i].is_wiki then
                    -- Another upper Wikipedia result: only this one may update it
                    update_wiki_languages_on_close = false
                    break
                end
            end
        end
    end
    return wiki_languages, update_wiki_languages_on_close
end

function ReaderWikipedia:onUpdateWikiLanguages(wiki_languages)
    -- Update our self.wiki_languages in-place
    while table.remove(self.wiki_languages) do end
    for _, lang in ipairs(wiki_languages) do
        table.insert(self.wiki_languages, lang)
    end
end

-- override onSaveSettings in ReaderDictionary
function ReaderWikipedia:onSaveSettings()
end

function ReaderWikipedia:onShowWikipediaLookup()
    local connect_callback = function()
        self:lookupInput()
    end
    NetworkMgr:runWhenOnline(connect_callback)
    return true
end

return ReaderWikipedia
