local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local FileSearcher = InputContainer:extend{
    case_sensitive = false,
    include_subfolders = true,
    include_metadata = false,
}

function FileSearcher:init()
    self:registerKeyEvents()
    if not self.ui.document then
        self.ui.menu:registerToMainMenu(self)
    end
end

function FileSearcher:registerKeyEvents()
    if Device:hasKeyboard() then
        self.key_events.ShowFileSearch = { { "Alt", "F" }, { "Ctrl", "F" } }
        self.key_events.ShowFileSearchBlank = { { "Alt", "Shift", "F" }, { "Ctrl", "Shift", "F" }, event = "ShowFileSearch", args = "" }
    end
end

function FileSearcher:addToMainMenu(menu_items)
    menu_items.file_search = {
        -- @translators Search for files by name.
        text = _("File search"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self:onShowFileSearch()
        end,
    }
    menu_items.file_search_results = {
        text = _("Last file search results"),
        callback = function()
            self:onShowSearchResults()
        end,
    }
end

function FileSearcher:onShowFileSearch(search_string)
    local search_dialog, check_button_case, check_button_subfolders, check_button_metadata
    local function _doSearch()
        local search_str = search_dialog:getInputText()
        if search_str == "" then return end
        FileSearcher.search_string = search_str
        UIManager:close(search_dialog)
        self.case_sensitive = check_button_case.checked
        self.include_subfolders = check_button_subfolders.checked
        self.include_metadata = check_button_metadata and check_button_metadata.checked
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            self:doSearch()
        end)
    end
    search_dialog = InputDialog:new{
        title = _("Enter text to search for in filename"),
        input = search_string or FileSearcher.search_string,
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
                        FileSearcher.search_path = G_reader_settings:readSetting("home_dir")
                        _doSearch()
                    end,
                },
                {
                    text = self.ui.file_chooser and _("Current folder") or _("Book folder"),
                    is_enter_default = true,
                    callback = function()
                        FileSearcher.search_path = self.ui.file_chooser and self.ui.file_chooser.path or self.ui:getLastDirFile()
                        _doSearch()
                    end,
                },
            },
        },
    }
    check_button_case = CheckButton:new{
        text = _("Case sensitive"),
        checked = self.case_sensitive,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_case)
    check_button_subfolders = CheckButton:new{
        text = _("Include subfolders"),
        checked = self.include_subfolders,
        parent = search_dialog,
    }
    search_dialog:addWidget(check_button_subfolders)
    if self.ui.coverbrowser then
        check_button_metadata = CheckButton:new{
            text = _("Also search in book metadata"),
            checked = self.include_metadata,
            parent = search_dialog,
        }
        search_dialog:addWidget(check_button_metadata)
    end
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

-- Helper function: This logic runs in a Lua Lane.
-- It must be pure Lua and only accept/return simple data types.
local function _getFileMatchesInLane(cancel_flag, params)
    local lfs = require("libs/libkoreader-lfs")
    -- IMPORTANT: Utf8Proc and util.fixUtf8 are NOT used here to avoid FFI issues in the lane.
    local stringStartsWith = function(str, start)
        return str:sub(1, #start) == start
    end

    local sys_folders = {
        ["/dev"] = true, ["/proc"] = true, ["/sys"] = true, ["/mnt/base-us"] = true,
    }

    -- Prepare search string pattern for the lane (NO lowercasing here)
    local search_string_pattern_lane = params.search_string
    if search_string_pattern_lane ~= "*" then
        -- Escape magic characters for string.find pattern matching
        search_string_pattern_lane = search_string_pattern_lane:gsub("%.","%%%.")
        search_string_pattern_lane = search_string_pattern_lane:gsub("%*","%.%*")
        search_string_pattern_lane = search_string_pattern_lane:gsub("%?","%.")
    end

    local matched_items = {} -- Stores { type, f, fullpath, attributes }

    local scan_dirs = { params.search_path }
    while #scan_dirs ~= 0 do
        if cancel_flag[1] then
            print("CANCELLED")
            return matched_items
        end -- Cooperative cancellation check
        local new_dirs = {}
        for _, d in ipairs(scan_dirs) do
            if cancel_flag[1] then
                print("CANCELLED")
                return matched_items
            end -- Cooperative cancellation check
            local ok, iter, dir_obj = pcall(lfs.dir, d)
            if ok then
                for f in iter, dir_obj do
                    if cancel_flag[1] then
                        print("CANCELLED")
                        return matched_items
                    end -- Cooperative cancellation check
                    local fullpath = "/" .. f
                    if d ~= "/" then
                        fullpath = d .. fullpath
                    end
                    local attributes = lfs.attributes(fullpath) or {}

                    local is_hidden = stringStartsWith(f, ".")

                    -- Filename matching in lane is now strictly case-sensitive
                    local name_matches_lane = (search_string_pattern_lane == "*" or f:find(search_string_pattern_lane))

                    if attributes.mode == "directory" and f ~= "." and f ~= ".."
                            and (params.show_hidden or not is_hidden) then
                        if params.include_subfolders and not sys_folders[fullpath] then
                            table.insert(new_dirs, fullpath)
                        end
                        if name_matches_lane then
                            table.insert(matched_items, { type = "dir", f = f, fullpath = fullpath, attributes = attributes })
                        end
                    elseif attributes.mode == "file" and not stringStartsWith(f, "._") then
                        if name_matches_lane then
                            table.insert(matched_items, { type = "file", f = f, fullpath = fullpath, attributes = attributes })
                        end
                    end
                end
            end
        end
        scan_dirs = new_dirs
    end
    return matched_items
end

-- Helper function: This logic runs on the Main Thread.
-- It relies on `self` to access UI/document-related objects.
function FileSearcher:_processLaneResultsOnMainThread(matched_items_from_lane, original_search_string, case_sensitive_flag, include_metadata_flag)
    local logger = require("logger")
    logger.dbg("Main :", matched_items_from_lane, original_search_string, case_sensitive_flag, include_metadata_flag)

    local fc = self.ui.file_chooser or FileChooser:new{ ui = self.ui }
    local collate = fc:getCollate()

    local final_dirs, final_files = {}, {}
    self.no_metadata_count = 0 -- Reset, counted here

    -- Prepare search string pattern for the main thread (with Utf8Proc and case sensitivity)
    local main_thread_search_string_pattern = original_search_string
    if main_thread_search_string_pattern ~= "*" then
        if not case_sensitive_flag then
            main_thread_search_string_pattern = Utf8Proc.lowercase(util.fixUtf8(main_thread_search_string_pattern, "?"))
        end
        -- Escape magic characters for string.find pattern matching
        main_thread_search_string_pattern = main_thread_search_string_pattern:gsub("%.","%%%.")
        main_thread_search_string_pattern = main_thread_search_string_pattern:gsub("%*","%.%*")
        main_thread_search_string_pattern = main_thread_search_string_pattern:gsub("%?","%.")
    end

    -- Internal helper for full matching logic (filename and metadata) on main thread
    local function _isMatchFull(filename_original, fullpath, is_file_type)
        if original_search_string == "*" then return true end

        local filename_for_match_mt = filename_original
        if not case_sensitive_flag then
            filename_for_match_mt = Utf8Proc.lowercase(util.fixUtf8(filename_original, "?"))
        end

        -- Check filename match
        if filename_for_match_mt:find(main_thread_search_string_pattern) then
            return true
        end

        -- Check metadata match (only for files, and if include_metadata_flag is true)
        if include_metadata_flag and is_file_type and DocumentRegistry:hasProvider(fullpath) then
            local book_props = self.ui.bookinfo:getDocProps(fullpath, nil, true)
            if next(book_props) ~= nil then
                return self.ui.bookinfo:findInProps(book_props, original_search_string, case_sensitive_flag)
            else
                self.no_metadata_count = self.no_metadata_count + 1
                -- If metadata search is enabled but no metadata found, consider it not a match
                return false
            end
        end
        return false
    end


    for _, item in ipairs(matched_items_from_lane) do
        local f, fullpath, attributes = item.f, item.fullpath, item.attributes

        if item.type == "dir" then
            -- Directories matched by name from lane get full re-evaluation
            if _isMatchFull(f, fullpath, false) then
                table.insert(final_dirs, fc:getListItem(nil, f, fullpath, attributes, collate))
            end
        elseif item.type == "file" then
            -- Files need full main-thread checks (supported type, FileChooser:show_file, and then name/metadata match)
            local is_supported = DocumentRegistry:hasProvider(fullpath)
            local file_passes_main_checks = (FileChooser.show_unsupported or is_supported) and fc:show_file(f)

            if file_passes_main_checks then
                if _isMatchFull(f, fullpath, true) then
                    table.insert(final_files, fc:getListItem(nil, f, fullpath, attributes, collate))
                end
            end
        end
    end
    return final_dirs, final_files, self.no_metadata_count
end

-- FileSearcher:doSearch() orchestrates the lane and main thread processing
function FileSearcher:doSearch()
    local search_hash = FileSearcher.search_path .. (FileSearcher.search_string or "") ..
        tostring(self.case_sensitive) .. tostring(self.include_subfolders) .. tostring(self.include_metadata)
    local not_cached = FileSearcher.search_hash ~= search_hash

    if not_cached then
        local Trapper = require("ui/trapper")
        local InfoMessage = require("ui/widget/infomessage")
        local UIManager = require("ui/uimanager")

        local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
        UIManager:show(info)
        UIManager:forceRePaint()

        -- Prepare parameters for the lane (only simple values, no Utf8Proc/self/etc.)
        local lane_params = {
            search_path = FileSearcher.search_path,
            search_string = FileSearcher.search_string, -- Lane gets original string for case-sensitive find
            include_subfolders = self.include_subfolders,
            show_hidden = FileChooser.show_hidden, -- Assuming this is a static value available globally
        }

        local bound_lane_task = function(cancel_flag)
            return _getFileMatchesInLane(cancel_flag, lane_params)
        end
        local matched_items_from_lane = Trapper:dismissableRunInLane(
            bound_lane_task, -- Pass the lane helper function
            info
        )

        UIManager:close(info)
        FileSearcher.search_hash = search_hash

        -- Process results from the lane on the main thread
        local final_dirs, final_files, no_metadata_count = self:_processLaneResultsOnMainThread(
            matched_items_from_lane,
            FileSearcher.search_string, -- Pass original search string for main thread processing
            self.case_sensitive,        -- Pass case_sensitive flag for main thread processing
            self.include_metadata       -- Pass include_metadata flag for main thread processing
        )
        self.no_metadata_count = no_metadata_count

        FileSearcher.search_results = (self.ui.file_chooser or FileChooser:new{ ui = self.ui }):genItemTable(final_dirs, final_files)
    end

    if #FileSearcher.search_results > 0 then
        self:onShowSearchResults(not_cached)
    else
        self:showSearchResultsMessage(true)
    end
end

function FileSearcher:showSearchResultsMessage(no_results)
    local text = no_results and T(_("No results for '%1'."), FileSearcher.search_string)
    if self.no_metadata_count == 0 then
        UIManager:show(ConfirmBox:new{
            text = text,
            icon = "notice-info",
            ok_text = _("File search"),
            ok_callback = function()
                self:onShowFileSearch()
            end,
        })
    else
        local txt = T(N_("1 book has been skipped.", "%1 books have been skipped.",
            self.no_metadata_count), self.no_metadata_count) .. "\n" ..
            _("Not all books metadata extracted yet.\nExtract metadata now?")
        text = no_results and text .. "\n\n" .. txt or txt
        UIManager:show(ConfirmBox:new{
            text = text,
            ok_text = _("Extract"),
            ok_callback = function()
                if not no_results then
                    self.booklist_menu.close_callback()
                end
                self.ui.coverbrowser:extractBooksInDirectory(FileSearcher.search_path)
            end,
        })
    end
end

function FileSearcher:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileSearcher:onShowSearchResults(not_cached)
    if not not_cached and FileSearcher.search_results == nil then
        self:onShowFileSearch()
        return true
    end
    -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "filesearcher",
        subtitle = T(_("Query: %1"), FileSearcher.search_string),
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:setSelectMode() end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowSearchResults(not_cached) end,
    }
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        if self.selected_files then
            self.selected_files = nil
            for _, item in ipairs(FileSearcher.search_results) do
                item.dim = nil
            end
        end
    end
    self:updateItemTable(FileSearcher.search_results)
    UIManager:show(self.booklist_menu)
    if not_cached and self.no_metadata_count ~= 0 then
        self:showSearchResultsMessage()
    end
    return true
end

function FileSearcher:updateItemTable(item_table)
    if item_table == nil then
        item_table = self.booklist_menu.item_table
    end
    local title = T(_("Search results (%1)"), #item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1)
end

function FileSearcher:onMenuSelect(item)
    if lfs.attributes(item.path) == nil then return end
    if self._manager.selected_files then
        if item.is_file then
            item.dim = not item.dim and true or nil
            self._manager.selected_files[item.path] = item.dim
            self._manager:updateItemTable()
        end
    else
        if item.is_file then
            if DocumentRegistry:hasProvider(item.path, nil, true) then
                self.close_callback()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.openFile(self.ui, item.path)
            end
        else
            self._manager.update_files = nil
            self.close_callback()
            if self.ui.file_chooser then
                local pathname = util.splitFilePathName(item.path)
                self.ui.file_chooser:changeToPath(pathname, item.path)
            else -- called from Reader
                self.ui:onClose()
                self.ui:showFileManager(item.path)
            end
        end
    end
end

function FileSearcher:onMenuHold(item)
    if self._manager.selected_files or lfs.attributes(item.path) == nil then return true end
    local file = item.path
    local is_file = item.is_file or false
    self.file_dialog = nil

    local function close_dialog_callback()
        UIManager:close(self.file_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.file_dialog)
        self.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.file_dialog)
        self._manager:updateItemTable()
        self._manager.files_updated = true
    end
    local function close_menu_refresh_callback()
        self._manager.files_updated = true
        self.close_callback()
    end

    local buttons = {}
    local book_props, is_currently_opened
    if is_file then
        local has_provider = DocumentRegistry:hasProvider(file)
        local been_opened = BookList.hasBookBeenOpened(file)
        local doc_settings_or_file = file
        if has_provider or been_opened then
            book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)
            is_currently_opened = file == (self.ui.document and self.ui.document.file)
            if is_currently_opened then
                doc_settings_or_file = self.ui.doc_settings
                if not book_props then
                    book_props = self.ui.doc_props
                    book_props.has_cover = true
                end
            elseif been_opened then
                doc_settings_or_file = BookList.getDocSettings(file)
                if not book_props then
                    local props = doc_settings_or_file:readSetting("doc_props")
                    book_props = self.ui.bookinfo.extendProps(props, file)
                    book_props.has_cover = true
                end
            end
            table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
            table.insert(buttons, {}) -- separator
            table.insert(buttons, {
                filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
                self._manager.ui.collections:genAddToCollectionButton(file, close_dialog_callback, close_dialog_update_callback),
            })
        end
        if Device:canExecuteScript(file) then
            table.insert(buttons, {
                filemanagerutil.genExecuteScriptButton(file, close_dialog_menu_callback)
            })
        end
        if FileManagerConverter:isSupported(file) then
            table.insert(buttons, {
                FileManagerConverter:genConvertButton(file, close_dialog_callback, close_menu_refresh_callback)
            })
        end
        table.insert(buttons, {
            {
                text = _("Delete"),
                enabled = not is_currently_opened,
                callback = function()
                    local function post_delete_callback()
                        table.remove(FileSearcher.search_results, item.idx)
                        table.remove(self.item_table, item.idx)
                        close_dialog_update_callback()
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager:showDeleteFileDialog(file, post_delete_callback)
                end,
            },
            {
                text = _("Open with…"),
                callback = function()
                    close_dialog_callback()
                    local FileManager = require("apps/filemanager/filemanager")
                    FileManager.showOpenWithDialog(self.ui, file)
                end,
            },
        })
        table.insert(buttons, {
            filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
            filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
        })
        if has_provider then
            table.insert(buttons, {
                filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
                filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
            })
        end
    else -- folder
        table.insert(buttons, {
            filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        })
    end

    if self._manager.file_dialog_added_buttons ~= nil then
        for _, row_func in ipairs(self._manager.file_dialog_added_buttons) do
            local row = row_func(file, true, book_props)
            if row ~= nil then
                table.insert(buttons, row)
            end
        end
    end

    self.file_dialog = ButtonDialog:new{
        title = is_file and BD.filename(file) or BD.directory(file),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileSearcher.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.filesearcher.booklist_menu
end

function FileSearcher:setSelectMode()
    if self.selected_files then
        self:showSelectModeDialog()
    else
        self.selected_files = {}
        self.booklist_menu:setTitleBarLeftIcon("check")
    end
end

function FileSearcher:showSelectModeDialog()
    local item_table = self.booklist_menu.item_table
    local select_count = util.tableSize(self.selected_files)
    local actions_enabled = select_count > 0
    local title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
        or _("No files selected")
    local select_dialog
    local buttons = {
        {
            {
                text = _("Deselect all"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    for file in pairs (self.selected_files) do
                        self.selected_files[file] = nil
                    end
                    for _, item in ipairs(item_table) do
                        item.dim = nil
                    end
                    self:updateItemTable()
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(select_dialog)
                    for _, item in ipairs(item_table) do
                        if item.is_file then
                            item.dim = true
                            self.selected_files[item.path] = true
                        end
                    end
                    self:updateItemTable()
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self.selected_files = nil
                    self.booklist_menu:setTitleBarLeftIcon("appbar.menu")
                    if actions_enabled then
                        for _, item in ipairs(item_table) do
                            item.dim = nil
                        end
                    end
                    self:updateItemTable()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    self.files_updated = nil -- refresh fm later
                    self.booklist_menu.close_callback()
                    if self.ui.file_chooser then
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        self.ui.file_chooser:refreshPath()
                    else -- called from Reader
                        self.ui:onClose()
                        self.ui:showFileManager(FileSearcher.search_path .. "/", selected_files)
                    end
                end,
            },
        },
    }
    select_dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(select_dialog)
end

function FileSearcher:onBookMetadataChanged()
    if self.booklist_menu then
        self.booklist_menu:updateItems()
    end
end

function FileSearcher:onCloseWidget()
    if self.booklist_menu then
        self.booklist_menu.close_callback()
    end
end

return FileSearcher
