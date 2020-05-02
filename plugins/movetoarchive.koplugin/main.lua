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
}

local move_to_archive_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), "move_to_archive_settings.lua"))
local archive_dir_config_key = "archive_dir";
local last_copied_from_config_key = "last_copied_from_dir";
local archive_dir_path = move_to_archive_settings:readSetting(archive_dir_config_key)
local last_copied_from_dir = move_to_archive_settings:readSetting(last_copied_from_config_key)

function MoveToArchive:init()
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
                    if not archive_dir_path then
                        self:showNoArchiveConfirmBox()
                        return
                    end
                    self:openFileBrowser(archive_dir_path)
                end,
            },
            {
                text = _("Go to last copied/moved from folder"),
                callback = function()
                    if not last_copied_from_dir then
                        UIManager:show(InfoMessage:new{
                            text = _("No previous folder found.")
                         })
                        return
                    end
                    self:openFileBrowser(last_copied_from_dir)
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
    if not archive_dir_path then
        self:showNoArchiveConfirmBox()
        return
    end
    local document_full_path = self.ui.document.file
    self.ui:onClose()
    local filename
    last_copied_from_dir, filename = util.splitFilePathName(document_full_path)

    logger.dbg("MoveToArchive: last_moved/copied_from_dir :", last_copied_from_dir)
    move_to_archive_settings:saveSetting(last_copied_from_config_key, ("%s/"):format(last_copied_from_dir))

    if is_move_process then
        FileManager:moveFile(document_full_path, archive_dir_path)
        FileManager:moveFile(DocSettings:getSidecarDir(document_full_path), archive_dir_path)
    else
        FileManager:copyFileFromTo(document_full_path, archive_dir_path)
    end
    local dest_file = string.format("%s/%s", archive_dir_path, filename)
    require("readhistory"):updateItemByPath(document_full_path, dest_file)
    ReadCollection:updateItemByPath(document_full_path, dest_file)
    -- Update last open file.
    if G_reader_settings:readSetting("lastfile") == document_full_path then
        G_reader_settings:saveSetting("lastfile", dest_file)
    end

    self:showConfirmBox(moved_done_text, _("Ok"), function () ReaderUI:showReader(archive_dir_path .. filename) end,
        function () self:openFileBrowser(last_copied_from_dir) end)
    ReadHistory:removeItemByPath(document_full_path)
end


function MoveToArchive:setArchiveDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            archive_dir_path = path
            move_to_archive_settings:saveSetting(archive_dir_config_key, ("%s/"):format(path))
            move_to_archive_settings:flush()
        end,
    }:chooseDir()
end

function MoveToArchive:showNoArchiveConfirmBox()
    self:showConfirmBox(_("No archive directory.\nDo you want to set it now?"), _("Set archive folder"), self.setArchiveDirectory)
end

function MoveToArchive:showConfirmBox(text, ok_text, ok_callback, cancel_callback)
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        ok_callback = ok_callback,
        cancel_callback = cancel_callback
    })
end


function MoveToArchive:isActionEnabled()
    return self.ui.document ~= nil and ((BaseUtil.dirname(self.ui.document.file) .. "/") ~= archive_dir_path )
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