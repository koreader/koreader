local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local _ = require("gettext")

local FileManagerCollection = InputContainer:extend{
    coll_menu_title = _("Favorites"),
}

function FileManagerCollection:init()
    self.ui.menu:registerToMainMenu(self)
end

function FileManagerCollection:addToMainMenu(menu_items)
    -- insert table to main tab of filemanager menu
    menu_items.collections = {
        text = self.coll_menu_title,
        callback = function()
            self:onShowColl("favorites")
        end,
    }
end

function FileManagerCollection:updateItemTable()
    -- try to stay on current page
    local select_number = nil
    if self.coll_menu.page and self.coll_menu.perpage then
        select_number = (self.coll_menu.page - 1) * self.coll_menu.perpage + 1
    end
    self.coll_menu:switchItemTable(self.coll_menu_title,
        require("readcollection"):prepareList(self.coll_menu.collection), select_number)
end

function FileManagerCollection:onMenuHold(item)
    local collfile_dialog = nil
    local buttons = {
        {
            {
                text = _("Sort"),
                callback = function()
                    UIManager:close(collfile_dialog)
                    local item_table = {}
                    for i=1, #self._manager.coll_menu.item_table do
                        table.insert(item_table, {text = self._manager.coll_menu.item_table[i].text, label = self._manager.coll_menu.item_table[i].file})
                    end
                    local SortWidget = require("ui/widget/sortwidget")
                    local sort_item
                    sort_item = SortWidget:new{
                        title = _("Sort favorites book"),
                        item_table = item_table,
                        callback = function()
                            local new_order_table = {}
                            for i=1, #sort_item.item_table do
                                table.insert(new_order_table, {
                                    file = sort_item.item_table[i].label,
                                    order = i
                                })
                            end
                            require("readcollection"):writeCollection(new_order_table, self._manager.coll_menu.collection)
                            self._manager:updateItemTable()
                        end
                    }
                    UIManager:show(sort_item)

                end,
            },
            {
                text = _("Remove from collection"),
                callback = function()
                    require("readcollection"):removeItem(item.file, self._manager.coll_menu.collection)
                    self._manager:updateItemTable()
                    UIManager:close(collfile_dialog)
                end,
            },
        },
        {
            {
                text = _("Book information"),
                enabled = FileManagerBookInfo:isSupported(item.file),
                callback = function()
                    FileManagerBookInfo:show(item.file)
                    UIManager:close(collfile_dialog)
                end,
            },
        },
    }
    collfile_dialog = ButtonDialogTitle:new{
        title = item.text:match("([^/]+)$"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(collfile_dialog)
    return true
end

function FileManagerCollection:onShowColl(collection)
    self.coll_menu = Menu:new{
        ui = self.ui,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
        onMenuHold = self.onMenuHold,
        _manager = self,
        collection = collection,
    }
    self:updateItemTable()
    self.coll_menu.close_callback = function()
        -- Close it at next tick so it stays displayed
        -- while a book is opening (avoids a transient
        -- display of the underlying File Browser)
        UIManager:nextTick(function()
            UIManager:close(self.coll_menu)
        end)
    end
    UIManager:show(self.coll_menu)
    return true
end

return FileManagerCollection
