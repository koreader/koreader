local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("frontend/util")
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
    menu_items.moveToArchive = {
        text = _("Move to Archive"),
        sub_item_table = {
            {
                text = _("Move current book to archive"),
                callback = self.moveToArchive,
            },
            {
                text = _("Copy current book to archive"),
                callback = self.copyToArchive,
            },
            {
                text = _("Go to archive folder"),
                callback = function()
                    if not archive_dir_path then
                        MoveToArchive:showNoArchiveConfirmBox()
                        return
                    end
                    if FileManager.instance then
                        FileManager.instance:reinit(archive_dir_path)
                    else
                        FileManager:showFiles(archive_dir_path)
                    end
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
                    if FileManager.instance then
                        FileManager.instance:reinit(last_copied_from_dir)
                    else
                        FileManager:showFiles(last_copied_from_dir)
                    end
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
    if not archive_dir_path then
        MoveToArchive:showNoArchiveConfirmBox()
        return
    end
    local document_full_path = G_reader_settings:readSetting("lastfile")
    local filename
    last_copied_from_dir, filename = util.splitFilePathName(document_full_path)
    logger.dbg("MoveToArchive: last_copied_from_dir :", last_copied_from_dir)

    FileManager:moveFile(document_full_path, archive_dir_path)

    move_to_archive_settings:saveSetting(last_copied_from_config_key, ("%s/"):format(last_copied_from_dir))

    ReadHistory:removeItemByPath(document_full_path)

    MoveToArchive:showConfirmBox(_("Book moved. \nDo you want to open it from archive folder?"), function () ReaderUI:showReader(archive_dir_path .. filename) end)
end

function MoveToArchive:copyToArchive()
    if not archive_dir_path then
        MoveToArchive:showNoArchiveConfirmBox()
        return
    end
    local document_full_path = G_reader_settings:readSetting("lastfile")
    local filename
    last_copied_from_dir, filename = util.splitFilePathName(document_full_path)

    logger.dbg("MoveToArchive: last_copied_from_dir :", last_copied_from_dir)
    move_to_archive_settings:saveSetting(last_copied_from_config_key, ("%s/"):format(last_copied_from_dir))

    FileManager:copyFileFromTo(document_full_path, archive_dir_path)

    MoveToArchive:showConfirmBox(_("Book copied. \nDo you want to open it from archive folder?"), function () ReaderUI:showReader(archive_dir_path .. filename) end)
end


function MoveToArchive:setArchiveDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("MoveToArchive: set archive directory to: ", path)
            move_to_archive_settings:saveSetting(archive_dir_config_key, ("%s/"):format(path))
            move_to_archive_settings:flush()

            archive_dir_path = path
        end,
    }:chooseDir()
end

function MoveToArchive:showNoArchiveConfirmBox()
    MoveToArchive:showConfirmBox(_("No archive directory. \nDo you want to set it now?"), self.setArchiveDirectory)
end

function MoveToArchive:showConfirmBox(text, ok_callback)
    UIManager:show(ConfirmBox:new{
        text = text,
        cancel_text = _("Cancel"),
        ok_text = _("Ok"),
        ok_callback = ok_callback
    })
end


return MoveToArchive
