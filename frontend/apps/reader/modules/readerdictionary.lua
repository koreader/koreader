local InputContainer = require("ui/widget/container/inputcontainer")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Device = require("device")
local JSON = require("json")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
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

function ReaderDictionary:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.search, {
        text = _("Dictionary lookup"),
        tap_input = {
            title = _("Enter a word to look up"),
            type = "text",
            callback = function(input)
                self:onLookupWord(input)
            end,
        },
    })
end

function ReaderDictionary:onLookupWord(word, box, highlight)
    self.highlight = highlight
    self:stardictLookup(word, box)
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
    -- We do multiple times the same replacements, which is most of the time overkill,
    -- but sometimes provices better cleaning
    -- Some extremes cases to explain the multiples gsub :
    --
    -- Sample epub html: mais, qu’« absolument, on ne peut décidément pas » revenir en arrière
    -- Holding on "qu" or "absolument" will make crengine returns: qu’« absolument,
    -- We want to only get: absolument
    --
    -- Sample epub html: car « l’état, actuel, de notre connaissance » s’y oppose
    -- Holding on "état" will make crengine returns: « l’état,
    -- We want to get: état
    --
    -- Some of these gsub could be removed when crengine does a better job
    -- at finding word boundaries
    --
    -- Strip some quotations marks
    text = string.gsub(text, "\xC2\xAB", '') -- U+00AB << (left double angle quotation mark)
    text = string.gsub(text, "\xC2\xBB", '') -- U+00BB >> (right double angle quotation mark)
    text = string.gsub(text, "\xE2\x80\x9D", '') -- U+201D '' (right double quotation mark)
    text = string.gsub(text, "\xE2\x80\x9C", '') -- U+201C `` (left double quotation mark)
    text = string.gsub(text, "\xE2\x80\x94", '') -- U+2014 - (em dash)
    text = string.gsub(text, "\xE2\x80\x95", '') -- U+2015 - (horizontal bar)
    text = string.gsub(text, "\xC2\xA0", '') -- U+00A0 no-break space
    -- Replace some meaningful quotes with ascii quote
    text = string.gsub(text, "\xE2\x80\x99", "'") -- U+2019 (right single quotation mark)
    -- Strip punctuation characters around selection
    -- (this had to be done after the utf8 gsubs above, or it would strip part of these utf8 chars)
    text = util.stripePunctuations(text)
    -- Strip leading and trailing spaces
    text = string.gsub(text, "^%s+", '')
    text = string.gsub(text, "%s+$", '')
    -- Strip some french grammatical constructs
    text = string.gsub(text, "^[LSDMNTlsdmnt]'", '') -- french l' s' t'
    text = string.gsub(text, "^[Qq][Uu]'", '') -- french qu'
    -- Strip again leading and trailing spaces
    text = string.gsub(text, "^%s+", '')
    text = string.gsub(text, "%s+$", '')
    return text
end

function ReaderDictionary:onLookupStarted(word)
    local text = T(self.lookup_msg, word)
    self.lookup_progress_msg = InfoMessage:new{text=text}
    UIManager:show(self.lookup_progress_msg)
    UIManager:forceRePaint()
end

function ReaderDictionary:onLookupDone()
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
    self:onLookupStarted(word)
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
    for _, dict_dir in ipairs(dict_dirs) do
        local results_str = nil
        if Device:isAndroid() then
            local A = require("android")
            results_str = A.stdout("./sdcv", "--utf8-input", "--utf8-output",
                    "-nj", word, "--data-dir", dict_dir)
        else
            local std_out = io.popen("./sdcv --utf8-input --utf8-output -nj "
                .. ("%q"):format(word) .. " --data-dir " .. dict_dir, "r")
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
    self:onLookupDone()
    self:showDict(word, tidyMarkup(final_results), box)
end

function ReaderDictionary:showDict(word, results, box)
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
        }
        table.insert(self.dict_window_list, self.dict_window)
        UIManager:show(self.dict_window)
    end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
    logger.dbg("make default dictionary:", dict)
    self.default_dictionary = dict
    UIManager:show(InfoMessage:new{
        text = T(_("%1 is now the default dictionary for this document."), dict),
        timeout = 2,
    })
    return true
end

function ReaderDictionary:onReadSettings(config)
    self.default_dictionary = config:readSetting("default_dictionary")
end

function ReaderDictionary:onSaveSettings()
    logger.dbg("save default dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
