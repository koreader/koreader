local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local LuaSettings = require("luasettings")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

local BookShortcuts = WidgetContainer:extend{
    name = "bookshortcuts",
    settings_file = DataStorage:getSettingsDir() .. "/bookshortcuts.lua",
    bs_settings = nil,
    updated = false,
}

local function dispatcherRegisterShortcut(name)
    local mode = lfs.attributes(name, "mode")
    if mode then
        local title = T(C_("File", "Open %1"), mode == "file" and name:gsub(".*/", "") or name)
        Dispatcher:registerAction(BookShortcuts.name .. name,
            {category="none", event="BookShortcut", title=title, general=true, arg=name,})
    end
end

function BookShortcuts:onDispatcherRegisterActions()
    for name in pairs(self.shortcuts) do
        if name ~= "settings" then
            dispatcherRegisterShortcut(name)
        end
    end
end

function BookShortcuts:onBookShortcut(path)
    local mode = lfs.attributes(path, "mode")
    if mode then
        local file
        if mode ~= "file" then
            if self.settings.directory_action == "FM" then
                if self.ui.file_chooser then
                    self.ui.file_chooser:changeToPath(path)
                else -- called from Reader
                    self.ui:onClose()
                    self.ui:showFileManager(path)
                end
            else
                local real_path = ffiUtil.realpath(path)
                for _, v in ipairs(require("readhistory").hist) do
                    local ipath = ffiUtil.realpath(ffiUtil.dirname(v.file))
                    if ipath and (ipath == real_path
                            or (self.settings.recursive_directory and util.stringStartsWith(ipath, real_path))) then
                        file = v.file
                        break
                    end
                end
            end
        else
            file = path
        end
        if file then
            if Device:canExecuteScript(file) then
                local filemanagerutil = require("apps/filemanager/filemanagerutil")
                filemanagerutil.executeScript(file)
            else
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.openFile(self.ui, file)
            end
        end
    end
end

function BookShortcuts:init()
    self:loadSettings()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function BookShortcuts:loadSettings()
    if not BookShortcuts.bs_settings then
        BookShortcuts.bs_settings = LuaSettings:open(self.settings_file)
        if not next(BookShortcuts.bs_settings.data) then
            self.updated = true
        end
    end
    self.shortcuts = BookShortcuts.bs_settings.data
    self.settings = BookShortcuts.bs_settings:readSetting("settings", { directory_action = "FM" })
end

function BookShortcuts:onFlushSettings()
    if self.updated then
        BookShortcuts.bs_settings:flush()
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
            text_func = function()
                return T(_("Folder action: %1"), self.settings.directory_action == "FM" and FM_text or last_text)
            end,
            keep_menu_open = true,
            sub_item_table = {
                {
                    text = FM_text,
                    radio = true,
                    checked_func = function()
                        return self.settings.directory_action == "FM"
                    end,
                    callback = function()
                        self.settings.directory_action = "FM"
                        self.updated = true
                    end,
                },
                {
                    text = last_text,
                    radio = true,
                    checked_func = function()
                        return self.settings.directory_action == "Last"
                    end,
                    callback = function()
                        self.settings.directory_action = "Last"
                        self.updated = true
                    end,
                },
                {
                    text = _("Recursively search folders"),
                    enabled_func = function()
                        return self.settings.directory_action == "Last"
                    end,
                    checked_func = function()
                        return self.settings.directory_action == "Last" and self.settings.recursive_directory
                    end,
                    callback = function()
                        self.settings.recursive_directory = not self.settings.recursive_directory or nil
                        self.updated = true
                    end,
                },
            },
            separator = true,
        },
    }
    for k in ffiUtil.orderedPairs(self.shortcuts) do
        if k == "settings" then goto continue end
        local mode = lfs.attributes(k, "mode")
        local icon = mode and (mode == "file" and "\u{F016} " or "\u{F114} ") or "\u{F48E} "
        local text = mode == "file" and k:gsub(".*/", "") or k
        table.insert(sub_item_table, {
            text = icon .. text,
            callback = function() self:onBookShortcut(k) end,
            hold_callback = function(touchmenu_instance, item)
                UIManager:show(ConfirmBox:new{
                    text = _("Do you want to delete this shortcut?") .. "\n\n" .. k .. "\n",
                    ok_text = _("Delete"),
                    ok_callback = function()
                        self:deleteShortcut(k)
                        table.remove(touchmenu_instance.item_table, item.idx)
                        touchmenu_instance.page = 1
                        touchmenu_instance:updateItems()
                    end,
                })
            end,
        })
        ::continue::
    end
    return sub_item_table
end

function BookShortcuts:addShortcut(name)
    self.shortcuts[name] = true
    dispatcherRegisterShortcut(name)
    self.updated = true
end

function BookShortcuts:deleteShortcut(name)
    self.shortcuts[name] = nil
    Dispatcher:removeAction(name)
    UIManager:broadcastEvent(Event:new("DispatcherActionNameChanged", { old_name = name, new_name = nil }))
    self.updated = true
end

return BookShortcuts
