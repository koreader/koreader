local DataStorage = require("datastorage")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local TimeVal = require("ui/timeval")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local ReaderUserHyph = WidgetContainer:new{}

-----------------------------------------------
--
-----------------------------------------------

-- returns path to the user dictionary
function ReaderUserHyph:getDictionaryPath()
    return FFIUtil.joinPath(DataStorage:getSettingsDir(),
        "user-" .. self.ui.document:getTextMainLangDefaultHyphDictionary():gsub(".pattern$", "") .. ".hyph")
end

-- Load the user dictionary suitable for the actual language
-- if reload==true, force a reload
-- Unload is done automatically when a new dictionary is loaded.
function ReaderUserHyph:loadDictionary(name, reload)
    if G_reader_settings:isTrue("hyph_user_dict") and lfs.attributes(name, "mode") == "file" then
        self.ui.document:setUserHyphenationDict(name, reload)
    else
        self.ui.document:setUserHyphenationDict()
    end
end

-- Reload on change of the hyphenation language
function ReaderUserHyph:onTypographyLanguageChanged()
    self:onChangedUserDictionary()
end

-- Reload on "ChangedUserDictionary" event,
-- doesn't load dictionary if filesize and filename haven't changed
-- if reload==true reload
function ReaderUserHyph:onChangedUserDictionary(reload)
    local start_tv = TimeVal:now()
    self:loadDictionary(self:isAvailable() and self:getDictionaryPath() or "", reload and true or false)
    self.ui:handleEvent(Event:new("UpdatePos"))
    logger.err(string.format("xxxxxxxxxx reload user dictionary and rendering took %.3f seconds", TimeVal:getDuration(start_tv)))
    logger.dbg(string.format("reload user dictionary and rendering took %.3f seconds", TimeVal:getDuration(start_tv)))
end

---------------------------------------------
-- Functions to use with the UI
---------------------------------------------

function ReaderUserHyph:isAvailable()
    return G_reader_settings:isTrue("hyph_user_dict") and self:_enabled()
end

function ReaderUserHyph:_enabled()
    return self.ui.typography.hyphenation and not self.ui.typography.hyph_soft_hyphens_only
        and not self.ui.typography.hyph_force_algorithmic
end

function ReaderUserHyph:getMenuEntry()
    return {
        text = _("User dictionary for exceptions"),
        callback = function()
            local hyph_user_dict =  not G_reader_settings:isTrue("hyph_user_dict")
            G_reader_settings:saveSetting("hyph_user_dict", hyph_user_dict)
            self:onChangedUserDictionary(true)
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


-- add a button for dictquicklookup
function ReaderUserHyph:addButton(buttons, pos, word, parentWidget)
    if word:find("[ ,;-%.\n]") then return end

    if G_reader_settings:readSetting("hyph_user_dict") then
        table.insert(buttons, pos, {
            {
                id = "add_user_dict_entry",
                text = T(_("Modify hyphenation of \"%1\"."), word),
                callback = function()
                    if parentWidget then
                        UIManager:close(parentWidget)
                    end
                    self:modifyUserEntry(word)
                end,
            },
        })
    end
end

-------------------------------------------
-- Helper functions for dictionary entries
-------------------------------------------

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

-------------------------------------
-- dictionary, file functions use:
--    self.dict_file
--    self.new_dict_file
--    self.dict
--    self.next_line
-------------------------------------

-- opens user dictionary
function ReaderUserHyph:openDictionary()
    self.dict_file = self.ui.userhyph:getDictionaryPath()
    self.new_dict_file = self.dict_file .. ".new"

    -- if no file, crate an empty one
    if lfs.attributes(self.dict_file, "mode") ~= "file" then
        self.dict = io.open(self.dict_file, "w")
        self.dict:close()
    end

    -- open files
    self.dict = io.open(self.dict_file, "r")
    if not self.dict then
        logger.err("UserHyph: could not open " .. self.dict_file)
        return
    end
    self.new_dict = io.open(self.new_dict_file, "w")
    if not self.new_dict then
        logger.err("UserHyph: could not open " .. self.new_dict_file)
        return
    end
    return true
end

-- reads the first dictionary entries from the old dictionary
-- and write them to the new dict, as long the entry is alphabetically lower than word
-- if the word matches the dictionary entry, the hypenation part is formatted and returned
function ReaderUserHyph:findEntry(word)
    -- scan hyphenation dictionary for selected word
    local word_lower = self.ui.document:getLowercasedWord(word)
    self.next_line = self.dict:read()
    while self.next_line and self.ui.document:getLowercasedWord(self.next_line:sub(1, self.next_line:find(";") - 1)) < word_lower do
        self.new_dict:write(self.next_line .. "\n")
        self.next_line = self.dict:read()
    end

    local hyphenation
    -- check if a hyphenation is found for word
    if self.next_line and self.ui.document:getLowercasedWord(self.next_line:sub(1, self.next_line:find(";") - 1)) == word_lower then
        hyphenation = string.sub(self.next_line, self.next_line:find(";") + 1) -- hyphenation found
        self.next_line = nil -- Important for not duplicating the entry in the dictionary
    end
    return hyphenation
end

-- writes on entry to new dictionary
function ReaderUserHyph:writeEntry(line)
    self.new_dict:write(self.ui.document:getLowercasedWord(line) .. "\n")
end

-- reads the rest of the old dictionary and writes this to the reset
-- if self.new_dict~=nil, an additional line can be written
function ReaderUserHyph:writeRest()
    -- write old entry if there was one
    if self.next_line then
        self.new_dict:write(self.next_line .. "\n")
    end
    -- copy rest of file
    repeat
        self.next_line = self.ui.userhyph.dict:read()
        if self.next_line then
            self.new_dict:write(self.ui.userhyph.next_line .. "\n")
        end
    until (not self.next_line)
end

-- closes all open files and invalidates variables
function ReaderUserHyph:closeDictionary()
    self.ui.userhyph.dict:close()
    self.ui.userhyph.new_dict:close()
    os.remove(self.ui.userhyph.dict_file)
    os.rename(self.ui.userhyph.new_dict_file, self.ui.userhyph.dict_file)

    self.next_line = nil
    self.dict_file = nil
    self.new_dict_file = nil
    self.dict = nil
end

function ReaderUserHyph:modifyUserEntry(word)
    if word:find("[ ,;-%.]") then return end -- no button if more than one word

    if not self.ui.document then
        return
    end

    local suggested_hyphenation = self.ui.document:getHyphenationForWord(word)
    suggested_hyphenation = self.ui.document:formatHyphenationSuggestion(suggested_hyphenation, word)

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
                        self:openDictionary()
                        self:findEntry(word)
                        self:writeRest()
                        self:closeDictionary()
                        UIManager:close(input_dialog)
                        self:onChangedUserDictionary(true)
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

                        -- don't save if no changes
                        if self:checkHyphenation(new_suggestion, word) then
                            if new_suggestion ~= input_dialog.old_hyph then
                                self:openDictionary()
                                self:findEntry(word)
                                self:writeEntry(string.format("%s;%s", word, new_suggestion))
                                self:writeRest()
                                self:closeDictionary()
                                self:onChangedUserDictionary(true)
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
