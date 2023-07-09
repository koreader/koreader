local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = require("device").screen
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local _ = require("gettext")

local FileManagerCollection = WidgetContainer:extend{
    coll_menu_title = _("Favorites"),
}

function FileManagerCollection:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerCollection:addToMainMenu(menu_items)
    menu_items.collections = {
        text = self.coll_menu_title,
        callback = function()
            self:onShowColl("favorites")
        end,
    }
end

function FileManagerCollection:updateItemTable()
    -- Try to stay on current page.
    local select_number = nil
    if self.coll_menu.page and self.coll_menu.perpage then
        select_number = (self.coll_menu.page - 1) * self.coll_menu.perpage + 1
    end
    self.coll_menu:switchItemTable(self.coll_menu_title,
        ReadCollection:prepareList(self.coll_menu.collection), select_number)
end

function FileManagerCollection:onMenuChoice(item)
    require("apps/reader/readerui"):showReader(item.file)
end

function FileManagerCollection:onMenuHold(item)
    self.collfile_dialog = nil
    local function close_dialog_callback()
        UIManager:close(self.collfile_dialog)
    end
    local function close_dialog_menu_callback()
        UIManager:close(self.collfile_dialog)
        self._manager.coll_menu.close_callback()
    end
    local function status_button_callback()
        UIManager:close(self.collfile_dialog)
        self._manager:updateItemTable()
    end
    local is_currently_opened = item.file == (self.ui.document and self.ui.document.file)

    local buttons = {}
    if not (item.dim or is_currently_opened) then
        table.insert(buttons, filemanagerutil.genStatusButtonsRow(item.file, status_button_callback))
        table.insert(buttons, {}) -- separator
    end
    table.insert(buttons, {
        filemanagerutil.genResetSettingsButton(item.file, status_button_callback, is_currently_opened),
        {
            text = _("Remove from favorites"),
            callback = function()
                UIManager:close(self.collfile_dialog)
                ReadCollection:removeItem(item.file, self._manager.coll_menu.collection)
                self._manager:updateItemTable()
            end,
        },
    })
    table.insert(buttons, {
        filemanagerutil.genShowFolderButton(item.file, close_dialog_menu_callback, item.dim),
        filemanagerutil.genBookInformationButton(item.file, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(item.file, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(item.file, close_dialog_callback, item.dim),
    })

    if Device:canExecuteScript(item.file) then
        table.insert(buttons, {
            filemanagerutil.genExecuteScriptButton(item.file, close_dialog_menu_callback)
        })
    end

    self.collfile_dialog = ButtonDialog:new{
        title = item.text:match("([^/]+)$"),
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

function FileManagerCollection:onShowColl(collection)
    self.coll_menu = Menu:new{
        ui = self.ui,
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() self:showCollDialog() end,
        onMenuChoice = self.onMenuChoice,
        onMenuHold = self.onMenuHold,
        onSetRotationMode = self.MenuSetRotationModeHandler,
        _manager = self,
        collection = collection,
    }
    self:updateItemTable()
    self.coll_menu.close_callback = function()
        UIManager:close(self.coll_menu)
    end
    UIManager:show(self.coll_menu)
    return true
end

function FileManagerCollection:showCollDialog()
    local coll_dialog
    local is_added = self.ui.document and ReadCollection:checkItemExist(self.ui.document.file)
    local buttons = {
        {{
            text_func = function()
                return is_added and _("Remove current book from favorites") or _("Add current book to favorites")
            end,
            enabled = self.ui.document and true or false,
            callback = function()
                UIManager:close(coll_dialog)
                if is_added then
                    ReadCollection:removeItem(self.ui.document.file)
                else
                    ReadCollection:addItem(self.ui.document.file)
                end
                self:updateItemTable()
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
                        return DocumentRegistry:getProviders(file) ~= nil
                    end,
                    onConfirm = function(file)
                        if not ReadCollection:checkItemExist(file) then
                            ReadCollection:addItem(file)
                            self:updateItemTable()
                        end
                    end,
                }
                UIManager:show(path_chooser)
            end,
        }},
        {{
            text = _("Sort favorites"),
            callback = function()
                UIManager:close(coll_dialog)
                self:sortCollection()
            end,
        }},
    }
    coll_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(coll_dialog)
end

function FileManagerCollection:sortCollection()
    local item_table = {}
    for _, v in ipairs(self.coll_menu.item_table) do
        table.insert(item_table, { text = v.text, label = v.file })
    end
    local SortWidget = require("ui/widget/sortwidget")
    local sort_widget
    sort_widget = SortWidget:new{
        title = _("Sort favorites"),
        item_table = item_table,
        callback = function()
            local new_order_table = {}
            for i, v in ipairs(sort_widget.item_table) do
                table.insert(new_order_table, { file = v.label, order = i })
            end
            ReadCollection:writeCollection(new_order_table, self.coll_menu.collection)
            self:updateItemTable()
        end
    }
    UIManager:show(sort_widget)
end

return FileManagerCollection
