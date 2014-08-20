local EventListener = require("ui/widget/eventlistener")
local UIManager = require("ui/uimanager")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local JSON = require("JSON")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderDictionary = EventListener:new{}

function ReaderDictionary:onLookupWord(word, box, highlight)
    self.highlight = highlight
    self:stardictLookup(word, box)
    return true
end

function ReaderDictionary:stardictLookup(word, box)
    DEBUG("lookup word:", word, box)
    if word then
        -- strip punctuation characters around selected word
        word = string.gsub(word, "^%p+", '')
        word = string.gsub(word, "%p+$", '')
        DEBUG("stripped word:", word)
        -- escape quotes and other funny characters in word
        local std_out = io.popen("./sdcv --utf8-input --utf8-output -nj "..("%q"):format(word), "r")
        local results_str = nil
        if std_out then results_str = std_out:read("*all") end
        --DEBUG("result str:", word, results_str)
        local ok, results = pcall(JSON.decode, JSON, results_str)
        if ok and results then
            DEBUG("lookup result table:", word, results)
            self:showDict(word, results, box)
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
    self.ui.doc_settings:saveSetting("default_dictionary", self.default_dictionary)
end

return ReaderDictionary
