local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("json")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local ReaderDictionary = InputContainer:new{
    data_dir = nil,
    dict_window_list = {},
    lookup_msg = _("Searching dictionary for:\n%1")
}

function ReaderDictionary:init()
    self.ui.menu:registerToMainMenu(self)
    self.data_dir = os.getenv("STARDICT_DATA_DIR") or
        DataStorage:getDataDir() .. "/data/dict"
end

function ReaderDictionary:addToMainMenu(menu_items)
    menu_items.dictionary_lookup = {
        text = _("Dictionary lookup"),
        tap_input = {
            title = _("Enter a word to look up"),
            ok_text = _("Search dictionary"),
            type = "text",
            callback = function(input)
                self:onLookupWord(input)
            end,
        },
    }
    menu_items.dictionary_settings = {
        text = _("Dictionary settings"),
        sub_item_table = {
            {
                text = _("Disable dictionary fuzzy search"),
                checked_func = function()
                    return self.disable_fuzzy_search == true
                end,
                callback = function()
                    self.disable_fuzzy_search = not self.disable_fuzzy_search
                end,
                hold_callback = function()
                    self:makeDisableFuzzyDefault(self.disable_fuzzy_search)
                end,
            },
            { -- setting used by dictquicklookup
                text = _("Justify text"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("dict_justify")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("dict_justify")
                end,
            }
        }
    }
end

function ReaderDictionary:onLookupWord(word, box, highlight)
    self.highlight = highlight
    self:stardictLookup(word, box)
    return true
end

local function dictDirsEmpty(dict_dirs)
    for _, dict_dir in ipairs(dict_dirs) do
        if not util.isEmptyDir(dict_dir) then
            return false
        end
    end
    return true
end

local function tidyMarkup(results)
    local cdata_tag = "<!%[CDATA%[(.-)%]%]>"
    local format_escape = "&[29Ib%+]{(.-)}"
    for _, result in ipairs(results) do
        local def = result.definition
        -- preserve the <br> tag for line break
        def = def:gsub("<[bB][rR] ?/?>", "\n")
        -- parse CDATA text in XML
        if def:find(cdata_tag) then
            def = def:gsub(cdata_tag, "%1")
            -- ignore format strings
            while def:find(format_escape) do
                def = def:gsub(format_escape, "%1")
            end
        end
        -- ignore all markup tags
        def = def:gsub("%b<>", "")
        -- strip all leading empty lines/spaces
        def = def:gsub("^%s+", "")
        result.definition = def
    end
    return results
end

function ReaderDictionary:cleanSelection(text)
    -- Will be used by ReaderWikipedia too
    if not text then
        return ""
    end
    -- crengine does now a much better job at finding word boundaries, but
    -- some cleanup is still needed for selection we get from other engines
    -- (example: pdf selection "qu’autrefois," will be cleaned to "autrefois")
    --
    -- Replace extended quote (included in the general puncturation range)
    -- with plain ascii quote (for french words like "aujourd’hui")
    text = string.gsub(text, "\xE2\x80\x99", "'") -- U+2019 (right single quotation mark)
    -- Strip punctuation characters around selection
    text = util.stripePunctuations(text)
    -- Strip some common english grammatical construct
    text = string.gsub(text, "'s$", '') -- english possessive
    -- Strip some common french grammatical constructs
    text = string.gsub(text, "^[LSDMNTlsdmnt]'", '') -- french l' s' t'...
    text = string.gsub(text, "^[Qq][Uu]'", '') -- french qu'
    -- Replace no-break space with regular space
    text = string.gsub(text, "\xC2\xA0", ' ') -- U+00A0 no-break space
    -- There may be a need to remove some (all?) diacritical marks
    -- https://en.wikipedia.org/wiki/Combining_character#Unicode_ranges
    -- see discussion at https://github.com/koreader/koreader/issues/1649
    -- Commented for now, will have to be checked by people who read
    -- languages and texts that use them.
    -- text = string.gsub(text, "\204[\128-\191]", '') -- U+0300 to U+033F
    -- text = string.gsub(text, "\205[\128-\175]", '') -- U+0340 to U+036F
    return text
end

function ReaderDictionary:showLookupInfo(word)
    local text = T(self.lookup_msg, word)
    self.lookup_progress_msg = InfoMessage:new{text=text}
    UIManager:show(self.lookup_progress_msg)
    UIManager:forceRePaint()
end

function ReaderDictionary:dismissLookupInfo()
    if self.lookup_progress_msg then
        UIManager:close(self.lookup_progress_msg)
        UIManager:forceRePaint()
    end
    self.lookup_progress_msg = nil
end

function ReaderDictionary:stardictLookup(word, box)
    logger.dbg("lookup word:", word, box)
    -- escape quotes and other funny characters in word
    word = self:cleanSelection(word)
    logger.dbg("stripped word:", word)
    if word == "" then
        return
    end
    if not self.disable_fuzzy_search then
        self:showLookupInfo(word)
    end
    local final_results = {}
    local seen_results = {}
    -- Allow for two sdcv calls : one in the classic data/dict, and
    -- another one in data/dict_ext if it exists
    -- We could put in data/dict_ext dictionaries with a great number of words
    -- but poor definitions as a fall back. If these were in data/dict,
    -- they would prevent fuzzy searches in other dictories with better
    -- definitions, and masks such results. This way, we can get both.
    local dict_dirs = {self.data_dir}
    local dict_ext = self.data_dir.."_ext"
    if lfs.attributes(dict_ext, "mode") == "directory" then
        table.insert(dict_dirs, dict_ext)
    end
    -- early exit if no dictionaries
    if dictDirsEmpty(dict_dirs) then
        final_results = {
            {
                dict = "",
                word = word,
                definition = _([[No dictionaries installed. Please search for "Dictionary support" in the KOReader Wiki to get more information about installing new dictionaries.]]),
            }
        }
        self:showDict(word, final_results, box)
        return
    end
    for _, dict_dir in ipairs(dict_dirs) do
        local results_str = nil
        local common_options = self.disable_fuzzy_search and "-njf" or "-nj"
        if Device:isAndroid() then
            local A = require("android")
            results_str = A.stdout("./sdcv", "--utf8-input", "--utf8-output",
                    common_options, word, "--data-dir", dict_dir)
        else
            local std_out = io.popen(
                ("./sdcv --utf8-input --utf8-output %q %q --data-dir %q"):format(common_options, word, dict_dir),
                "r")
            if std_out then
                results_str = std_out:read("*all")
                std_out:close()
            end
        end
        local ok, results = pcall(JSON.decode, results_str)
        if ok and results then
            -- we may get duplicates (sdcv may do multiple queries,
            -- in fixed mode then in fuzzy mode), we have to remove them
            local h
            for _,r in ipairs(results) do
                h = r.dict .. r.word .. r.definition
                if seen_results[h] == nil then
                    table.insert(final_results, r)
                    seen_results[h] = true
                end
            end
        else
            logger.warn("JSON data cannot be decoded", results)
        end
    end
    if #final_results == 0 then
        -- dummy results
        final_results = {
            {
                dict = "",
                word = word,
                definition = _("No definition found."),
            }
        }
    end
    self:showDict(word, tidyMarkup(final_results), box)
end

function ReaderDictionary:showDict(word, results, box)
    self:dismissLookupInfo()
    if results and results[1] then
        logger.dbg("showing quick lookup window", word, results)
        self.dict_window = DictQuickLookup:new{
            window_list = self.dict_window_list,
            ui = self.ui,
            highlight = self.highlight,
            dialog = self.dialog,
            -- original lookup word
            word = word,
            results = results,
            dictionary = self.default_dictionary,
            width = Screen:getWidth() - Screen:scaleBySize(80),
            word_box = box,
            -- differentiate between dict and wiki
            is_wiki = self.is_wiki,
            wiki_languages = self.wiki_languages,
            refresh_callback = function()
                if self.view then
                    -- update info in footer (time, battery, etc)
                    self.view.footer:updateFooter()
                end
            end,
        }
        table.insert(self.dict_window_list, self.dict_window)
        UIManager:show(self.dict_window)
    end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
    logger.dbg("make default dictionary:", dict)
    self.default_dictionary = dict
    UIManager:show(InfoMessage:new{
        text = T(_("%1 is now the default dictionary for this document."),
                 dict),
        timeout = 2,
    })
    return true
end

function ReaderDictionary:onReadSettings(config)
    self.default_dictionary = config:readSetting("default_dictionary")
    self.disable_fuzzy_search = config:readSetting("disable_fuzzy_search")
    if self.disable_fuzzy_search == nil then
        self.disable_fuzzy_search = G_reader_settings:isTrue("disable_fuzzy_search")
    end
end

function ReaderDictionary:onSaveSettings()
    logger.dbg("save default dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("disable_fuzzy_search", self.disable_fuzzy_search)
end

function ReaderDictionary:makeDisableFuzzyDefault(disable_fuzzy_search)
    logger.dbg("disable fuzzy search", self.disable_fuzzy_search)
    UIManager:show(ConfirmBox:new{
        text = T(
            disable_fuzzy_search
            and _("Disable fuzzy search by default?")
            or _("Enable fuzzy search by default?")
        ),
        ok_callback = function()
            G_reader_settings:saveSetting("disable_fuzzy_search", disable_fuzzy_search)
        end,
    })
end

return ReaderDictionary
