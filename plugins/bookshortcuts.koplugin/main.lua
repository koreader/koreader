local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local BookShortcuts = WidgetContainer:new{
    name = "bookshortcuts",
    shortcuts = LuaSettings:open(DataStorage:getSettingsDir() .. "/bookshortcuts.lua"),
    updated = false,
}

function BookShortcuts:onDispatcherRegisterActions()
    for k,v in pairs(self.shortcuts.data) do
        if util.pathExists(k) then
            local title = k
            if lfs.attributes(k, "mode") == "file" then
                local directory, filename = util.splitFilePathName(k) -- luacheck: no unused
                title = filename
            end
            Dispatcher:registerAction(k, {category="none", event="BookShortcut", title=title, general=true, arg=k,})
        end
    end
end

function BookShortcuts:onBookShortcut(path)
    if util.pathExists(path) then
        local file
        if lfs.attributes(path, "mode") ~= "file" then
            if G_reader_settings:readSetting("BookShortcuts_directory_action") == "FM" then
                local FileManager = require("apps/filemanager/filemanager")
                FileManager:showFiles(path)
            else
                file = ReadHistory:getFileByDirectory(path)
            end
        else
            file = path
        end
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
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
    local FM_text = _("file browser")
    local last_text = _("last book")

    local sub_item_table = {
        {
            text = _("New shortcut"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local path_chooser = PathChooser:new{
                    select_file = true,
                    select_directory = true,
                    detailed_file_info = true,
                    path = G_reader_settings:readSetting("home_dir"),
                    onConfirm = function(path)
                        self:addShortcut(path)
                        touchmenu_instance.item_table = self:getSubMenuItems()
                        touchmenu_instance.page = 1
                        touchmenu_instance:updateItems()
                    end
                }
                UIManager:show(path_chooser)
            end,
        },
        {
            text_func = function() return T(_("Directory action: %1"), G_reader_settings:readSetting("BookShortcuts_directory_action", "FM") == "FM" and FM_text or last_text) end,
            keep_menu_open = true,
            sub_item_table = {
                {
                    text = last_text,
                    checked_func = function() return G_reader_settings:readSetting("BookShortcuts_directory_action") == "Last" end,
                    callback = function() G_reader_settings:saveSetting("BookShortcuts_directory_action", "Last") end,
                },
                {
                    text = FM_text,
                    checked_func = function() return G_reader_settings:readSetting("BookShortcuts_directory_action") == "FM" end,
                    callback = function() G_reader_settings:saveSetting("BookShortcuts_directory_action", "FM") end,
                },
            },
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
