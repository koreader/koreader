local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = ffiUtil.template

local FileManagerCollection = WidgetContainer:extend{
    title = _("Collections"),
    default_collection_title = _("Favorites"),
    checkmark = "\u{2713}",
    empty_prop = "\u{0000}" .. _("N/A"), -- sorted first
}

function FileManagerCollection:init()
    self.show_mark = G_reader_settings:nilOrTrue("collection_show_mark")
    self.doc_props_cache = {}
    self.updated_collections = {}
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerCollection:addToMainMenu(menu_items)
    menu_items.favorites = {
        text = self.default_collection_title,
        callback = function()
            self:onShowColl()
        end,
    }
    menu_items.collections = {
        text = self.title,
        callback = function()
            self:onShowCollList()
        end,
    }
end

-- collection

function FileManagerCollection:getCollectionTitle(collection_name)
    return collection_name == ReadCollection.default_collection_name
        and self.default_collection_title -- favorites
         or collection_name
end

function FileManagerCollection:refreshFileManager()
    if self.files_updated then
        if self.ui.file_chooser then
            self.ui.file_chooser:refreshPath()
        end
        self.files_updated = nil
    end
end

function FileManagerCollection:onShowColl(collection_name)
    collection_name = collection_name or ReadCollection.default_collection_name
    ReadCollection:updateCollectionFromFolder(collection_name)
    -- This may be hijacked by CoverBrowser plugin and needs to be known as booklist_menu.
    self.booklist_menu = BookList:new{
        name = "collections",
        path = collection_name,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            if self.selected_files then
                self:showSelectModeDialog()
            else
                self:showCollDialog()
            end
        end,
        onLeftButtonHold = function()
            self:toggleSelectMode()
        end,
        onReturn = function()
            self.from_collection_name = self:getCollectionTitle(collection_name)
            self.booklist_menu.close_callback()
            self:onShowCollList()
        end,
        onMenuSelect = self.onMenuSelect,
        onMenuHold = self.onMenuHold,
        ui = self.ui,
        _manager = self,
        _recreate_func = function() self:onShowColl(collection_name) end,
        search_callback = function(search_string)
            self:onShowCollectionsSearchDialog(search_string, collection_name)
        end,
    }
    table.insert(self.booklist_menu.paths, true) -- enable onReturn button
    self.booklist_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.booklist_menu)
        self.booklist_menu = nil
        self.match_table = nil
        self.selected_files = nil
    end
    self:setCollate()
    self:updateItemTable()
    UIManager:show(self.booklist_menu)
    return true
end

function FileManagerCollection:updateItemTable(item_table, focused_file)
    if item_table == nil then
        item_table = {}
        for _, item in pairs(ReadCollection.coll[self.booklist_menu.path]) do
            if self:isItemMatch(item) then
                local item_tmp = {
                    file      = item.file,
                    text      = item.text,
                    order     = item.order,
                    attr      = item.attr,
                    mandatory = self.mandatory_func and self.mandatory_func(item) or util.getFriendlySize(item.attr.size or 0),
                }
                if self.item_func then
                    self.item_func(item_tmp, self.ui)
                end
                table.insert(item_table, item_tmp)
            end
        end
        if #item_table > 1 then
            table.sort(item_table, self.sorting_func)
        end
    end
    local title, subtitle = self:getBookListTitle(item_table)
    self.booklist_menu:switchItemTable(title, item_table, -1, focused_file and { file = focused_file }, subtitle)
end

function FileManagerCollection:isItemMatch(item)
    if self.match_table then
        if self.match_table.status then
            if self.match_table.status ~= BookList.getBookStatus(item.file) then
                return false
            end
        end
        if self.match_table.props then
            local doc_props = self.ui.bookinfo:getDocProps(item.file, nil, true)
            for prop, value in pairs(self.match_table.props) do
                if (doc_props[prop] or self.empty_prop) ~= value then
                    return false
                end
            end
        end
    end
    return true
end

function FileManagerCollection:getBookListTitle(item_table)
    local coll_name = self.booklist_menu.path
    local marker = self.getCollMarker(coll_name)
    local template = marker and "%1 (%2) " .. marker or "%1 (%2)"
    local title = T(template, self:getCollectionTitle(coll_name), #item_table)
    local subtitle = ""
    if self.match_table then
        subtitle = {}
        if self.match_table.status then
            local status_string = BookList.getBookStatusString(self.match_table.status, true)
            table.insert(subtitle, "\u{0000}" .. status_string) -- sorted first
        end
        if self.match_table.props then
            for prop, value in pairs(self.match_table.props) do
                table.insert(subtitle, T("%1 %2", self.ui.bookinfo.prop_text[prop], value))
            end
        end
        if #subtitle == 1 then
            subtitle = subtitle[1]
        else
            table.sort(subtitle)
            subtitle = table.concat(subtitle, " | ")
        end
    end
    return title, subtitle
end

function FileManagerCollection:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerCollection:onMenuSelect(item)
    if self._manager.selected_files then
        item.dim = not item.dim and true or nil
        self._manager.selected_files[item.file] = item.dim
        self:updateItems(1, true)
    else
        self.close_callback()
        if self.ui.document then
            if self.ui.document.file ~= item.file then
                self.ui:switchDocument(item.file)
            end
        else
            self.ui:openFile(item.file)
        end
    end
end

function FileManagerCollection:onMenuHold(item)
    if self._manager.selected_files then
        self._manager:showSelectModeDialog()
        return true
    end

    local file = item.file
    self.file_dialog = nil
    local book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)

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
    local is_currently_opened = file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    local doc_settings_or_file
    if is_currently_opened then
        doc_settings_or_file = self.ui.doc_settings
        if not book_props then
            book_props = self.ui.doc_props
            book_props.has_cover = true
        end
    else
        if BookList.hasBookBeenOpened(file) then
            doc_settings_or_file = BookList.getDocSettings(file)
            if not book_props then
                local props = doc_settings_or_file:readSetting("doc_props")
                book_props = self.ui.bookinfo.extendProps(props, file)
                book_props.has_cover = true
            end
        else
            doc_settings_or_file = file
        end
    end
    table.insert(buttons, filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_update_callback))
    table.insert(buttons, {}) -- separator
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(doc_settings_or_file, close_dialog_update_callback, is_currently_opened),
        self._manager:genAddToCollectionButton(file, close_dialog_callback, close_dialog_update_callback),
    })
    if Device:canExecuteScript(file) then
        table.insert(buttons, {
            filemanagerutil.genExecuteScriptButton(file, close_dialog_menu_callback)
        })
    end
    table.insert(buttons, {
        {
            text = _("Delete"),
            enabled = not is_currently_opened,
            callback = function()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showDeleteFileDialog(file, close_dialog_update_callback)
            end,
        },
        {
            text = _("Remove from collection"),
            callback = function()
                self._manager.updated_collections[self.path] = true
                ReadCollection:removeItem(file, self.path, true)
                close_dialog_update_callback()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        filemanagerutil.genBookInformationButton(doc_settings_or_file, book_props, close_dialog_callback),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, book_props, close_dialog_callback),
        filemanagerutil.genBookDescriptionButton(file, book_props, close_dialog_callback),
    })

    if self._manager.file_dialog_added_buttons ~= nil then
        for _, row_func in ipairs(self._manager.file_dialog_added_buttons) do
            local row = row_func(file, true, book_props)
            if row ~= nil then
                table.insert(buttons, row)
            end
        end
    end

    self.file_dialog = ButtonDialog:new{
        title = BD.filename(item.text),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.file_dialog)
    return true
end

function FileManagerCollection.getMenuInstance()
    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    return ui.collections.booklist_menu
end

function FileManagerCollection:toggleSelectMode(rebuild)
    if self.selected_files then
        if rebuild then
            self:updateItemTable()
        else
            for _, item in ipairs(self.booklist_menu.item_table) do
                item.dim = nil
            end
            self.booklist_menu:updateItems(1, true)
        end
        self.booklist_menu:setTitleBarLeftIcon("appbar.menu")
        self.selected_files = nil
    else
        self.booklist_menu:setTitleBarLeftIcon("check")
        self.selected_files = {}
    end
end

function FileManagerCollection:showSelectModeDialog()
    local collection_name = self.booklist_menu.path
    local item_table = self.booklist_menu.item_table
    local select_count = util.tableSize(self.selected_files)
    local actions_enabled = select_count > 0
    local title = actions_enabled and T(N_("1 book selected", "%1 books selected", select_count), select_count)
        or _("No books selected")
    local select_dialog
    local buttons = {
        {
            {
                text = _("Remove from collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Remove selected books from collection?"),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            UIManager:close(select_dialog)
                            self.updated_collections[collection_name] = true
                            for file in pairs(self.selected_files) do
                                ReadCollection:removeItem(file, collection_name, true)
                            end
                            self.files_updated = self.show_mark
                            self:toggleSelectMode(true)
                        end,
                    })
                end,
            },
        },
        {
            {
                text = _("Move to collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local caller_callback = function(selected_collections)
                        for name in pairs(selected_collections) do
                            self.updated_collections[name] = true
                        end
                        ReadCollection:addItemsMultiple(self.selected_files, selected_collections)
                        self.updated_collections[collection_name] = true
                        for file in pairs(self.selected_files) do
                            ReadCollection:removeItem(file, collection_name, true)
                        end
                        self.files_updated = self.show_mark
                        self:toggleSelectMode(true)
                    end
                    self:onShowCollList({}, caller_callback)
                end,
            },
            {
                text = _("Copy to collection"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local caller_callback = function(selected_collections)
                        for name in pairs(selected_collections) do
                            self.updated_collections[name] = true
                        end
                        ReadCollection:addItemsMultiple(self.selected_files, selected_collections)
                        self.files_updated = self.show_mark
                        self:toggleSelectMode()
                    end
                    self:onShowCollList({}, caller_callback)
                end,
            },
        },
        {}, -- separator
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
                    self.booklist_menu:updateItems(1, true)
                end,
            },
            {
                text = _("Select all"),
                callback = function()
                    UIManager:close(select_dialog)
                    for _, item in ipairs(item_table) do
                        item.dim = true
                        self.selected_files[item.file] = true
                    end
                    self.booklist_menu:updateItems(1, true)
                end,
            },
        },
        {
            {
                text = _("Exit select mode"),
                callback = function()
                    UIManager:close(select_dialog)
                    self:toggleSelectMode()
                end,
            },
            {
                text = _("Select in file browser"),
                enabled = actions_enabled,
                callback = function()
                    UIManager:close(select_dialog)
                    local selected_files = self.selected_files
                    local files_updated = self.files_updated
                    self.files_updated = nil -- refresh fm later
                    self.booklist_menu.close_callback()
                    if self.ui.document then
                        self.ui:onClose()
                        self.ui:showFileManager(self.ui.document.file, selected_files)
                    else
                        self.ui.selected_files = selected_files
                        self.ui.title_bar:setRightIcon("check")
                        if files_updated then
                            self.ui.file_chooser:refreshPath()
                        else -- dim only
                            self.ui.file_chooser:updateItems(1, true)
                        end
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

function FileManagerCollection:showCollDialog()
    local collection_name = self.booklist_menu.path
    local coll_not_empty = #self.booklist_menu.item_table > 0
    local coll_dialog
    local function genFilterByStatusButton(button_status)
        return {
            text = BookList.getBookStatusString(button_status),
            enabled = coll_not_empty,
            callback = function()
                UIManager:close(coll_dialog)
                util.tableSetValue(self, button_status, "match_table", "status")
                self:updateItemTable()
            end,
        }
    end
    local function genFilterByMetadataButton(button_text, button_prop)
        return {
            text = button_text,
            enabled = coll_not_empty,
            callback = function()
                UIManager:close(coll_dialog)
                local prop_values = {}
                for idx, item in ipairs(self.booklist_menu.item_table) do
                    local doc_prop = self.ui.bookinfo:getDocProps(item.file, nil, true)[button_prop]
                    if doc_prop == nil then
                        doc_prop = { self.empty_prop }
                    elseif button_prop == "series" then
                        doc_prop = { doc_prop }
                    elseif button_prop == "language" then
                        doc_prop = { doc_prop:lower() }
                    else -- "authors", "keywords"
                        doc_prop = util.splitToArray(doc_prop, "\n")
                    end
                    for _, prop in ipairs(doc_prop) do
                        prop_values[prop] = prop_values[prop] or {}
                        table.insert(prop_values[prop], idx)
                    end
                end
                self:showPropValueList(button_prop, prop_values)
            end,
        }
    end
    local buttons = {
        {{
            text = _("Collections"),
            callback = function()
                UIManager:close(coll_dialog)
                self.booklist_menu.close_callback()
                self:onShowCollList()
            end,
        }},
        {}, -- separator
        {
            genFilterByStatusButton("new"),
            genFilterByStatusButton("reading"),
        },
        {
            genFilterByStatusButton("abandoned"),
            genFilterByStatusButton("complete"),
        },
        {
            genFilterByMetadataButton(_("Filter by authors"), "authors"),
            genFilterByMetadataButton(_("Filter by series"), "series"),
        },
        {
            genFilterByMetadataButton(_("Filter by language"), "language"),
            genFilterByMetadataButton(_("Filter by keywords"), "keywords"),
        },
        {{
            text = _("Reset all filters"),
            enabled = self.match_table ~= nil,
            callback = function()
                UIManager:close(coll_dialog)
                self.match_table = nil
                self:updateItemTable()
            end,
        }},
        {}, -- separator
        {
            {
                text = _("Select"),
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    self:toggleSelectMode()
                end,
            },
            {
                text = _("Search"),
                enabled = coll_not_empty,
                callback = function()
                    UIManager:close(coll_dialog)
                    self:onShowCollectionsSearchDialog(nil, collection_name)
                end,
            },
        },
        {{
            text = _("Arrange books in collection"),
            enabled = coll_not_empty and self.match_table == nil,
            callback = function()
                UIManager:close(coll_dialog)
                self:showArrangeBooksDialog()
            end,
        }},
        {}, -- separator
        {{
            text = _("Add all books from a folder"),
            callback = function()
                UIManager:close(coll_dialog)
                self:addBooksFromFolder(false)
            end,
        }},
        {{
            text = _("Add all books from a folder and its subfolders"),
            callback = function()
                UIManager:close(coll_dialog)
                self:addBooksFromFolder(true)
            end,
        }},
        {{
            text = _("Add a book to collection"),
            callback = function()
                UIManager:close(coll_dialog)
                local PathChooser = require("ui/widget/pathchooser")
                local path_chooser = PathChooser:new{
                    path = G_reader_settings:readSetting("home_dir"),
                    select_directory = false,
                    onConfirm = function(file)
                        if not ReadCollection:isFileInCollection(file, collection_name) then
                            self.updated_collections[collection_name] = true
                            ReadCollection:addItem(file, collection_name)
                            self:updateItemTable(nil, file) -- show added item
                            self.files_updated = self.show_mark
                        end
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }},
    }
    if self.ui.document then
        local file = self.ui.document.file
        local is_in_collection = ReadCollection:isFileInCollection(file, collection_name)
        table.insert(buttons, {{
            text_func = function()
                return is_in_collection and _("Remove current book from collection") or _("Add current book to collection")
            end,
            callback = function()
                UIManager:close(coll_dialog)
                self.updated_collections[collection_name] = true
                if is_in_collection then
                    ReadCollection:removeItem(file, collection_name, true)
                    file = nil
                else
                    ReadCollection:addItem(file, collection_name)
                end
                self:updateItemTable(nil, file)
                self.files_updated = self.show_mark
            end,
        }})
    end
    coll_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(coll_dialog)
end

function FileManagerCollection:showPropValueList(prop, prop_values)
    local prop_menu
    local prop_item_table = {}
    for value, item_idxs in pairs(prop_values) do
        table.insert(prop_item_table, {
            text = value,
            mandatory = #item_idxs,
            callback = function()
                UIManager:close(prop_menu)
                util.tableSetValue(self, value, "match_table", "props", prop)
                local item_table = {}
                for _, idx in ipairs(item_idxs) do
                    table.insert(item_table, self.booklist_menu.item_table[idx])
                end
                self:updateItemTable(item_table)
            end,
        })
    end
    if #prop_item_table > 1 then
        table.sort(prop_item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
    end
    prop_menu = Menu:new{
        title = T("%1 (%2)", self.ui.bookinfo.prop_text[prop]:sub(1, -2), #prop_item_table),
        item_table = prop_item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
    }
    UIManager:show(prop_menu)
end

function FileManagerCollection:setCollate(collate_id, collate_reverse)
    local coll_settings = ReadCollection.coll_settings[self.booklist_menu.path]
    if collate_id == nil then
        collate_id = coll_settings.collate
    else
        coll_settings.collate = collate_id or nil
    end
    if collate_reverse == nil then
        collate_reverse = coll_settings.collate_reverse
    else
        coll_settings.collate_reverse = collate_reverse or nil
    end
    if collate_id then
        local collate = BookList.collates[collate_id]
        self.item_func = collate.item_func
        self.mandatory_func = collate.mandatory_func
        self.sorting_func, self.sort_cache = collate.init_sort_func(self.sort_cache)
        if collate_reverse then
            local sorting_func_unreversed = self.sorting_func
            self.sorting_func = function(a, b) return sorting_func_unreversed(b, a) end
        end
    else -- manual
        self.item_func = nil
        self.mandatory_func = nil
        self.sorting_func = function(a, b) return a.order < b.order end
    end
end

function FileManagerCollection:showArrangeBooksDialog()
    local collection_name = self.booklist_menu.path
    local coll_settings = ReadCollection.coll_settings[collection_name]
    local curr_collate_id = coll_settings.collate
    local arrange_dialog
    local function genCollateButton(collate_id)
        local collate = BookList.collates[collate_id]
        return {
            text = collate.text .. (curr_collate_id == collate_id and "  ✓" or ""),
            callback = function()
                if curr_collate_id ~= collate_id then
                    UIManager:close(arrange_dialog)
                    self.updated_collections[collection_name] = true
                    self:setCollate(collate_id)
                    self:updateItemTable()
                end
            end,
        }
    end
    local buttons = {
        {
            genCollateButton("authors"),
            genCollateButton("title"),
        },
        {
            genCollateButton("keywords"),
            genCollateButton("series"),
        },
        {
            genCollateButton("natural"),
            genCollateButton("strcoll"),
        },
        {
            genCollateButton("size"),
            genCollateButton("access"),
        },
        {{
            text = _("Reverse sorting") .. (coll_settings.collate_reverse and "  ✓" or ""),
            enabled = curr_collate_id and true or false, -- disabled for manual sorting
            callback = function()
                UIManager:close(arrange_dialog)
                self.updated_collections[collection_name] = true
                self:setCollate(nil, not coll_settings.collate_reverse)
                self:updateItemTable()
            end,
        }},
        {}, -- separator
        {{
            text = _("Manual sorting") .. (curr_collate_id == nil and "  ✓" or ""),
            callback = function()
                UIManager:close(arrange_dialog)
                local sort_widget
                sort_widget = SortWidget:new{
                    title = _("Arrange books in collection"),
                    item_table = self.booklist_menu.item_table,
                    callback = function()
                        ReadCollection:updateCollectionOrder(collection_name, sort_widget.item_table)
                        self.updated_collections[collection_name] = true
                        self:setCollate(false, false)
                        self:updateItemTable()
                    end,
                }
                UIManager:show(sort_widget)
            end,
        }},
    }
    arrange_dialog = ButtonDialog:new{
        title = _("Sort by"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(arrange_dialog)
end

function FileManagerCollection:addBooksFromFolder(include_subfolders)
    local PathChooser = require("ui/widget/pathchooser")
    local path_chooser = PathChooser:new{
        path = G_reader_settings:readSetting("home_dir"),
        select_file = false,
        onConfirm = function(folder)
            local count = ReadCollection:updateCollectionFromFolder(self.booklist_menu.path,
                { [folder] = { subfolders = include_subfolders } })
            local text
            if count == 0 then
                text = _("No books added to collection")
            else
                self.updated_collections[self.booklist_menu.path] = true
                text = T(N_("1 book added to collection", "%1 books added to collection", count), count)
                self:updateItemTable()
                self.files_updated = self.show_mark
            end
            UIManager:show(InfoMessage:new{ text = text })
        end,
    }
    UIManager:show(path_chooser)
end

function FileManagerCollection:onBookMetadataChanged(prop_updated)
    local file
    if prop_updated then
        file = prop_updated.filepath
        self.doc_props_cache[file] = prop_updated.doc_props
    end
    if self.booklist_menu then
        self:updateItemTable(nil, file) -- keep showing the changed file after resorting
    end
end

-- collection list

function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
    local title_bar_left_icon
    if file_or_selected_collections ~= nil then -- select mode
        title_bar_left_icon = "check"
        if type(file_or_selected_collections) == "string" then -- checkmark collections containing the file
            self.selected_collections = ReadCollection:getCollectionsWithFile(file_or_selected_collections)
        else
            self.selected_collections = util.tableDeepCopy(file_or_selected_collections)
        end
    else
        title_bar_left_icon = "appbar.menu"
        self.selected_collections = nil
    end
    self.coll_list = Menu:new{
        path = true, -- draw focus
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = title_bar_left_icon,
        onLeftButtonTap = function() self:showCollListDialog(caller_callback, no_dialog) end,
        onMenuChoice = self.onCollListChoice,
        onMenuHold = self.onCollListHold,
        _manager = self,
        _recreate_func = function() self:onShowCollList(file_or_selected_collections, caller_callback, no_dialog) end,
    }
    self.coll_list.close_callback = function(force_close)
        if force_close or self.selected_collections == nil then
            self:refreshFileManager()
            UIManager:close(self.coll_list)
            self.coll_list = nil
        end
    end
    self:updateCollListItemTable(true) -- init
    UIManager:show(self.coll_list)
    return true
end

function FileManagerCollection:updateCollListItemTable(do_init, item_number)
    local item_table
    if do_init then
        item_table = {}
        for coll_name in pairs(ReadCollection.coll) do
            local mandatory
            if self.selected_collections then
                mandatory = self.selected_collections[coll_name] and self.checkmark or "  "
                self.coll_list.items_mandatory_font_size = self.coll_list.font_size
            else
                mandatory = self.getCollListItemMandatory(coll_name)
            end
            table.insert(item_table, {
                text      = self:getCollectionTitle(coll_name),
                mandatory = mandatory,
                name      = coll_name,
                order     = ReadCollection.coll_settings[coll_name].order,
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2) return v1.order < v2.order end)
        end
    else
        item_table = self.coll_list.item_table
    end
    local title = T(_("Collections (%1)"), #item_table)
    local itemmatch, subtitle
    if self.selected_collections then
        local selected_nb = util.tableSize(self.selected_collections)
        subtitle = self.selected_collections and T(_("Selected: %1"), selected_nb)
        if do_init and selected_nb > 0 then -- show first collection containing the long-pressed book
            for i, item in ipairs(item_table) do
                if self.selected_collections[item.name] then
                    item_number = i
                    break
                end
            end
        end
    elseif self.from_collection_name ~= nil then
        itemmatch = { text = self.from_collection_name }
        self.from_collection_name = nil
    end
    self.coll_list:switchItemTable(title, item_table, item_number or -1, itemmatch, subtitle)
end

function FileManagerCollection.getCollListItemMandatory(coll_name)
    local marker = FileManagerCollection.getCollMarker(coll_name)
    local coll_nb = util.tableSize(ReadCollection.coll[coll_name])
    return marker and marker .. " " .. coll_nb or coll_nb
end

function FileManagerCollection.getCollMarker(coll_name)
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local marker
    if coll_settings.folders then
        marker = "\u{F114}"
    end
    if util.tableGetValue(coll_settings, "filter", "add", "filetype") then
        marker = marker and "\u{F114} \u{F0B0}" or "\u{F0B0}"
    end
    return marker
end

function FileManagerCollection:onCollListChoice(item)
    if self._manager.selected_collections then
        if item.mandatory == self._manager.checkmark then
            self.item_table[item.idx].mandatory = "  "
            self._manager.selected_collections[item.name] = nil
        else
            self.item_table[item.idx].mandatory = self._manager.checkmark
            self._manager.selected_collections[item.name] = true
        end
        self._manager:updateCollListItemTable()
    else
        self._manager:onShowColl(item.name)
    end
end

function FileManagerCollection:onCollListHold(item)
    if self._manager.selected_collections then -- select mode
        return true
    end

    local button_dialog
    local buttons = {
        {
            {
                text = _("Filter new books"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:showCollFilterDialog(item)
                end
            },
            {
                text = _("Connect folders"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:showCollFolderList(item)
                end
            },
        },
        item.name ~= ReadCollection.default_collection_name and { -- Favorites non-editable
            {
                text = _("Remove collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:removeCollection(item)
                end
            },
            {
                text = _("Rename collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:renameCollection(item)
                end
            },
        } or nil,
    }
    button_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
    return true
end

function FileManagerCollection:showCollFilterDialog(item)
    local coll_name = item.name
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local input_dialog
    input_dialog = InputDialog:new{
        title =  _("Enter file type for new books"),
        input = util.tableGetValue(coll_settings, "filter", "add", "filetype"),
        input_hint = "epub, pdf",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    UIManager:close(input_dialog)
                    local filetype = input_dialog:getInputText()
                    if filetype == "" then
                        util.tableRemoveValue(coll_settings, "filter", "add", "filetype")
                    else
                        util.tableSetValue(coll_settings, filetype:lower(), "filter", "add", "filetype")
                    end
                    self.coll_list.item_table[item.idx].mandatory = self.getCollListItemMandatory(coll_name)
                    self:updateCollListItemTable()
                    self.updated_collections[coll_name] = true
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManagerCollection:showCollFolderList(item)
    local coll_name = item.name
    self.coll_folder_list = Menu:new{
        path = coll_name,
        title = item.text,
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "plus",
        onLeftButtonTap = function() self:showAddCollFolderDialog() end,
        onMenuChoice = self.onCollFolderListChoice,
        onMenuHold = self.onCollFolderListHold,
        ui = self.ui,
        _manager = self,
    }
    self.coll_folder_list.close_callback = function()
        UIManager:close(self.coll_folder_list)
        self.coll_folder_list = nil
        if self.updated_collections[coll_name] then
            -- folder has been connected, new books added to collection
            self.coll_list.item_table[item.idx].mandatory = self.getCollListItemMandatory(item.name)
            self:updateCollListItemTable()
        end
    end
    self:updateCollFolderListItemTable()
    UIManager:show(self.coll_folder_list)
end

function FileManagerCollection:updateCollFolderListItemTable()
    local item_table = {}
    local folders = ReadCollection.coll_settings[self.coll_folder_list.path].folders
    if folders then
        for folder, folder_settings in pairs(folders) do
            table.insert(item_table, {
                text      = folder,
                mandatory = folder_settings.subfolders and "\u{F114}" or nil,
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(a, b) return ffiUtil.strcoll(a.text, b.text) end)
        end
    end
    local subtitle = T(_("Connected folders: %1"), #item_table)
    self.coll_folder_list:switchItemTable(nil, item_table, -1, nil, subtitle)
end

function FileManagerCollection:onCollFolderListChoice(item)
    self._manager.update_files = nil
    self.close_callback()
    self._manager.coll_list.close_callback()
    if self.ui.file_chooser then
        self.ui.file_chooser:changeToPath(item.text)
    else -- called from Reader
        self.ui:onClose()
        self.ui:showFileManager(item.text .. "/")
    end
end

function FileManagerCollection:onCollFolderListHold(item)
    local folder = item.text
    local coll_name = self.path
    local coll_settings = ReadCollection.coll_settings[coll_name]
    local button_dialog
    local buttons = {
        {
            {
                text = _("Disconnect folder"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager.updated_collections[coll_name] = true
                    coll_settings.folders[folder] = nil
                    if next(coll_settings.folders) == nil then
                        coll_settings.folders = nil
                    end
                    self._manager:updateCollFolderListItemTable()
                end
            },
            {
                text = coll_settings.folders[folder].subfolders and _("Exclude subfolders") or _("Include subfolders"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager.updated_collections[coll_name] = true
                    if coll_settings.folders[folder].subfolders then
                        coll_settings.folders[folder].subfolders = false
                    else
                        coll_settings.folders[folder].subfolders = true
                        ReadCollection:updateCollectionFromFolder(coll_name)
                    end
                    self._manager:updateCollFolderListItemTable()
                end
            },
        },
    }
    button_dialog = ButtonDialog:new{
        title = folder,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function FileManagerCollection:showAddCollFolderDialog()
    local PathChooser = require("ui/widget/pathchooser")
    UIManager:show(PathChooser:new{
        path = G_reader_settings:readSetting("home_dir"),
        select_file = false,
        onConfirm = function(folder)
            local coll_name = self.coll_folder_list.path
            local coll_settings = ReadCollection.coll_settings[coll_name]
            coll_settings.folders = coll_settings.folders or {}
            if coll_settings.folders[folder] == nil then
                self.updated_collections[coll_name] = true
                coll_settings.folders[folder] = { subfolders = false }
                ReadCollection:updateCollectionFromFolder(coll_name)
                self:updateCollFolderListItemTable()
            end
        end,
    })
end

function FileManagerCollection:showCollListDialog(caller_callback, no_dialog)
    if no_dialog then
        caller_callback(self.selected_collections)
        self.coll_list.close_callback(true)
        return
    end

    local button_dialog, buttons
    local new_collection_button = {
        {
            text = _("New collection"),
            callback = function()
                UIManager:close(button_dialog)
                self:addCollection()
            end,
        },
    }
    if self.selected_collections then -- select mode
        buttons = {
            new_collection_button,
            {}, -- separator
            {
                {
                    text = _("Deselect all"),
                    callback = function()
                        UIManager:close(button_dialog)
                        for name in pairs(self.selected_collections) do
                            self.selected_collections[name] = nil
                        end
                        self:updateCollListItemTable(true)
                    end,
                },
                {
                    text = _("Select all"),
                    callback = function()
                        UIManager:close(button_dialog)
                        for name in pairs(ReadCollection.coll) do
                            self.selected_collections[name] = true
                        end
                        self:updateCollListItemTable(true)
                    end,
                },
            },
            {
                {
                    text = _("Apply selection"),
                    callback = function()
                        UIManager:close(button_dialog)
                        caller_callback(self.selected_collections)
                        self.coll_list.close_callback(true)
                    end,
                },
            },
        }
    else
        buttons = {
            new_collection_button,
            {
                {
                    text = _("Arrange collections"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:sortCollections()
                    end,
                },
            },
            {},
            {
                {
                    text = _("Collections search"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onShowCollectionsSearchDialog()
                    end,
                },
            },
        }
    end
    button_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function FileManagerCollection:editCollectionName(editCallback, old_name)
    local input_dialog
    input_dialog = InputDialog:new{
        title =  _("Enter collection name"),
        input = old_name,
        input_hint = old_name,
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(input_dialog)
                end,
            },
            {
                text = _("Save"),
                callback = function()
                    local new_name = input_dialog:getInputText()
                    if new_name == "" or new_name == old_name then return end
                    if ReadCollection.coll[new_name] then
                        UIManager:show(InfoMessage:new{
                            text = T(_("Collection already exists: %1"), new_name),
                        })
                    else
                        UIManager:close(input_dialog)
                        editCallback(new_name)
                    end
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManagerCollection:addCollection()
    local editCallback = function(name)
        self.updated_collections[name] = true
        ReadCollection:addCollection(name)
        local mandatory
        if self.selected_collections then
            self.selected_collections[name] = true
            mandatory = self.checkmark
        else
            mandatory = 0
        end
        table.insert(self.coll_list.item_table, {
            text      = name,
            mandatory = mandatory,
            name      = name,
            order     = ReadCollection.coll_settings[name].order,
        })
        self:updateCollListItemTable(false, #self.coll_list.item_table) -- show added item
    end
    self:editCollectionName(editCallback)
end

function FileManagerCollection:renameCollection(item)
    local editCallback = function(name)
        self.updated_collections[name] = true
        ReadCollection:renameCollection(item.name, name)
        self.coll_list.item_table[item.idx].text = name
        self.coll_list.item_table[item.idx].name = name
        self:updateCollListItemTable()
    end
    self:editCollectionName(editCallback, item.name)
end

function FileManagerCollection:removeCollection(item)
    UIManager:show(ConfirmBox:new{
        text = _("Remove collection?") .. "\n\n" .. item.text,
        ok_text = _("Remove"),
        ok_callback = function()
            self.updated_collections[item.name] = true
            ReadCollection:removeCollection(item.name)
            table.remove(self.coll_list.item_table, item.idx)
            self:updateCollListItemTable()
            self.files_updated = self.show_mark
        end,
    })
end

function FileManagerCollection:sortCollections()
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange collections"),
        item_table = self.coll_list.item_table,
        callback = function()
            self.updated_collections = { true } -- all
            ReadCollection:updateCollectionListOrder(sort_widget.item_table)
            self:updateCollListItemTable(true) -- init
        end,
    }
    UIManager:show(sort_widget)
end

function FileManagerCollection:onShowCollectionsSearchDialog(search_str, coll_name)
    local search_dialog, check_button_case, check_button_content
    search_dialog = InputDialog:new{
        title = _("Enter text to search for"),
        input = search_str or self.search_str,
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
                    text = _("Search"),
                    callback = function()
                        local str = search_dialog:getInputText()
                        UIManager:close(search_dialog)
                        if str ~= "" then
                            self.search_str = str
                            self.case_sensitive = check_button_case.checked
                            self.include_content = check_button_content.checked
                            local Trapper = require("ui/trapper")
                            Trapper:wrap(function()
                                self:searchCollections(coll_name)
                            end)
                        end
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
    check_button_content = CheckButton:new{
        text = _("Also search in book content (slow)"),
        checked = self.include_content,
        parent = search_dialog,
    }
    if self.ui.document then
        self.include_content = nil
    else
        search_dialog:addWidget(check_button_content)
    end
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    return true
end

function FileManagerCollection:searchCollections(coll_name)
    local function isFileMatch(file)
        if self.search_str == "*" then
            return true
        end
        if util.stringSearch(file:gsub(".*/", ""), self.search_str, self.case_sensitive) ~= 0 then
            return true
        end
        if not DocumentRegistry:hasProvider(file) then
            return false
        end
        local book_props = self.ui.bookinfo:getDocProps(file, nil, true)
        if next(book_props) ~= nil and self.ui.bookinfo:findInProps(book_props, self.search_str, self.case_sensitive) then
            return true
        end
        if self.include_content then
            logger.dbg("Search in book:", file)
            local ReaderUI = require("apps/reader/readerui")
            local provider = ReaderUI:extendProvider(file, DocumentRegistry:getProvider(file))
            local document = DocumentRegistry:openDocument(file, provider)
            if document then
                local loaded, found
                if document.loadDocument then -- CRE
                    -- We will be half-loading documents and may mess with crengine's state.
                    -- Fortunately, this is run in a subprocess, so we won't be affecting the
                    -- main process's crengine state or any document opened in the main
                    -- process (we furthermore prevent this feature when one is opened).
                    -- To avoid creating half-rendered/invalid cache files, it's best to disable
                    -- crengine saving of such cache files.
                    if not self.is_cre_cache_disabled then
                        local cre = require("document/credocument"):engineInit()
                        cre.initCache("", 0, true, 40)
                        self.is_cre_cache_disabled = true
                    end
                    loaded = document:loadDocument()
                else
                    loaded = true
                end
                if loaded then
                    found = document:findText(self.search_str, 0, 0, not self.case_sensitive, 1, false, 1)
                end
                document:close()
                if found then
                    return true
                end
            end
        end
        return false
    end

    local collections = coll_name and { [coll_name] = ReadCollection.coll[coll_name] } or ReadCollection.coll
    local Trapper = require("ui/trapper")
    local info = InfoMessage:new{ text = _("Searching… (tap to cancel)") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local completed, files_found, files_found_order = Trapper:dismissableRunInSubprocess(function()
        local match_cache, _files_found, _files_found_order = {}, {}, {}
        for collection_name, coll in pairs(collections) do
            local coll_order = ReadCollection.coll_settings[collection_name].order
            for _, item in pairs(coll) do
                local file = item.file
                if match_cache[file] == nil then -- a book can be included to several collections
                    match_cache[file] = isFileMatch(file)
                end
                if match_cache[file] then
                    local order_idx = _files_found[file]
                    if order_idx == nil then -- new
                        table.insert(_files_found_order, {
                            file = file,
                            coll_order = coll_order,
                            item_order = item.order,
                        })
                        _files_found[file] = #_files_found_order -- order_idx
                    else -- previously found, update orders
                        if _files_found_order[order_idx].coll_order > coll_order then
                            _files_found_order[order_idx].coll_order = coll_order
                            _files_found_order[order_idx].item_order = item.order
                        end
                    end
                end
            end
        end
        return _files_found, _files_found_order
    end, info)
    if not completed then return end
    UIManager:close(info)

    if #files_found_order == 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("No results for: %1"), self.search_str),
        })
    else
        table.sort(files_found_order, function(a, b)
            if a.coll_order ~= b.coll_order then
                return a.coll_order < b.coll_order
            end
            if a.item_order and b.item_order then
                return a.item_order < b.item_order
            end
            return ffiUtil.strcoll(a.text, b.text)
        end)
        local new_coll_name = T(_("Search results: %1"), self.search_str)
        if coll_name then
            new_coll_name = new_coll_name .. " " .. T(_"(in %1)", coll_name)
            self.booklist_menu.close_callback()
        end
        self.updated_collections[new_coll_name] = true
        ReadCollection:removeCollection(new_coll_name)
        ReadCollection:addCollection(new_coll_name)
        ReadCollection:addItemsMultiple(files_found, { [new_coll_name] = true })
        ReadCollection:updateCollectionOrder(new_coll_name, files_found_order)
        if self.coll_list ~= nil then
            UIManager:close(self.coll_list)
            self.coll_list = nil
        end
        self:onShowColl(new_coll_name)
    end
end

function FileManagerCollection:onCloseWidget()
    if next(self.updated_collections) then
        ReadCollection:write(self.updated_collections)
    end
end

-- external

function FileManagerCollection:genAddToCollectionButton(file_or_files, caller_pre_callback, caller_post_callback, button_disabled)
    local is_single_file = type(file_or_files) == "string"
    return {
        text = _("Collections…"),
        enabled = not button_disabled,
        callback = function()
            if caller_pre_callback then
                caller_pre_callback()
            end
            local caller_callback = function(selected_collections)
                for name in pairs(selected_collections) do
                    self.updated_collections[name] = true
                end
                if is_single_file then
                    ReadCollection:addRemoveItemMultiple(file_or_files, selected_collections)
                else -- selected files
                    ReadCollection:addItemsMultiple(file_or_files, selected_collections)
                end
                if caller_post_callback then
                    caller_post_callback()
                end
            end
            -- if selected files, do not checkmark any collection on start
            self:onShowCollList(is_single_file and file_or_files or {}, caller_callback)
        end,
    }
end

return FileManagerCollection
