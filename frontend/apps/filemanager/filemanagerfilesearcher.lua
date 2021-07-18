local CheckButton = require("ui/widget/checkbutton")
local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local VerticalGroup = require("ui/widget/verticalgroup")
local lfs = require("libs/libkoreader-lfs")
local BaseUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen

local FileSearcher = InputContainer:new{
    search_dialog = nil,

    --filesearcher
    -- state buffer
    dirs = {},
    files = {},
    results = {},
    items = 0,
    commands = nil,
}

function FileSearcher:readDir()
    local FileManager = require("apps/filemanager/filemanager")
    local ReaderUI = require("apps/reader/readerui")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    self.dirs = {self.path}
    self.files = {}
    while #self.dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for __, d in pairs(self.dirs) do
            -- handle files in d
            for f in lfs.dir(d) do
                local fullpath = d.."/"..f
                local attributes = lfs.attributes(fullpath) or {}
                -- Don't traverse hidden folders if we're not showing them
                if attributes.mode == "directory" and f ~= "." and f ~= ".."
                    and (G_reader_settings:isTrue("show_hidden") or not util.stringStartsWith(f, "."))
                    and FileChooser:show_dir(f)
                then
                    table.insert(new_dirs, fullpath)
                    table.insert(self.files, {
                        name = f,
                        text = f.."/",
                        attr = attributes,
                        callback = function()
                            FileManager:showFiles(fullpath)
                        end,
                    })
                -- Always ignore macOS resource forks, too.
                elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                    and (show_unsupported or DocumentRegistry:hasProvider(fullpath))
                    and FileChooser:show_file(f)
                then
                    table.insert(self.files, {
                        name = f,
                        text = f,
                        attr = attributes,
                        callback = function()
                            ReaderUI:showReader(fullpath)
                        end,
                    })
                end
            end
        end
        self.dirs = new_dirs
    end
end

function FileSearcher:setSearchResults()
    local keywords = self.search_value
    self.results = {}
    if keywords == "*" then -- one * to show all files
        self.results = self.files
    else
        if not self.case_sensitive then
            keywords = Utf8Proc.lowercase(util.fixUtf8(keywords, "?"))
        end
        -- replace '.' with '%.'
        keywords = keywords:gsub("%.","%%%.")
        -- replace '*' with '.*'
        keywords = keywords:gsub("%*","%.%*")
        -- replace '?' with '.'
        keywords = keywords:gsub("%?","%.")
        for __,f in pairs(self.files) do
            if self.case_sensitive then
                if string.find(f.name, keywords) then
                    table.insert(self.results, f)
                end
            else
                if string.find(Utf8Proc.lowercase(util.fixUtf8(f.name, "?")), keywords) then
                    table.insert(self.results, f)
                end
            end
        end
    end
    self.keywords = keywords
    self.items = #self.results
end

function FileSearcher:close()
    UIManager:close(self.search_dialog)
    self:readDir() --- @todo this probably doesn't need to be repeated once it's been done
    self:setSearchResults() --- @todo doesn't have to be repeated if the search term is the same
    if #self.results > 0 then
        self:showSearchResults()
    else
        UIManager:show(
            InfoMessage:new{
                text = BaseUtil.template(_("No results for '%1'."),
                                     self.search_value)
            }
        )
    end
end

function FileSearcher:onShowFileSearch()
    self.search_dialog = InputDialog:new{
        title = _("Enter filename to search for"),
        input = self.search_value,
        width = math.floor(Screen:getWidth() * 0.9),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.search_dialog:onClose()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    text = _("Home folder"),
                    enabled = G_reader_settings:has("home_dir"),
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == "" then return end
                        self.path = G_reader_settings:readSetting("home_dir")
                        self:close()
                    end,
                },
                {
                    text = _("Current folder"),
                    is_enter_default = true,
                    callback = function()
                        self.search_value = self.search_dialog:getInputText()
                        if self.search_value == "" then return end
                        self.path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        self:close()
                    end,
                },
            },
        },
    }
    -- checkbox
    self.check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = self.search_dialog,
        callback = function()
            if not self.check_button_case.checked then
                self.check_button_case:check()
                self.case_sensitive = true
            else
                self.check_button_case:unCheck()
                self.case_sensitive = false
            end
        end,
    }

    local checkbox_shift = math.floor((self.search_dialog.width - self.search_dialog._input_widget.width) / 2 + 0.5)
    local check_buttons = HorizontalGroup:new{
        HorizontalSpan:new{width = checkbox_shift},
        VerticalGroup:new{
            align = "left",
            self.check_button_case,
        },
    }

    -- insert check buttons before the regular buttons
    local nb_elements = #self.search_dialog.dialog_frame[1]
    table.insert(self.search_dialog.dialog_frame[1], nb_elements-1, check_buttons)

    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function FileSearcher:showSearchResults()
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
        height = Screen:getHeight() - (Size.margin.fullscreen_popout * 2),
        show_parent = menu_container,
        onMenuHold = self.onMenuHold,
        cface = Font:getFace("smallinfofont"),
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end

    local collate = G_reader_settings:readSetting("collate") or "strcoll"
    local reverse_collate = G_reader_settings:isTrue("reverse_collate")
    local sorting = FileChooser:getSortingFunction(collate, reverse_collate)

    table.sort(self.results, sorting)
    self.search_menu:switchItemTable(_("Search results"), self.results)
    UIManager:show(menu_container)
end

return FileSearcher
