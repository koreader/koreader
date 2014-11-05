local InputContainer = require("ui/widget/container/inputcontainer")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local JSON = require("JSON")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderDictionary = InputContainer:new{}

function ReaderDictionary:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderDictionary:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Dictionary lookup"),
        tap_input = {
            title = _("Input word to lookup"),
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

local function tidy_markup(results)
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
        result.definition = def
    end
    return results
end

function ReaderDictionary:stardictLookup(word, box)
    DEBUG("lookup word:", word, box)
    if word then
        -- strip ASCII punctuation characters around selected word
        -- and strip any generic punctuation (U+2000 - U+206F) in the word
        word = word:gsub("\226[\128-\131][\128-\191]",''):gsub("^%p+",''):gsub("%p+$",'')
        DEBUG("stripped word:", word)
        -- escape quotes and other funny characters in word
        local std_out = io.popen("./sdcv --utf8-input --utf8-output -nj "..("%q"):format(word), "r")
        local results_str = nil
        if std_out then results_str = std_out:read("*all") end
        --DEBUG("result str:", word, results_str)
        local ok, results = pcall(JSON.decode, JSON, results_str)
        if ok and results then
            DEBUG("lookup result table:", word, results)
            self:showDict(word, tidy_markup(results), box)
        else
            -- dummy results
            results = {
                {
                    dict = "",
                    word = word,
                    definition = _("No definition found."),
                }
            }
            DEBUG("dummy result table:", word, results)
            self:showDict(word, results, box)
        end
    end
end

function ReaderDictionary:showDict(word, results, box)
    if results and results[1] then
        DEBUG("showing quick lookup window")
        UIManager:show(DictQuickLookup:new{
            ui = self.ui,
            highlight = self.highlight,
            dialog = self.dialog,
            -- original lookup word
            word = word,
            results = results,
            dictionary = self.default_dictionary,
            width = Screen:getWidth() - Screen:scaleByDPI(80),
            word_box = box,
            -- differentiate between dict and wiki
            wiki = self.wiki,
        })
    end
end

function ReaderDictionary:onUpdateDefaultDict(dict)
    DEBUG("make default dictionary:", dict)
    self.default_dictionary = dict
    return true
end

function ReaderDictionary:onReadSettings(config)
    self.default_dictionary = config:readSetting("default_dictionary")
end

function ReaderDictionary:onSaveSettings()
    DEBUG("save default dictionary", self.default_dictionary)
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
