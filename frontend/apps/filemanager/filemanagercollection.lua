local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
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
        {
            text = _("Sort favorites"),
            callback = function()
                UIManager:close(self.collfile_dialog)
                local item_table = {}
                for _, v in ipairs(self._manager.coll_menu.item_table) do
                    table.insert(item_table, {text = v.text, label = v.file})
                end
                local SortWidget = require("ui/widget/sortwidget")
                local sort_item
                sort_item = SortWidget:new{
                    title = _("Sort favorites"),
                    item_table = item_table,
                    callback = function()
                        local new_order_table = {}
                        for i, v in ipairs(sort_item.item_table) do
                            table.insert(new_order_table, {
                                file = v.label,
                                order = i,
                            })
                        end
                        ReadCollection:writeCollection(new_order_table, self._manager.coll_menu.collection)
                        self._manager:updateItemTable()
                    end
                }
                UIManager:show(sort_item)
            end,
        },
        filemanagerutil.genBookInformationButton(item.file, close_dialog_callback, item.dim),
    })
    table.insert(buttons, {
        filemanagerutil.genBookCoverButton(item.file, close_dialog_callback, item.dim),
        filemanagerutil.genBookDescriptionButton(item.file, close_dialog_callback, item.dim),
    })

    if Device:canExecuteScript(item.file) then
        local function button_callback()
            UIManager:close(self.collfile_dialog)
            self.coll_menu.close_callback()
        end
        table.insert(buttons, {
            filemanagerutil.genExecuteScriptButton(item.file, button_callback)
        })
    end

    self.collfile_dialog = ButtonDialogTitle:new{
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

return FileManagerCollection
