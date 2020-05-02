local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local ReadCollection = require("readcollection")
local ReadHistory = require("readhistory")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("frontend/util")
local BaseUtil = require("ffi/util")
local _ = require("gettext")

local MoveToArchive = WidgetContainer:new{
    name = "move2archive",
    move_to_archive_settings = nil,
    archive_dir_path = nil,
    last_copied_from_dir = nil,
}

function MoveToArchive:init()
    self.move_to_archive_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "move_to_archive_settings.lua"),
    self.archive_dir_path = self.move_to_archive_settings:readSetting("archive_dir")
    self.last_copied_from_dir = self.move_to_archive_settings:readSetting("last_copied_from_dir")
    self.ui.menu:registerToMainMenu(self)
end

function MoveToArchive:addToMainMenu(menu_items)
    menu_items.move_to_archive = {
        text = _("Move to archive"),
        sub_item_table = {
            {
                text = _("Move current book to archive"),
                callback = function() self:moveToArchive() end,
                enabled_func = function() return self:isActionEnabled() end,
            },
            {
                text = _("Copy current book to archive"),
                callback = function() self:copyToArchive() end,
                enabled_func = function() return self:isActionEnabled() end,
            },
            {
                text = _("Go to archive folder"),
                callback = function()
                    if not self.archive_dir_path then
                        self:showNoArchiveConfirmBox()
                        return
                    end
                    self:openFileBrowser(self.archive_dir_path)
                end,
            },
            {
                text = _("Go to last copied/moved from folder"),
                callback = function()
                    if not self.last_copied_from_dir then
                        UIManager:show(InfoMessage:new{
                            text = _("No previous folder found.")
                         })
                        return
                    end
                    self:openFileBrowser(self.last_copied_from_dir)
                end,
            },
            {
                text = _("Set archive directory"),
                keep_menu_open = true,
                callback =  self.setArchiveDirectory,
            }
        },
    }
end

function MoveToArchive:moveToArchive()
    local move_done_text = _("Book moved.\nDo you want to open it from the archive folder?")
    self:commonProcess(true, move_done_text)
end

function MoveToArchive:copyToArchive()
    local copy_done_text =_("Book copied.\nDo you want to open it from the archive folder?")
    self:commonProcess(false, copy_done_text)
end

function MoveToArchive:commonProcess(is_move_process, moved_done_text)
    if not self.archive_dir_path then
        self:showNoArchiveConfirmBox()
        return
    end
    local document_full_path = self.ui.document.file
    local filename
    self.last_copied_from_dir, filename = util.splitFilePathName(document_full_path)

    logger.dbg("MoveToArchive: last_moved/copied_from_dir :", self.last_copied_from_dir)
    self.move_to_archive_settings:saveSetting("last_copied_from_dir", ("%s/"):format(self.last_copied_from_dir))
    self.move_to_archive_settings:flush()

    self.ui:onClose()
    if is_move_process then
        FileManager:moveFile(document_full_path, self.archive_dir_path)
        FileManager:moveFile(DocSettings:getSidecarDir(document_full_path), self.archive_dir_path)
    else
        FileManager:copyFileFromTo(document_full_path, self.archive_dir_path)
        FileManager:copyRecursive(DocSettings:getSidecarDir(document_full_path), self.archive_dir_path)
    end
    local dest_file = string.format("%s/%s", self.archive_dir_path, filename)
    ReadHistory:updateItemByPath(document_full_path, dest_file)
    ReadCollection:updateItemByPath(document_full_path, dest_file)
    -- Update last open file.
    if G_reader_settings:readSetting("lastfile") == document_full_path then
        G_reader_settings:saveSetting("lastfile", dest_file)
    end

    UIManager:show(ConfirmBox:new{
        text = moved_done_text,
        ok_callback = function ()
            ReaderUI:showReader(self.archive_dir_path .. filename)
        end,
        cancel_callback = function ()
            if DocSettings:open(dest_file):readSetting("percent_finished") == 1 then
                ReadHistory:removeItemByPath(dest_file)
            end
            self:openFileBrowser(self.last_copied_from_dir)
        end,
    })
end


function MoveToArchive:setArchiveDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            self.archive_dir_path = path
            self.move_to_archive_settings:saveSetting("archive_dir", ("%s/"):format(path))
            self.move_to_archive_settings:flush()
        end,
    }:chooseDir()
end

function MoveToArchive:showNoArchiveConfirmBox()
    UIManager:show(ConfirmBox:new{
        text = _("No archive directory.\nDo you want to set it now?"),
        ok_text = _("Set archive folder"),
        ok_callback = ok_callback = function()
            self:setArchiveDirectory()
        end,
    })
end

function MoveToArchive:isActionEnabled()
    return self.ui.document ~= nil and ((BaseUtil.dirname(self.ui.document.file) .. "/") ~= self.archive_dir_path )
end

function MoveToArchive:openFileBrowser(path)
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(path)
    else
        FileManager:showFiles(path)
    end
end

return MoveToArchive
