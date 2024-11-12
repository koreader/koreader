local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local SortWidget = require("ui/widget/sortwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local _ = require("gettext")
local T = require("ffi/util").template
local util = require("util")

local FileManagerCollection = WidgetContainer:extend{
    title = _("Collections"),
    default_collection_title = _("Favorites"),
    checkmark = "\u{2713}",
}

function FileManagerCollection:init()
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
    self.coll_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        -- item and book cover thumbnail dimensions in Mosaic and Detailed list display modes
        -- must be equal in File manager, History and Collection windows to avoid image scaling
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showCollDialog() end,
        onReturn = function()
            self.coll_menu.close_callback()
            self:onShowCollList()
        end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        _manager = self,
        _recreate_func = function() self:onShowColl(collection_name) end,
        collection_name = collection_name,
    }
    table.insert(self.coll_menu.paths, true) -- enable onReturn button
    self.coll_menu.close_callback = function()
        self:refreshFileManager()
        UIManager:close(self.coll_menu)
        self.coll_menu = nil
    end
    self:updateItemTable()
    UIManager:show(self.coll_menu)
    return true
end

function FileManagerCollection:updateItemTable(show_last_item)
    local item_table = {}
    for _, item in pairs(ReadCollection.coll[self.coll_menu.collection_name]) do
        table.insert(item_table, item)
    end
    if #item_table > 1 then
        table.sort(item_table, function(v1, v2) return v1.order < v2.order end)
    end
    local title = self:getCollectionTitle(self.coll_menu.collection_name)
    title = T("%1 (%2)", title, #item_table)
    local item_number = show_last_item and #item_table or -1
    self.coll_menu:switchItemTable(title, item_table, item_number)
end

function FileManagerCollection:onSetDimensions(dimen)
    self.dimen = dimen
end

function FileManagerCollection:onMenuChoice(item)
    if self.ui.document then
        if self.ui.document.file ~= item.file then
            self.ui:switchDocument(item.file)
        end
    else
        self.ui:openFile(item.file)
    end
end

function FileManagerCollection:onMenuHold(item)
    local file = item.file
    self.collfile_dialog = nil
    self.book_props = self.ui.coverbrowser and self.ui.coverbrowser:getBookInfo(file)

    local function close_dialog_callback()
        UIManager:close(self.collfile_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.collfile_dialog)
        self._manager.coll_menu.close_callback()
    end
    local function close_dialog_update_callback()
        UIManager:close(self.collfile_dialog)
        self._manager:updateItemTable()
        self._manager.files_updated = true
    end
    local is_currently_opened = file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    local doc_settings_or_file
    if is_currently_opened then
        doc_settings_or_file = self.ui.doc_settings
        if not self.book_props then
            self.book_props = self.ui.doc_props
            self.book_props.has_cover = true
        end
    else
        if DocSettings:hasSidecarFile(file) then
            doc_settings_or_file = DocSettings:open(file)
            if not self.book_props then
                local props = doc_settings_or_file:readSetting("doc_props")
                self.book_props = self.ui.bookinfo.extendProps(props, file)
                self.book_props.has_cover = true
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
                ReadCollection:removeItem(file, self.collection_name)
                close_dialog_update_callback()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        filemanagerutil.genBookInformationButton(doc_settings_or_file, self.book_props, close_dialog_callback),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(file, self.book_props, close_dialog_callback),
        filemanagerutil.genBookDescriptionButton(file, self.book_props, close_dialog_callback),
    })

    if Device:canExecuteScript(file) then
        table.insert(buttons, {
            filemanagerutil.genExecuteScriptButton(file, close_dialog_menu_callback)
        })
    end

    self.collfile_dialog = ButtonDialog:new{
        title = BD.filename(item.text),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.collfile_dialog)
    return true
end

function FileManagerCollection:showCollDialog()
    local coll_dialog
    local buttons = {
        {{
            text = _("Collections"),
            callback = function()
                UIManager:close(coll_dialog)
                self.coll_menu.close_callback()
                self:onShowCollList()
            end,
        }},
        {}, -- separator
        {{
            text = _("Arrange books in collection"),
            callback = function()
                UIManager:close(coll_dialog)
                self:sortCollection()
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
                        if not ReadCollection:isFileInCollection(file, self.coll_menu.collection_name) then
                            ReadCollection:addItem(file, self.coll_menu.collection_name)
                            self:updateItemTable(true) -- show added item
                            self.files_updated = true
                        end
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }},
    }
    if self.ui.document then
        local file = self.ui.document.file
        local is_in_collection = ReadCollection:isFileInCollection(file, self.coll_menu.collection_name)
        table.insert(buttons, {{
            text_func = function()
                return is_in_collection and _("Remove current book from collection") or _("Add current book to collection")
            end,
            callback = function()
                UIManager:close(coll_dialog)
                if is_in_collection then
                    ReadCollection:removeItem(file, self.coll_menu.collection_name)
                else
                    ReadCollection:addItem(file, self.coll_menu.collection_name)
                end
                self:updateItemTable(not is_in_collection)
                self.files_updated = true
            end,
        }})
    end
    coll_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(coll_dialog)
end

function FileManagerCollection:sortCollection()
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange books in collection"),
        item_table = ReadCollection:getOrderedCollection(self.coll_menu.collection_name),
        callback = function()
            ReadCollection:updateCollectionOrder(self.coll_menu.collection_name, sort_widget.item_table)
            self:updateItemTable()
        end
    }
    UIManager:show(sort_widget)
end

function FileManagerCollection:onBookMetadataChanged()
    if self.coll_menu then
        self.coll_menu:updateItems()
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
        for name, coll in pairs(ReadCollection.coll) do
            local mandatory
            if self.selected_collections then
                mandatory = self.selected_collections[name] and self.checkmark or "  "
                self.coll_list.items_mandatory_font_size = self.coll_list.font_size
            else
                mandatory = util.tableSize(coll)
            end
            table.insert(item_table, {
                text      = self:getCollectionTitle(name),
                mandatory = mandatory,
                name      = name,
                order     = ReadCollection.coll_order[name],
            })
        end
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2) return v1.order < v2.order end)
        end
    else
        item_table = self.coll_list.item_table
    end
    local title = T(_("Collections (%1)"), #item_table)
    local subtitle
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
    end
    self.coll_list:switchItemTable(title, item_table, item_number or -1, nil, subtitle)
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
    if item.name == ReadCollection.default_collection_name -- Favorites non-editable
            or self._manager.selected_collections then -- select mode
        return
    end

    local button_dialog
    local buttons = {
        {
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
        },
    }
    button_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
    return true
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
            order     = ReadCollection.coll_order[name],
        })
        self:updateCollListItemTable(false, #self.coll_list.item_table) -- show added item
    end
    self:editCollectionName(editCallback)
end

function FileManagerCollection:renameCollection(item)
    local editCallback = function(name)
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
            ReadCollection:removeCollection(item.name)
            table.remove(self.coll_list.item_table, item.idx)
            self:updateCollListItemTable()
            self.files_updated = true
        end,
    })
end

function FileManagerCollection:sortCollections()
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Arrange collections"),
        item_table = util.tableDeepCopy(self.coll_list.item_table),
        callback = function()
            ReadCollection:updateCollectionListOrder(sort_widget.item_table)
            self:updateCollListItemTable(true) -- init
        end,
    }
    UIManager:show(sort_widget)
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
