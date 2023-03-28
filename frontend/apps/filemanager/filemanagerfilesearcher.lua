local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CheckButton = require("ui/widget/checkbutton")
local CenterContainer = require("ui/widget/container/centercontainer")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local BaseUtil = require("ffi/util")
local Utf8Proc = require("ffi/utf8proc")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local Screen = require("device").screen
local T = BaseUtil.template

local FileSearcher = WidgetContainer:extend{
    case_sensitive = false,
    include_subfolders = true,
    include_metadata = false,
}

function FileSearcher:init()
end

function FileSearcher:onShowFileSearch(search_string)
    local search_dialog
    local check_button_case, check_button_subfolders, check_button_metadata
    search_dialog = InputDialog:new{
        title = _("Enter text to search for in filename"),
        input = search_string or self.search_value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(search_dialog)
                    end,
                },
                {
                    text = _("Home folder"),
                    enabled = G_reader_settings:has("home_dir"),
                    callback = function()
                        self.search_value = search_dialog:getInputText()
                        if self.search_value == "" then return end
                        UIManager:close(search_dialog)
                        self.path = G_reader_settings:readSetting("home_dir")
                        self:doSearch()
                    end,
                },
                {
                    text = self.ui.file_chooser and _("Current folder") or _("Book folder"),
                    is_enter_default = true,
                    callback = function()
                        self.search_value = search_dialog:getInputText()
                        if self.search_value == "" then return end
                        UIManager:close(search_dialog)
                        self.path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        self:doSearch()
                    end,
                },
            },
        },
    }

    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = search_dialog,
        callback = function()
            self.case_sensitive = check_button_case.checked
        end,
    }
    search_dialog:addWidget(check_button_case)
    check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = search_dialog,
        callback = function()
            self.include_subfolders = check_button_subfolders.checked
        end,
    }
    search_dialog:addWidget(check_button_subfolders)
    if self.ui.coverbrowser then
        check_button_metadata = CheckButton:new{
            text = _("Also search in book metadata"),
            checked = self.include_metadata,
            parent = search_dialog,
            callback = function()
                self.include_metadata = check_button_metadata.checked
            end,
        }
        search_dialog:addWidget(check_button_metadata)
    end

    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
end

function FileSearcher:doSearch()
    local results
    local dirs, files = self:getList()
    -- If we have a FileChooser instance, use it, to be able to make use of its natsort cache
    if self.ui.file_chooser then
        results = self.ui.file_chooser:genItemTable(dirs, files)
    else
        results = FileChooser:genItemTable(dirs, files)
    end
    if #results > 0 then
        self:showSearchResults(results)
    else
        self:showSearchResultsMessage(true)
    end
end

function FileSearcher:getList()
    self.no_metadata_count = 0
    local sys_folders = { -- do not search in sys_folders
        ["/dev"] = true,
        ["/proc"] = true,
        ["/sys"] = true,
    }
    local show_hidden = G_reader_settings:isTrue("show_hidden")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local collate = G_reader_settings:readSetting("collate")
    local keywords = self.search_value
    if keywords ~= "*" then -- one * to show all files
        if not self.case_sensitive then
            keywords = Utf8Proc.lowercase(util.fixUtf8(keywords, "?"))
        end
        -- replace '.' with '%.'
        keywords = keywords:gsub("%.","%%%.")
        -- replace '*' with '.*'
        keywords = keywords:gsub("%*","%.%*")
        -- replace '?' with '.'
        keywords = keywords:gsub("%?","%.")
    end

    local dirs, files = {}, {}
    local scan_dirs = {self.path}
    while #scan_dirs ~= 0 do
        local new_dirs = {}
        -- handle each dir
        for _, d in ipairs(scan_dirs) do
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
                            and (show_hidden or not util.stringStartsWith(f, "."))
                            and FileChooser:show_dir(f) then
                        if self.include_subfolders and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        end
                        if self:isFileMatch(f, fullpath, keywords) then
                            table.insert(dirs, FileChooser:getListItem(f, fullpath, attributes))
                        end
                    -- Always ignore macOS resource forks, too.
                    elseif attributes.mode == "file" and not util.stringStartsWith(f, "._")
                            and (show_unsupported or DocumentRegistry:hasProvider(fullpath))
                            and FileChooser:show_file(f) then
                        if self:isFileMatch(f, fullpath, keywords, true) then
                            table.insert(files, FileChooser:getListItem(f, fullpath, attributes, collate))
                        end
                    end
                end
            end
        end
        scan_dirs = new_dirs
    end
    return dirs, files
end

function FileSearcher:isFileMatch(filename, fullpath, keywords, is_file)
    local metadata_keys = {
        "authors",
        "title",
        "series",
        "description",
        "keywords",
        "language",
    }
    if keywords == "*" then
        return true
    end
    if not self.case_sensitive then
        filename = Utf8Proc.lowercase(util.fixUtf8(filename, "?"))
    end
    if string.find(filename, keywords) then
        return true
    end
    if self.include_metadata and is_file and DocumentRegistry:hasProvider(fullpath) then
        local book_props = self.ui.coverbrowser:getBookInfo(fullpath) or
                           FileManagerBookInfo:getBookProps(fullpath, nil, true)
        if next(book_props) ~= nil then
            for _, key in ipairs(metadata_keys) do
                local prop = book_props[key]
                if prop and prop ~= "" then
                    if not self.case_sensitive then
                        prop = Utf8Proc.lowercase(util.fixUtf8(prop, "?"))
                    end
                    if key == "description" then
                        prop = util.htmlToPlainTextIfHtml(prop)
                    end
                    if string.find(prop, keywords) then
                        return true
                    end
                end
            end
        else
            self.no_metadata_count = self.no_metadata_count + 1
        end
    end
end

function FileSearcher:showSearchResultsMessage(no_results)
    local text = no_results and T(_("No results for '%1'."), self.search_value)
    if self.no_metadata_count == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = text })
    else
        local txt = T(N_("1 book has been skipped.", "%1 books have been skipped.",
            self.no_metadata_count), self.no_metadata_count) .. "\n" ..
            _("Not all books metadata extracted yet.\nExtract metadata now?")
        text = no_results and text .. "\n\n" .. txt or txt
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = text,
            ok_text = _("Extract"),
            ok_callback = function()
                if not no_results then
                    self.search_menu.close_callback()
                end
                self.ui.coverbrowser:extractBooksInDirectory(self.path)
            end
        })
    end
end

function FileSearcher:showSearchResults(results)
    local menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
    }
    self.search_menu = Menu:new{
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        show_parent = menu_container,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        handle_hold_on_hold_release = true,
        _manager = self,
    }
    table.insert(menu_container, self.search_menu)
    self.search_menu.close_callback = function()
        UIManager:close(menu_container)
    end
    self.search_menu:switchItemTable(T(_("Search results (%1)"), #results), results)
    UIManager:show(menu_container)
    if self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
end

function FileSearcher:onMenuSelect(item)
    local dialog
    local buttons = {}
    if item.is_file then
        table.insert(buttons, {
            {
                text = _("Book information"),
                callback = function()
                    UIManager:close(dialog)
                    FileManagerBookInfo:show(item.path)
                end,
            },
            {
                text = _("Open"),
                enabled = DocumentRegistry:hasProvider(item.path),
                callback = function()
                    UIManager:close(dialog)
                    self.close_callback()
                    require("apps/reader/readerui"):showReader(item.path)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
        {
            text = _("Show folder"),
            callback = function()
                UIManager:close(dialog)
                self.close_callback()
                self._manager:showFolder(item.path)
            end,
        },
    })
    dialog = ButtonDialogTitle:new{
        title = item.path,
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function FileSearcher:onMenuHold(item)
    if item.is_file then
        if DocumentRegistry:hasProvider(item.path) then
            self.close_callback()
            require("apps/reader/readerui"):showReader(item.path)
        end
    else
        self.close_callback()
        self._manager:showFolder(item.path)
    end
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
