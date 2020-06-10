local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")
local Screen = require("device").screen
local CenterContainer = require("ui/widget/container/centercontainer")
local Menu = require("ui/widget/menu")
local InputDialog = require("ui/widget/inputdialog")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Font = require("ui/font")
local _ = require("gettext")
local Helpers = require("extensions/helpers")

local Characters = WidgetContainer:new {

    name = "characters",
    is_doc_only = true,

    source_file = nil,
    source_file_handle = nil,

    characters = {},

    -- guard against destroying all characters because of bugs
    prevent_all_characters_destruction = true,
    characters_count_at_init = false,

    filtered_characters = {},

    last_character = '',

    characters_chooser_menu = nil,
    characters_inner_menu = nil,

    character_dialog = nil,

    items_per_page = G_reader_settings:readSetting("items_per_page") or 16,

    ebooks = {},
    current_ebook = '',
    other_ebooks = {},

    filter = '',
    previous_filter = '',

    needle_for_subpage = '',
    selected_text = '',

    longest_item = 0,

    -- handy when there is little storage room remaining on a device:
    delete_backup_files = false,

    garbage = nil,
}

function Characters:init()

    local current_ebook = G_reader_settings:readSetting("lastfile")

    self.current_ebook = string.gsub(current_ebook, '^.+/', '')

    -- plugin needs a settings file characters.lua in the settings dir, with a table containing the table "charactes":
    local source_file = DataStorage:getSettingsDir() .. "/characters.lua"

    if self.delete_backup_files then
        self:deleteBackupCharacterFiles()
    end

    self.source_file_handle = LuaSettings:open(source_file)

    self.ebooks = self.source_file_handle:readSetting('characters') or {}

    self.characters = self.ebooks[self.current_ebook] or {}

    -- it is possible to copy characters defined for other ebooks to the current ebook, so you don't have to manually define them again. Handy for ebooks in a series:
    self:getOtherEbooks()

    if self.characters_count_at_init == false then
        self.characters_count_at_init = #self.characters
    end

    if self.characters_count_at_init <= 1 then
        self.prevent_all_characters_destruction = false
    end
end

function Characters:getOtherEbooks()

    if #self.other_ebooks == 0 then

        -- determine other ebooks:
        for file, __ in pairs(self.ebooks) do
            if file ~= self.current_ebook then
                table.insert(self.other_ebooks, file)
            else
                self.garbage = __
            end
        end

    end
end

function Characters:reset()

    self.filter = ''
    self.filtered_characters = {}
    self.last_character = ''
 end

-- reclaim disk space:
function Characters:deleteBackupCharacterFiles()

    if not self.delete_backup_files then
        return
    end

    local settingsfolder = DataStorage:getSettingsDir() .. '/'
    local file_exists

    local to_be_deleted = {
        'characters.lua.old',
    }

    for __, target in ipairs(to_be_deleted) do

        target = settingsfolder .. target

        file_exists = Helpers:exists(target)

        if file_exists ~= false then

            Helpers:remove(target)

            self.garbage = __
        end
    end
end

-- Determine whether a character has already been saved. Fuzzy search supported (only 1 keyword derived from the terms in the search string has to match):

function Characters:hasAlreadyBeenSaved(character)

    local keywords = string.lower(character)

    -- if a search string contains multiple strings, they must all be found:
    if not string.match(keywords, ' ') then
        keywords = { keywords }
    else
        keywords = string.split(keywords, ' ')
    end

    local items_with_hits = {}

    for nr, saved_character in ipairs(self.characters) do

        local found = 0

        local haystack = string.lower(saved_character)

        -- prevent problems with hyphens:
        haystack = string.gsub(haystack, '%-', '')

        local hit_in_keyword = false

        for i, s in ipairs(keywords) do

            if s ~= 'the' and string.len(s) > 2 then

                self.garbage = i

                -- prevent problems with hyphens:
                s = string.gsub(s,'%-', '')

                if string.match(haystack, s) then

                    found = found + 1

                    -- give terms in saved character before double colon more weight:

                    if string.match(haystack, s .. '([a-z0-9A-Z,.;\'"() ]*):') then
                        found = found + 20
                        hit_in_keyword = true
                    end
                end
            end
        end

        if hit_in_keyword then
            table.insert(items_with_hits, {
                text = string.format('%02d', found),
                character = saved_character,
                characterno = nr,
            })
        end
    end

    if #items_with_hits > 0 then

        Helpers:table_sort_by_text_prop(items_with_hits)

        local item_with_most_hits = items_with_hits[#items_with_hits]

        -- to be able to show other characters which match the search term in the characters management:

        self.filter = character

        return {
            character = item_with_most_hits['character'],
            characterno = item_with_most_hits['characterno'],
        }
    end

    return nil
end

function Characters:onManageCharacters(characterno, force_repaint)

    self.characters_chooser_menu = CenterContainer:new {
        dimen = Screen:getSize(),
    }

    local iwidth
    local orientation = Screen:getScreenMode()

    if orientation == 'portrait' then

        iwidth = Helpers:getWideDialogWidth()

    else

        -- make width of dialog dependent on longest item:

        self:determineLongestItem()

        if self.longest_item <= 40 then
            iwidth = Helpers:getMiddleDialogWidth()
        else
            iwidth = Helpers:getWideDialogWidth()
        end
    end

    self.characters_inner_menu = Menu:new {
        show_parent = self.ui,
        width = iwidth,
        height = Screen:getHeight() - 120,
        no_title = false,
        parent = nil,
        has_close_button = true,
        is_popout = true,
        is_borderless = false,
        onMenuHold = self.onMenuHold,
        perpage = self.items_per_page,
        _manager = self,
    }

    table.insert(self.characters_chooser_menu, self.characters_inner_menu)
    self.characters_inner_menu.close_callback = function()

        UIManager:close(self.characters_chooser_menu)
        self.characters_chooser_menu = nil
    end

    local success = true

    if not force_repaint then

        success = self:updateCharactersTable(characterno)

        if success then
            UIManager:show(self.characters_chooser_menu)
        end

        -- force correctly drawn dialog borders:
    else
        UIManager:show(self.characters_chooser_menu)
        UIManager:close(self.characters_chooser_menu)

        self:onManageCharacters(characterno, false)
    end
end

function Characters:determineLongestItem()

    self.longest_item = 0

    for __, character in ipairs(self.characters) do

        local length = string.len(character)

        if length > self.longest_item then

            self.longest_item = length

            -- to keep the code inspection of the IDE silent:
            self.garbage = __
        end
    end
end

function Characters:showImportMenu(force_repaint)

    self.import_menu = CenterContainer:new {
        dimen = Screen:getSize(),
    }

    local iwidth = Helpers:getMiddleDialogWidth()

    local inner_menu = Menu:new {
        show_parent = self.ui,
        width = iwidth,
        height = Screen:getHeight() - 120,
        no_title = false,
        parent = nil,
        has_close_button = true,
        is_popout = true,
        is_borderless = false,
        perpage = self.items_per_page,
    }

    table.insert(self.import_menu, inner_menu)
    inner_menu.close_callback = function()

        UIManager:close(self.import_menu)
    end

    if not force_repaint then

        local item_table = self:updateOtherBooksTable()

        inner_menu:switchItemTable(tostring(#self.other_ebooks) .. ' andere boeken', item_table)

        UIManager:show(self.import_menu)

    -- force correctly drawn dialog borders:
    else
        UIManager:show(self.import_menu)
        UIManager:close(self.import_menu)

        self:showImportMenu(false)
    end

end

function Characters:importCharacters(nr, book)

    local other_ebook = self.other_ebooks[nr]

    self.characters = self.ebooks[other_ebook] or {}

    self.ebooks[self.current_ebook] = self.characters

    self:saveCharacters()

    self:onManageCharacters(nil, true)

    Helpers:alertInfo('Characters copied from ' .. book .. ' !', 2)
end

function Characters:updateOtherBooksTable()

    local item_table = {}
    local books = self.other_ebooks

    if #books > 0 then

        Helpers:table_sort_alphabetically(books)

        for nr, book in ipairs(books) do

            if book ~= self.current_ebook then

                local menu_item = {
                    text = Helpers:listItemNumber(nr, book),
                    callback = function()

                        UIManager:close(self.import_menu)

                        self:importCharacters(nr, book)
                    end,
                }

                table.insert(item_table, menu_item)
            end
        end

    else

        Helpers:alertError('No other books with character descriptions found!', 2)

        return false
    end

    return item_table
end

function Characters:updateCharactersTable(characterno)

    -- load all characters:
    --self:init()

    local item_table = {}
    local characters

    if string.len(self.filter) < 3 or self.filter ~= self.previous_filter then
        characters = self.characters or {}
    else
        characters = self.filtered_characters or {}
    end

    local filtered_count = 0
    local filtered_characters = {}

    local needle, haystack

    if #characters > 0 then

        Helpers:table_sort_alphabetically(characters)

        local previous_insertion_point = 0
        local filter_has_a_match

        for nr, item in ipairs(characters) do

            needle = string.lower(self.filter)
            haystack = string.lower(item)

            filter_has_a_match = string.len(self.filter) >= 3 and string.match(haystack, needle)

            if string.len(self.filter) < 3 or filter_has_a_match then

                local menu_item = {
                    text = Helpers:listItemNumber(nr, item),
                    character = item,
                    characterno = nr,
                    deletable = false,
                    editable = false,
                    callback = function()

                        UIManager:close(self.characters_inner_menu)

                        self.needle_for_subpage = item

                        Helpers:alertInfo(item, nil, function()
                            self:onManageCharacters(nil, true)
                        end)

                    end,
                }

                table.insert(item_table, menu_item)

                if filter_has_a_match then
                    filtered_count = filtered_count + 1
                    table.insert(filtered_characters, item)
                end
            end

            local factor_correction = 1

            local factor = self.items_per_page - factor_correction

            local filter_active = self.filter ~= nil and filtered_count > 0

            if (not filter_active and string.len(self.filter) < 3 and (nr % factor == 0 or nr == #characters)) or (filter_active and previous_insertion_point ~= filtered_count and (filtered_count % factor == 0 or nr == #characters)) then

                previous_insertion_point = filtered_count

                local filter_text = '   filter...'
                if self.filter ~= '' then
                    filter_text = '   reset filter...'
                end

                table.insert(item_table, {
                    text = filter_text,
                    deletable = false,
                    editable = false,
                    callback = function()

                        if self.filter == '' then
                            self:filterCharacters()
                        else
                            self.filter = ''
                            self:onManageCharacters(nil, true)
                            return
                        end

                    end,
                })
            end
        end

    -- no characters found:
    else

        table.insert(item_table, {
            text = '   import from another book...',
            deletable = false,
            editable = false,
            callback = function()

                self:showImportMenu(true)

            end,
        })
    end

    if #filtered_characters > 0 then
        self.filtered_characters = filtered_characters
    end

    -- try to stay on current page
    local select_number

    if self.characters_inner_menu.page and self.characters_inner_menu.perpage then

        select_number = (self.characters_inner_menu.page - 1) * self.characters_inner_menu.perpage + 1
    end

    local title
    local plural = 'Characters'

    if string.len(self.filter) >= 3 then

        -- when no characters found with the current filter:
        if filtered_count == 0 then

            Helpers:alertError('No characters found containing "' .. self.filter .. '"!' .. "\n\nManager dialog reset...", 2)

            self:reset()
            self:onManageCharacters(nil, true)

            return
        end

        if filtered_count == 1 then
            plural = 'Character'
        end

        title = tostring(filtered_count) .. ' ' .. plural .. ' - ' .. self.filter

    else

        if #characters == 1 then
            plural = 'Character'
        end

        title = tostring(#characters) .. ' ' .. plural
    end

    if #characters == 0 then
        title = 'Import characters'
    end

    -- goto page where recently displayed character can be found in the manager:

    if self.needle_for_subpage ~= '' then

        self.characters_inner_menu:switchItemTable(title, item_table, nil, {
            character = self.needle_for_subpage
        })

        self.needle_for_subpage = ''

    elseif characterno ~= nil then

        self.characters_inner_menu:switchItemTable(title, item_table, characterno)

    else

        self.characters_inner_menu:switchItemTable(title, item_table, select_number)
    end

    return true
end

function Characters:onSaveCharacter(character)

    self.selected_text = character

    local item = self:hasAlreadyBeenSaved(character)

    if item ~= nil then

        self:showCharacter(item)

        return
    end

    item = {
        character = character .. ': ',
        -- mark this as a new item:
        characterno = nil
    }

    self:editCharacter(item, false)
end

function Characters:saveCharacters()

    if self.characters_count_at_init and self.characters_count_at_init > 1 and #self.characters <= 1 then

        Helpers:alertError('The plugin tried to save ' .. tostring(#self.characters) .. ' characters. This is probably an error, therefor characters not saved.')

        return
    end

    -- was optionally set to a value by hasAlreadyBeenSaved(), so here we reset it:
    self.filter = ''

    self.source_file_handle:saveSetting('characters', self.ebooks)
    self.source_file_handle:flush()

    if self.delete_backup_files then
        self:deleteBackupCharacterFiles()
    end
end

function Characters:onMenuHold(item)

    local characters_manipulate_dialog

    characters_manipulate_dialog = ButtonDialog:new {
        buttons = {
            {
                {
                    text = 'Show...',
                    callback = function()

                        UIManager:close(characters_manipulate_dialog)

                        Helpers:alertInfo(item.character)

                        return false
                    end
                },
                {
                    text = _("Edit") .. '...',
                    callback = function()

                        UIManager:close(characters_manipulate_dialog)

                        self._manager:editCharacter(item, true)
                    end
                },
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(characters_manipulate_dialog)

                        Helpers:confirm('Doe you really want to delete this character?', function()

                            self._manager:deleteCharacter(item)
                        end)
                    end
                },
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(characters_manipulate_dialog)
                        return false
                    end
                },
            },
        }
    }
    UIManager:show(characters_manipulate_dialog)
    return true
end

function Characters:showCharacter(item)

    UIManager:show(MultiConfirmBox:new {
        text = item.character,
        face = Font:getFace('smallinfont', 17),
        padding = Screen:scaleBySize(9),
        show_icon = false,
        choice1_text_func = function()
            return 'Filter "' .. self.filter .. '"'
        end,
        choice1_callback = function()
            -- go to the subpage in the manager containing the currently displayed note:
            self:onManageCharacters(item.characterno, true)
            return false
        end,
        choice2_text_func = function()

            local label = _("Edit")

            if item.characterno == nil then
                label = 'Create'
            end

            return label
        end,
        choice2_callback = function()
            self.filter = ''
            self:editCharacter(item, false)
            return false
        end,
        cancel_text = 'New',
        cancel_callback = function()
            self.filter = ''
            item = {
                character = self.selected_text .. ': ',
                characterno = nil,
            }
            self:editCharacter(item, false)
            self.selected_text = ''
            return false
        end,
    })
end

function Characters:editCharacter(item, reload_manager)

    local edit_character_input

    local title = 'Edit character'

    if item.characterno == nil then
        title = 'Add character'
    end

    edit_character_input = InputDialog:new {
        title = title,
        input = Helpers:removeListItemNumber(item.character),
        input_type = "text",
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(edit_character_input)

                        if reload_manager then
                            self:updateCharactersTable(item.characterno)
                        end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = false,
                    callback = function()
                        self:renameCharacter(item, edit_character_input:getInputText())
                        UIManager:close(edit_character_input)

                        if reload_manager then
                            self:updateCharactersTable(item.characterno)
                        else
                            self:onManageCharacters(item.characterno, true)
                        end
                    end,
                },
            }
        },
    }
    UIManager:show(edit_character_input)
    edit_character_input:onShowKeyboard()
end

function Characters:filterCharacters()

    local filter_characters_input

    filter_characters_input = InputDialog:new {
        title = 'Filter characters',
        input = '',
        input_type = "text",
        allow_newline = false,
        cursor_at_end = true,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(filter_characters_input)

                        self:onManageCharacters(nil, true)
                    end,
                },
                {
                    text = 'Filter!',
                    is_enter_default = true,
                    callback = function()

                        self.previous_filter = self.filter

                        self.filter = filter_characters_input:getInputText()

                        UIManager:close(filter_characters_input)

                        self:onManageCharacters(nil, true)
                    end,
                },
            }
        },
    }
    UIManager:show(filter_characters_input)
    filter_characters_input:onShowKeyboard()
end

function Characters:renameCharacter(item, new_text)

    local characters = {}

    local is_new_character = item.characterno == nil

    -- add a new character:
    if is_new_character then

        characters = self.characters
        table.insert(characters, new_text)

        self.needle_for_subpage = new_text

    -- rename:
    else

        self.needle_for_subpage = ''

        for nr, character in ipairs(self.characters) do

            if nr == item.characterno then

                character = new_text
                self.needle_for_subpage = new_text
            end

            table.insert(characters, character)
        end
    end

    self:updateCharacterLists(characters)
    self:saveCharacters()
end

function Characters:updateCharacterLists(characters)

    self.characters = characters
    self.ebooks[self.current_ebook] = self.characters
end

function Characters:deleteCharacter(item)

    local characters = {}
    local position = 1
    for nr, character in ipairs(self.characters) do
        if nr ~= item.characterno then
            table.insert(characters, character)
        else
            position = nr
        end
    end

    self:updateCharacterLists(characters)
    self:saveCharacters()
    if position > #characters then
        position = #characters
    end
    self:updateCharactersTable(position)
end

return Characters
