local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local _ = require("gettext")

local FileManagerCollection = WidgetContainer:extend{
    title = _("Favorites"),
}

function FileManagerCollection:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerCollection:addToMainMenu(menu_items)
    menu_items.collections = {
        text = self.title,
        callback = function()
            self:onShowColl()
        end,
    }
end

function FileManagerCollection:updateItemTable()
    local item_table = {}
    for _, item in pairs(ReadCollection.coll[self.coll_menu.collection_name]) do
        table.insert(item_table, item)
    end
    table.sort(item_table, function(v1, v2) return v1.order < v2.order end)
    self.coll_menu:switchItemTable(self.title, item_table, -1)
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
                self.book_props = FileManagerBookInfo.extendProps(props, file)
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
        {
            text = _("Remove from favorites"),
            callback = function()
                UIManager:close(self.collfile_dialog)
                ReadCollection:removeItem(file, self.collection_name)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(file, close_dialog_menu_callback),
        filemanagerutil.genBookInformationButton(file, self.book_props, close_dialog_callback),
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

function FileManagerCollection:MenuSetRotationModeHandler(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        UIManager:close(self._manager.coll_menu)
        if self._manager.ui.view and self._manager.ui.view.onSetRotationMode then
            self._manager.ui.view:onSetRotationMode(rotation)
        elseif self._manager.ui.onSetRotationMode then
            self._manager.ui:onSetRotationMode(rotation)
        else
            Screen:setRotationMode(rotation)
        end
        self._manager:onShowColl()
    end
    return true
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
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        onSetRotationMode = self.MenuSetRotationModeHandler,
        _manager = self,
        collection_name = collection_name,
    }
    self.coll_menu.close_callback = function()
        if self.files_updated then
            if self.ui.file_chooser then
                self.ui.file_chooser:refreshPath()
            end
            self.files_updated = nil
        end
        UIManager:close(self.coll_menu)
        self.coll_menu = nil
    end
    self:updateItemTable()
    UIManager:show(self.coll_menu)
    return true
end

function FileManagerCollection:showCollDialog()
    local coll_dialog
    local buttons = {
        {{
            text = _("Sort favorites"),
            callback = function()
                UIManager:close(coll_dialog)
                self:sortCollection()
            end,
        }},
        {{
            text = _("Add a book to favorites"),
            callback = function()
                UIManager:close(coll_dialog)
                local PathChooser = require("ui/widget/pathchooser")
                local path_chooser = PathChooser:new{
                    path = G_reader_settings:readSetting("home_dir"),
                    select_directory = false,
                    file_filter = function(file)
                        return DocumentRegistry:hasProvider(file)
                    end,
                    onConfirm = function(file)
                        if not ReadCollection:hasFile(file) then
                            ReadCollection:addItem(file, self.coll_menu.collection_name)
                            self:updateItemTable()
                        end
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }},
    }
    if self.ui.document then
        local has_file = ReadCollection:hasFile(self.ui.document.file)
        table.insert(buttons, {{
            text_func = function()
                return has_file and _("Remove current book from favorites") or _("Add current book to favorites")
            end,
            callback = function()
                UIManager:close(coll_dialog)
                if has_file then
                    ReadCollection:removeItem(self.ui.document.file)
                else
                    ReadCollection:addItem(self.ui.document.file, self.coll_menu.collection_name)
                end
                self:updateItemTable()
            end,
        }})
    end
    coll_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(coll_dialog)
end

function FileManagerCollection:sortCollection()
    local item_table = ReadCollection:getOrderedCollection(self.coll_menu.collection_name)
    local SortWidget = require("ui/widget/sortwidget")
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Sort favorites"),
        item_table = item_table,
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

return FileManagerCollection
