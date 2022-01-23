local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local Device = require("device")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local BaseUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = BaseUtil.template

local FileManagerCollection = InputContainer:extend{
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

function FileManagerCollection:onMenuHold(item)
    self.collfile_dialog = nil
    local buttons = {
        {
            {
                text = _("Sort"),
                callback = function()
                    UIManager:close(self.collfile_dialog)
                    local item_table = {}
                    for i=1, #self._manager.coll_menu.item_table do
                        table.insert(item_table, {text = self._manager.coll_menu.item_table[i].text, label = self._manager.coll_menu.item_table[i].file})
                    end
                    local SortWidget = require("ui/widget/sortwidget")
                    local sort_item
                    sort_item = SortWidget:new{
                        title = _("Sort favorites"),
                        item_table = item_table,
                        callback = function()
                            local new_order_table = {}
                            for i=1, #sort_item.item_table do
                                table.insert(new_order_table, {
                                    file = sort_item.item_table[i].label,
                                    order = i
                                })
                            end
                            ReadCollection:writeCollection(new_order_table, self._manager.coll_menu.collection)
                            self._manager:updateItemTable()
                        end
                    }
                    UIManager:show(sort_item)

                end,
            },
            {
                text = _("Remove from collection"),
                callback = function()
                    ReadCollection:removeItem(item.file, self._manager.coll_menu.collection)
                    self._manager:updateItemTable()
                    UIManager:close(self.collfile_dialog)
                end,
            },
        },
        {
            {
                text = _("Book information"),
                enabled = FileManagerBookInfo:isSupported(item.file),
                callback = function()
                    FileManagerBookInfo:show(item.file)
                    UIManager:close(self.collfile_dialog)
                end,
            },
        },
    }
    -- NOTE: Duplicated from frontend/apps/filemanager/filemanager.lua
    if Device:canExecuteScript(item.file) then
        table.insert(buttons, {
            {
                -- @translators This is the script's programming language (e.g., shell or python)
                text = T(_("Execute %1 script"), util.getScriptType(item.file)),
                enabled = true,
                callback = function()
                    UIManager:close(self.collfile_dialog)
                    local script_is_running_msg = InfoMessage:new{
                            -- @translators %1 is the script's programming language (e.g., shell or python), %2 is the filename
                            text = T(_("Running %1 script %2…"), util.getScriptType(item.file), BD.filename(BaseUtil.basename(item.file))),
                    }
                    UIManager:show(script_is_running_msg)
                    UIManager:scheduleIn(0.5, function()
                        local rv = os.execute(BaseUtil.realpath(item.file))
                        UIManager:close(script_is_running_msg)
                        if rv == 0 then
                            UIManager:show(InfoMessage:new{
                                text = _("The script exited successfully."),
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = T(_("The script returned a non-zero status code: %1!"), bit.rshift(rv, 8)),
                                icon = "notice-warning",
                            })
                        end
                    end)
                end,
            }
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
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        is_borderless = true,
        is_popout = false,
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
