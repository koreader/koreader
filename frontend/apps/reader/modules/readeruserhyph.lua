local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
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

    -- work with malformed dictionary entries, some hyphenations might not work
    malformed_accepted = false,
}

-- returns path to the user dictionary
function ReaderUserHyph:getDictionaryPath()
    return FFIUtil.joinPath(DataStorage:getSettingsDir(),
        "user-" .. tostring(self.ui.document:getTextMainLangDefaultHyphDictionary():gsub(".pattern$", "")) .. ".hyph")
end


local load_error_text = _("Error loading user dictionary:\n%1\n%2")

-- Load the user dictionary suitable for the actual language
-- if reload==true, force a reload
-- Unload is done automatically when a new dictionary is loaded.
function ReaderUserHyph:loadDictionary(name, reload)
    if G_reader_settings:isTrue("hyph_user_dict") and lfs.attributes(name, "mode") == "file" then
        local ret = self.ui.document:setUserHyphenationDict(name, reload)
        -- this should only happen, if a user edits a dictionary by hand or the user messed
        -- with the dictionary file by hand. -> Warning and disable.
        if ret == self.USER_DICT_ERROR then
            UIManager:show(InfoMessage:new{
                text = T(load_error_text, name, _("Dictionary is not sorted alphabetically.\n\nDictionary is disabled now.")),
            })
            G_reader_settings:saveSetting("hyph_user_dict", false)
        elseif ret == self.USER_DICT_MALFORMED and not self.malformed_accepted then
            UIManager:show(ConfirmBox:new{
                text =  T(load_error_text, name, _("At least one dictionary entry is malformed.\n\nDo you want work with this incomplete dictionary?")),
                ok_text = _("Keep"),
                ok_callback = function()
                    self.malformed_accepted = true -- show this message only once per KOReader run
                end,
                cancel_text = _("Discard"),
                cancel_callback = function()
                    G_reader_settings:saveSetting("hyph_user_dict", false)
                end,
                })
        end
    else
        self.ui.document:setUserHyphenationDict() -- clear crengine user hyph dict
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
        text = _("Additional user dictionary"),
        help_text = _([[The user dictionary is an overlay to the selected hyphenation method.

You can change the hyphenation by long press (>4s) on a word and select 'Hyphenate' from the popup menu.

If you remove a word from the user dictionary, the selected hyphenation method is applied again.]]),
        callback = function()
            local hyph_user_dict =  not G_reader_settings:isTrue("hyph_user_dict")
            G_reader_settings:saveSetting("hyph_user_dict", hyph_user_dict)
            self:loadUserDictionary()
        end,
        hold_callback = function()
            local hyph_user_dict = G_reader_settings:isTrue("hyph_user_dict")
            UIManager:show(MultiConfirmBox:new{
                text = hyph_user_dict and _("Would you like to enable or disable the user hyphenation dictionary?\n\nThe current default (★) is enabled.")
                or _("Would you like to enable or disable the user hyphenation dictionary?\n\nThe current default (★) is disabled."),
                choice1_text_func =  function()
                    return hyph_user_dict and _("Disable") or _("Disable (★)")
                end,
                choice1_callback = function()
                    G_reader_settings:makeFalse("hyph_user_dict")
                end,
                choice2_text_func = function()
                    return hyph_user_dict and _("Enable (★)") or _("Enable")
                end,
                choice2_callback = function()
                    G_reader_settings:makeTrue("hyph_user_dict")
                end,
            })
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
    if self.ui.document:getLowercasedWord(suggestion) == self.ui.document:getLowercasedWord(word) then
        return true -- characters match (case insensitive)
    end
    return false
end

function ReaderUserHyph:updateDictionaryFile(word, hyphenation)
    local dict_file = self:getDictionaryPath()
    local new_dict_file = dict_file .. ".new"
    local dict
    local new_dict

    -- if no file, crate an empty one
    if lfs.attributes(dict_file, "mode") ~= "file" then
        dict = io.open(dict_file, "w")
        dict:close()
    end

print("xxxxxxxxxx open files" .. tostring(dict_file) .. tostring(new_dict_file ) )
    -- open files
    dict = io.open(dict_file, "r")
    if not dict then
        logger.err("UserHyph: could not open " .. dict_file)
        return
    end
    new_dict = io.open(new_dict_file, "w")
    if not new_dict then
        logger.err("UserHyph: could not open " .. new_dict_file)
        return
    end

print("xxxxxxxxxx search")

    --search entry
    local word_lower = self.ui.document:getLowercasedWord(word)
    local line = dict:read()
    while line and self.ui.document:getLowercasedWord(line:sub(1, line:find(";") - 1)) < word_lower do
        new_dict:write(line .. "\n")
        line = dict:read()
    end

print("xxxxxxxxxx found " .. tostring(line))

    -- last word = nil if EOF, else last_word=word if found in file, else last_word is word after the new entry
    if line then
        local last_word = self.ui.document:getLowercasedWord(line:sub(1, line:find(";") - 1))
        if self.ui.document:getLowercasedWord(last_word)
            == self.ui.document:getLowercasedWord(word) then
            line = nil
        end
    else
        line = nil
    end

print("xxxxxxxxxx write entry word" ..word.." hyphenation:" .. tostring(hyphenation))
    -- write new entry or remove old one
    if hyphenation and hyphenation~="" then
        new_dict:write(string.format("%s;%s\n", word, hyphenation))
    end

    -- write old entry if there was one
    if line  then

print("xxxxxxxxxx write old entry")

        new_dict:write(line .. "\n")

    end

print("xxxxxxxxxxxx copy restr")
    -- copy rest of file
    repeat
        line = dict:read()
        if line then
            new_dict:write(line .. "\n")
        end
    until (not line)

    dict:close()
    new_dict:close()
    os.remove(dict_file)
    os.rename(new_dict_file, dict_file)
end


function ReaderUserHyph:modifyUserEntry(word)
    if word:find("[ ,;-%.]") then return end -- no button if more than one word

    if not self.ui.document then
        return
    end

    local suggested_hyphenation = self.ui.document:getHyphenationForWord(word)

    local input_dialog
    input_dialog = InputDialog:new{
        title = T(_("Hyphenation entry for: \"%1\""), word),
        description = _("Add hyphenation positions with hyphens ('-') or spaces (' ')."),
        input = suggested_hyphenation,
        old_hyph = suggested_hyphenation,
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
                        self:updateDictionaryFile(word)
                        self:loadUserDictionary(true)
                    end,
                },
                {
                    text = _("Store"),
                    is_enter_default = true,
                    callback = function()
                        local new_suggestion = input_dialog:getInputText()
                        new_suggestion = new_suggestion:gsub(" ","-") -- replace spaces with hyphens
                        new_suggestion = new_suggestion:gsub("^-","") -- remove leading hypenations
                        new_suggestion = new_suggestion:gsub("-$","") -- remove trailing hypenations

                        if self:checkHyphenation(new_suggestion, word) then
                            -- don't save if no changes
                            if self.ui.document:getLowercasedWord(new_suggestion)
                                ~= self.ui.document:getLowercasedWord(input_dialog.old_hyph) then
                                self:updateDictionaryFile(word, new_suggestion)
                                self:loadUserDictionary(true)
                            end
                            UIManager:close(input_dialog)
                        else
                            UIManager:show(InfoMessage:new{
                                text = T(_("Wrong hyphenation!\nPlease check!"), self.dict_file),
                                show_icon = true,
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
