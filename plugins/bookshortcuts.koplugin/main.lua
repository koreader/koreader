local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")

local BookShortcuts = WidgetContainer:new{
    name = "bookshortcuts",
    shortcuts = LuaSettings:open(DataStorage:getSettingsDir() .. "/bookshortcuts.lua"),
    updated = false,
}

function BookShortcuts:onDispatcherRegisterActions()
    for k,v in pairs(self.shortcuts.data) do
        if util.fileExists(k) then
            local directory, filename = util.splitFilePathName(k) -- luacheck: no unused
            Dispatcher:registerAction(k, {category="none", event="BookShortcut", title=filename, general=true, arg=k,})
        end
    end
end

function BookShortcuts:onBookShortcut(path)
    if util.fileExists(path) then
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(path)
    end
end

function BookShortcuts:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function BookShortcuts:onFlushSettings()
    if self.shortcuts and self.updated then
        self.shortcuts:flush()
        self.updated = false
    end
end

function BookShortcuts:addToMainMenu(menu_items)
    menu_items.book_shortcuts = {
        text = _("Book shortcuts"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function BookShortcuts:getSubMenuItems()
    local sub_item_table = {
        {
            text = _("New shortcut"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local path_chooser = PathChooser:new{
                    select_file = true,
                    select_directory = false,
                    detailed_file_info = true,
                    path = G_reader_settings:readSetting("home_dir"),
                    onConfirm = function(file_path)
                        self:addShortcut(file_path)
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance.page = 1
                        touchmenu_instance:updateItems()
                    end
                }
                UIManager:show(path_chooser)
            end,
            separator = true,
        }
    }
    for k,v in FFIUtil.orderedPairs(self.shortcuts.data) do
        table.insert(sub_item_table, {
            text = k,
            callback = function() self:onBookShortcut(k) end,
            hold_callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = _("Do you want to delete this shortcut?"),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        self:deleteShortcut(k)
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance.page = 1
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        })
    end
    return sub_item_table
end

function BookShortcuts:addShortcut(name)
    self.shortcuts.data[name] = true
    self.updated = true
    self:onDispatcherRegisterActions()
end

function BookShortcuts:deleteShortcut(name)
    self.shortcuts.data[name] = nil
    Dispatcher:removeAction(name)
    self.updated = true
end

return BookShortcuts
