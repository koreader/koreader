local DataStorage = require("datastorage")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderUserHyph = WidgetContainer:new{
    -- return values from setUserHyphenationDict (crengine's UserHyphDict::init())
    USER_DICT_RELOAD = 0,
    USER_DICT_NOCHANGE = 1,
    USER_DICT_MALFORMED = 2,
    USER_DICT_ERROR_NOT_SORTED = 3,
}

-- returns path to the user dictionary
function ReaderUserHyph:getDictionaryPath()
    return FFIUtil.joinPath(DataStorage:getSettingsDir(),
        "user-" .. tostring(self.ui.document:getTextMainLangDefaultHyphDictionary():gsub(".pattern$", "")) .. ".hyph")
end

-- Load the user dictionary suitable for the actual language
-- if reload==true, force a reload
-- Unload is done automatically when a new dictionary is loaded.
function ReaderUserHyph:loadDictionary(name, reload)
    if G_reader_settings:isTrue("hyph_user_dict") and lfs.attributes(name, "mode") == "file" then
        logger.dbg("set user hyphenation dict", name, reload)
        local ret = cre.setUserHyphenationDict(name, reload)
        -- this should only happen, if a user edits a dictionary by hand or the user messed
        -- with the dictionary file by hand. -> Warning and disable.
        if ret == self.USER_DICT_ERROR_NOT_SORTED then
            UIManager:show(InfoMessage:new{
                text = T(_("The user dictionary\n%1\nis not alphabetically sorted.\n\nIt has been disabled."), name),
            })
            logger.warn("UserHyph: Dictionary " .. name .. " is not sorted alphabetically.")
            G_reader_settings:makeFalse("hyph_user_dict")
        elseif ret == self.USER_DICT_MALFORMED then
            UIManager:show(InfoMessage:new{
                text = T(_("The user dictionary\n%1\nhas corrupted entries.\n\nOnly valid entries will be used."), name),
            })
            logger.warn("UserHyph: Dictionary " .. name .. " has corrupted entries.")
        end
    else
        logger.dbg("reset user hyphenation dict")
        cre.setUserHyphenationDict("", true) -- clear crengine user hyph dict
    end
end

-- Reload on change of the hyphenation language
function ReaderUserHyph:onTypographyLanguageChanged()
    self:loadUserDictionary()
end

-- Reload on "ChangedUserDictionary" event,
-- doesn't load dictionary if filesize and filename haven't changed
-- if reload==true reload
function ReaderUserHyph:loadUserDictionary(reload)
    self:loadDictionary(self:isAvailable() and self:getDictionaryPath() or "", reload and true or false)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

-- Functions to use with the UI

function ReaderUserHyph:isAvailable()
    return G_reader_settings:isTrue("hyph_user_dict") and self:_enabled()
end

function ReaderUserHyph:_enabled()
    return self.ui.typography.hyphenation
end

-- add Menu entry
function ReaderUserHyph:getMenuEntry()
    return {
        text = _("Custom hyphenation rules"),
        help_text = _("The hyphenation of a word can be changed from its default by long pressing for 3 seconds and selecting 'Hyphenate'."),
        callback = function()
            local hyph_user_dict =  not G_reader_settings:isTrue("hyph_user_dict")
            G_reader_settings:saveSetting("hyph_user_dict", hyph_user_dict)
            self:loadUserDictionary() -- not needed to force a reload here
        end,
        checked_func = function()
            return self:isAvailable()
        end,
        enabled_func = function()
            return self:_enabled()
        end,
        separator = true,
    }
end

-- Helper functions for dictionary entries-------------------------------------------

-- checks if suggestion is well formated
function ReaderUserHyph:checkHyphenation(suggestion, word)
    if suggestion:find("%-%-") then
        return false -- two or more consecutive '-'
    end

    suggestion = suggestion:gsub("-","")
    if Utf8Proc.lowercase(suggestion) == Utf8Proc.lowercase(word) then
        return true -- characters match (case insensitive)
    end
    return false
end

function ReaderUserHyph:updateDictionary(word, hyphenation)
    local dict_file = self:getDictionaryPath()
    local new_dict_file = dict_file .. ".new"

    local new_dict = io.open(new_dict_file, "w")
    if not new_dict then
        logger.err("UserHyph: could not open " .. new_dict_file)
        return
    end

    local word_lower = Utf8Proc.lowercase(word)
    local line

    local dict = io.open(dict_file, "r")
    if dict then
        line = dict:read()
        --search entry
        while line and Utf8Proc.lowercase(line:sub(1, line:find(";") - 1)) < word_lower do
            new_dict:write(line .. "\n")
            line = dict:read()
        end

        -- last word = nil if EOF, else last_word=word if found in file, else last_word is word after the new entry
        if line then
            local last_word = Utf8Proc.lowercase(line:sub(1, line:find(";") - 1))
            if last_word == Utf8Proc.lowercase(word) then
                line = nil -- word found
            end
        else
            line = nil -- EOF
        end
    end

    -- write new entry
    if hyphenation and hyphenation ~= "" then
        new_dict:write(string.format("%s;%s\n", word, hyphenation))
    end

    -- write old entry if there was one
    if line then
        new_dict:write(line .. "\n")
    end

    if dict then
        repeat
            line = dict:read()
            if line then
                new_dict:write(line .. "\n")
            end
        until (not line)
        dict:close()
        os.remove(dict_file)
    end

    new_dict:close()
    os.rename(new_dict_file, dict_file)

    self:loadUserDictionary(true) -- dictionary has changed, force a reload here
end

function ReaderUserHyph:modifyUserEntry(word)
    if word:find("[ ,;-%.]") then return end -- no button if more than one word

    if not self.ui.document then return end

    local suggested_hyphenation = cre.getHyphenationForWord(word)

    local input_dialog
    input_dialog = InputDialog:new{
        title = T(_("Hyphenate: %1"), word),
        description = _("Add hyphenation positions with hyphens ('-') or spaces (' ')."),
        input = suggested_hyphenation,
        old_hyph_lowercase = Utf8Proc.lowercase(suggested_hyphenation),
        input_type = "string",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Remove"),
                    callback = function()
                        UIManager:close(input_dialog)
                        self:updateDictionary(word)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_suggestion = input_dialog:getInputText()
                        new_suggestion = new_suggestion:gsub(" ","-") -- replace spaces with hyphens
                        new_suggestion = new_suggestion:gsub("^-","") -- remove leading hypenations
                        new_suggestion = new_suggestion:gsub("-$","") -- remove trailing hypenations

                        if self:checkHyphenation(new_suggestion, word) then
                            -- don't save if no changes
                            if Utf8Proc.lowercase(new_suggestion) ~= input_dialog.old_hyph_lowercase then
                                self:updateDictionary(word, new_suggestion)
                            end
                            UIManager:close(input_dialog)
                        else
                            UIManager:show(InfoMessage:new{
                                text = T(_("Invalid hyphenation!"), self.dict_file),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return ReaderUserHyph
