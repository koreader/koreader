local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local FileManager = require("apps/filemanager/filemanager")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local MoveToArchive = WidgetContainer:extend{
    name = "movetoarchive",
    title = _("Move current book to archive"),
    settings_file = DataStorage:getSettingsDir() .. "/move_to_archive_settings.lua",
    settings = nil,
    data = nil, -- direct access to the settings table
    updated = nil,
}

function MoveToArchive:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function MoveToArchive:loadSettings()
    if self.settings then return end
    self.settings = LuaSettings:open(self.settings_file)
    self.data = self.settings.data
end

function MoveToArchive:onDispatcherRegisterActions()
    Dispatcher:registerAction(self.name, {category="none", event="MoveToArchive", title=self.title, reader=true})
end

function MoveToArchive:addToMainMenu(menu_items)
    menu_items.move_to_archive = {
        text = _("Move to archive"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function MoveToArchive:getSubMenuItems()
    self:loadSettings()
    return {
        {
            text = self.title,
            enabled_func = function()
                return self.data.archive_dir_path ~= nil and self:isActionEnabled()
            end,
            callback = function()
                self:onMoveToArchive()
            end,
        },
        {
            text = _("Copy current book to archive"),
            enabled_func = function()
                return self.data.archive_dir_path ~= nil and self:isActionEnabled()
            end,
            callback = function()
                self:onMoveToArchive(true)
            end,
            separator = true,
        },
        {
            text = _("Go to archive folder"),
            enabled_func = function()
                return self.data.archive_dir_path ~= nil
            end,
            callback = function()
                self:openFileBrowser(self.data.archive_dir_path)
            end,
        },
        {
            text = _("Go to last copied/moved from folder"),
            enabled_func = function()
                return self.data.last_copied_from_dir ~= nil
            end,
            callback = function()
                self:openFileBrowser(self.data.last_copied_from_dir)
            end,
            separator = true,
        },
        {
            text_func = function()
                return T(_("Archive folder: %1"), self.data.archive_dir_path or _("not set"))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local caller_callback = function(path)
                    self.data.archive_dir_path = path .. "/"
                    self.updated = true
                    touchmenu_instance:updateItems()
                end
                filemanagerutil.showChooseDialog(_("Archive folder:"), caller_callback, self.data.archive_dir_path)
            end,
        },
    }
end

function MoveToArchive:isActionEnabled()
    return self.document ~= nil and ((ffiUtil.dirname(self.document.file) .. "/") ~= self.data.archive_dir_path )
end

function MoveToArchive:onMoveToArchive(do_copy)
    self:loadSettings()
    local archive_dir_path = self.data.archive_dir_path
    if not (archive_dir_path and util.directoryExists(archive_dir_path)) then return true end
    local document_full_path = self.document.file
    local last_copied_from_dir, filename = util.splitFilePathName(document_full_path)
    if self.data.last_copied_from_dir ~= last_copied_from_dir then
        self.data.last_copied_from_dir = last_copied_from_dir
        self.updated = true
    end
    local dest_file = string.format("%s%s", archive_dir_path, filename)
    local text
    if do_copy then
        text = _("Book copied.\nDo you want to open it from the archive folder?")
        FileManager:copyFileFromTo(document_full_path, archive_dir_path)
    else
        text = _("Book moved.\nDo you want to open it from the archive folder?")
        FileManager:moveFile(document_full_path, archive_dir_path)
        require("readhistory"):updateItem(document_full_path, dest_file) -- (will update "lastfile" if needed)
        require("readcollection"):updateItem(document_full_path, dest_file)
    end
    DocSettings.updateLocation(document_full_path, dest_file, do_copy)
    if UIManager:isInSilentMode() then
        -- no dialog to allow multi-action executing
        self:openFileBrowser(last_copied_from_dir)
    else
        UIManager:show(ConfirmBox:new{
            text = text,
            ok_text = _("Open"),
            ok_callback = function()
                self.ui:switchDocument(dest_file)
            end,
            cancel_callback = function()
                self:openFileBrowser(last_copied_from_dir)
            end,
        })
    end
    return true
end

function MoveToArchive:openFileBrowser(path)
    if self.document then
        self.ui:onClose()
        self.ui:showFileManager(path)
    else
        self.ui.file_chooser:changeToPath(path)
    end
end

function MoveToArchive:onFlushSettings()
    if self.updated then
        self.settings:flush()
        self.updated = nil
    end
end

return MoveToArchive
