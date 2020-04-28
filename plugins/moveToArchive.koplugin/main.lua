local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local DocSettings = require("frontend/docsettings")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local Ftp = require("apps/cloudstorage/ftp")
local FtpApi = require("apps/cloudstorage/ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ftp = require("socket.ftp")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local MoveToArchive = WidgetContainer:new{
    name = "move2archive",
}

local initialized = false
local moveToArchive_config_file = "moveToArchive_settings.lua"
local archive_dir_config_key = "archive_dir";
local archive_dir_path
local moveToArchive_settings


function MoveToArchive:init()
    self.ui.menu:registerToMainMenu(self)
end

function MoveToArchive:addToMainMenu(menu_items)
    self:lazyInitialization()
    menu_items.moveToArchive = {
        text = _("Move to Archive"),
        sub_item_table = {
            {
                text = _("Move current book to archive"),
                keep_menu_open = true,
                callback = self.moveToArchive,
            },
            {
                text = _("Copy current book to archive"),
                keep_menu_open = true,
                callback = self.copyToArchive,
            },
            {
                text = _("Go to archive folder"),
                callback = function()
                    if not archive_dir_path then
                        UIManager:show(InfoMessage:new{
                            text = _("No archive directory. Please set it first")
                         })
                         return
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then
                        FileManager.instance:reinit(archive_dir_path)
                    else
                        FileManager:showFiles(archive_dir_path)
                    end
                end,
            },
            -- {
            --     text = _("Go back to previous folder"),
            --     callback = function()
            --         local FileManager = require("apps/filemanager/filemanager")
            --         if FileManager.instance then
            --             FileManager.instance:reinit(archive_dir_path)
            --         else
            --             FileManager:showFiles(archive_dir_path)
            --         end
            --     end,
            -- },
            {
                text = _("Set archive directory"),
                keep_menu_open = true,
                callback =  self.setArchiveDirectory,
            },
            -- {
            --     text = _("Help"),
            --     keep_menu_open = true,
            --     callback = function()
            --         UIManager:show(InfoMessage:new{
            --             text = T(_('MoveToArchive lets you send articles found on PC/Android phone to your Ebook reader (using ftp server).\n\nMore details: https://github.com/mwoz123/moveToArchive\n\nDownloads to local folder: %1'), BD.dirpath(archive_dir_path))
            --         })
            --     end,
            -- },
        },
    }
end

function MoveToArchive:lazyInitialization()
   if not initialized then
        logger.dbg("MoveToArchive: obtaining archive folder")
        moveToArchive_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), moveToArchive_config_file))
        if moveToArchive_settings:has(archive_dir_config_key) then
            archive_dir_path = moveToArchive_settings:readSetting(archive_dir_config_key)
        end
    end
end

function MoveToArchive:moveToArchive()
    MoveToArchive:copyToArchive()
    -- remove files
end

function MoveToArchive:copyToArchive()
    if not archive_dir_path then
        UIManager:show(InfoMessage:new{
            text = _("No archive directory. Please set it first")
         })
         return
    end
end



function MoveToArchive:removeReadActicles()
    logger.dbg("MoveToArchive: Removing read articles from :", archive_dir_path)
    for entry in lfs.dir(archive_dir_path) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = archive_dir_path .. entry
            if DocSettings:hasSidecarFile(entry_path) then
               local entry_mode = lfs.attributes(entry_path, "mode")
               if entry_mode == "file" then
                   os.remove(entry_path)
                   local sdr_dir = DocSettings:getSidecarDir(entry_path)
                   logger.dbg("MoveToArchive: sdr dir to be removed:", sdr_dir)
                   FFIUtil.purgeDir(sdr_dir)
               end
            end
        end
    end
    UIManager:show(InfoMessage:new{
       text = _("All read articles removed.")
    })
end

function MoveToArchive:setArchiveDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("MoveToArchive: set archive directory to: ", path)
            moveToArchive_settings:saveSetting(archive_dir_config_key, ("%s/"):format(path))
            moveToArchive_settings:flush()

            -- initialized = false
            -- MoveToArchive:lazyInitialization()
        end,
    }:chooseDir()
end


function MoveToArchive:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and archive_dir_path and archive_dir_path == string.sub(document_full_path, 1, string.len(archive_dir_path)) then
        logger.dbg("MoveToArchive: document_full_path:", document_full_path)
        logger.dbg("MoveToArchive: archive_dir_path:", archive_dir_path)
        logger.dbg("MoveToArchive: removing MoveToArchive file from history.")
        ReadHistory:removeItemByPath(document_full_path)
    end
end

return MoveToArchive
