local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CheckButton = require("ui/widget/checkbutton")
local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BaseUtil = require("ffi/util")
local Utf8Proc = require("ffi/utf8proc")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local Screen = require("device").screen
local T = require("ffi/util").template

local FileSearcher = WidgetContainer:extend{
    dirs = nil, -- table
    files = nil, -- table
    results = nil, -- table

    case_sensitive = false,
    include_subfolders = true,
}

local sys_folders = { -- do not search in sys_folders
    ["/dev"] = true,
    ["/proc"] = true,
    ["/sys"] = true,
}

function FileSearcher:init()
    self.dirs = {}
    self.files = {}
    self.results = {}
end

function FileSearcher:readDir()
    local ReaderUI = require("apps/reader/readerui")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    self.dirs = {self.path}
    self.files = {}
    while #self.dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for __, d in pairs(self.dirs) do
            -- handle files in d
            local ok, iter, dir_obj = pcall(lfs.dir, d)
            if ok then
                for f in iter, dir_obj do
                    local fullpath = "/" .. f
                    if d ~= "/" then
                        fullpath = d .. fullpath
                    end
                    local attributes = lfs.attributes(fullpath) or {}
                    -- Don't traverse hidden folders if we're not showing them
                    if attributes.mode == "directory" and f ~= "." and f ~= ".."
                        and (G_reader_settings:isTrue("show_hidden") or not util.stringStartsWith(f, "."))
                        and FileChooser:show_dir(f)
                    then
                        if self.include_subfolders and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        end
                        table.insert(self.files, {
                            dir = d,
                            name = f,
                            text = f.."/",
                            attr = attributes,
                            callback = function()
                                self:showFolder(fullpath .. "/")
                            end,
                        })
                    -- Always ignore macOS resource forks, too.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                        and (show_unsupported or DocumentRegistry:hasProvider(fullpath))
                        and FileChooser:show_file(f)
                    then
                        table.insert(self.files, {
                            dir = d,
                            name = f,
                            text = f,
                            mandatory = util.getFriendlySize(attributes.size or 0),
                            attr = attributes,
                            callback = function()
                                ReaderUI:showReader(fullpath)
                            end,
                        })
                    end
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

function FileSearcher:onShowFileSearch(search_string)
    self.search_dialog = InputDialog:new{
        title = _("Enter filename to search for"),
        input = search_string or self.search_value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
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

    self.check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = self.search_dialog,
        callback = function()
            self.case_sensitive = self.check_button_case.checked
        end,
    }
    self.search_dialog:addWidget(self.check_button_case)
    self.check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = self.search_dialog,
        callback = function()
            self.include_subfolders = self.check_button_subfolders.checked
        end,
    }
    self.search_dialog:addWidget(self.check_button_subfolders)

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
    self.search_menu:switchItemTable(T(_("Search results (%1)"), #self.results), self.results)
    UIManager:show(menu_container)
end

function FileSearcher:onMenuHold(item)
    local ReaderUI = require("apps/reader/readerui")
    local is_file = item.attr.mode == "file"
    local fullpath = item.dir .. "/" .. item.name .. (is_file and "" or "/")
    local buttons = {
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.results_dialog)
                end,
            },
            {
                text = _("Show folder"),
                callback = function()
                    UIManager:close(self.results_dialog)
                    self.close_callback()
                    self._manager:showFolder(fullpath)
                end,
            },
        },
    }
    if is_file then
        table.insert(buttons[1], {
            text = _("Open"),
            callback = function()
                UIManager:close(self.results_dialog)
                self.close_callback()
                ReaderUI:showReader(fullpath)
            end,
        })
    end

    self.results_dialog = ButtonDialogTitle:new{
        title = fullpath,
        buttons = buttons,
    }
    UIManager:show(self.results_dialog)
    return true
end

function FileSearcher:showFolder(path)
    if self.ui.file_chooser then
        local pathname = util.splitFilePathName(path)
        self.ui.file_chooser:changeToPath(pathname, path)
    else -- called from Reader
        self.ui:onClose()
        self.ui:showFileManager(path)
    end
end

return FileSearcher
