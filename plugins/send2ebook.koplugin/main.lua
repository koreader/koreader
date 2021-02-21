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

local Send2Ebook = WidgetContainer:new{
    name = "send2ebook",
}

local initialized = false
local send2ebook_config_file = "send2ebook_settings.lua"
local config_key_custom_dl_dir = "custom_dl_dir";
local default_download_dir_name = "send2ebook"
local download_dir_path
local send2ebook_settings

function Send2Ebook:downloadFileAndRemove(connection_url, remote_path, local_download_path)
    local url = connection_url .. remote_path
    local response = ftp.get(url ..";type=i")

    if response ~= nil then
        local_download_path = util.fixUtf8(local_download_path, "_")
        local file = io.open(local_download_path, "w")
        file:write(response)
        file:close()
        FtpApi:delete(url)
        return 1
    else
        logger.err("Send2Ebook: Error. Invalid connection data? ")
        return 0
    end
end

function Send2Ebook:init()
    self.ui.menu:registerToMainMenu(self)
end

function Send2Ebook:addToMainMenu(menu_items)
    self:lazyInitialization()
    menu_items.send2ebook = {
        text = _("Send2Ebook (Receiver)"),
        sub_item_table = {
            {
                text = _("Download and remove from server"),
                keep_menu_open = true,
                callback = function()
                    local connect_callback = function()
                        self:process()
                    end
                    NetworkMgr:runWhenOnline(connect_callback)
                end,
            },
            {
                text = _("Go to download folder"),
                callback = function()
                    if self.ui.document then
                        self.ui:onClose()
                    end
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then
                        FileManager.instance:reinit(download_dir_path)
                    else
                        FileManager:showFiles(download_dir_path)
                    end
                end,
            },
            {
                text = _("Remove read (opened) articles"),
                keep_menu_open = true,
                callback = self.removeReadActicles,
            },
            {
                text = _("Set custom download folder"),
                keep_menu_open = true,
                callback =  self.setCustomDownloadDirectory,
            },
            {
                text = _("Settings"),
                keep_menu_open = true,
                callback = self.editFtpConnection,
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_('Send2Ebook lets you send articles found on PC/Android phone to your Ebook reader (using ftp server).\n\nMore details: https://github.com/mwoz123/send2ebook\n\nDownloads to local folder: %1'), BD.dirpath(download_dir_path))
                    })
                end,
            },
        },
    }
end

function Send2Ebook:lazyInitialization()
   if not initialized then
        logger.dbg("Send2Ebook: obtaining download folder")
        send2ebook_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), send2ebook_config_file))
        if send2ebook_settings:has(config_key_custom_dl_dir) then
            download_dir_path = send2ebook_settings:readSetting(config_key_custom_dl_dir)
        else
            download_dir_path = ("%s/%s/"):format(DataStorage:getFullDataDir(), default_download_dir_name)
        end

        if not lfs.attributes(download_dir_path, "mode") then
            logger.dbg("Send2Ebook: Creating initial directory")
            lfs.mkdir(download_dir_path)
        end
    end
end

function Send2Ebook:process()
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    logger.dbg("Send2Ebook: force repaint due to upcoming blocking calls")
    UIManager:forceRePaint()
    UIManager:close(info)

    local count = 1
    local ftp_config = send2ebook_settings:readSetting("ftp_config") or {address="Please setup ftp in settings", username="", password="", folder=""}

    local connection_url = FtpApi:generateUrl(ftp_config.address, util.urlEncode(ftp_config.username), util.urlEncode(ftp_config.password))

    local ftp_files_table = FtpApi:listFolder(connection_url .. ftp_config.folder, ftp_config.folder) --args looks strange but otherwise resonse with invalid paths

    if not ftp_files_table then
      info = InfoMessage:new{ text = T(_("Could not get file list for server: %1, user: %2, folder: %3"), BD.ltr(ftp_config.address), ftp_config.username, BD.dirpath(ftp_config.folder)) }
    else
      local total_entries = table.getn(ftp_files_table)
      logger.dbg("Send2Ebook: total_entries ", total_entries)
      if total_entries > 1 then total_entries = total_entries -2 end --remove result "../" (upper folder) and "./" (current folder)
      for idx, ftp_file in ipairs(ftp_files_table) do
          logger.dbg("Send2Ebook: processing ftp_file:", ftp_file)
          --- @todo Recursive download folders.
          if ftp_file["type"] == "file" then

              info = InfoMessage:new{ text = T(_("Processing %1/%2"), count, total_entries) }
              UIManager:show(info)
              UIManager:forceRePaint()
              UIManager:close(info)

              local remote_file_path = ftp_file["url"]
              logger.dbg("Send2Ebook: remote_file_path", remote_file_path)
              local local_file_path = download_dir_path .. ftp_file["text"]
              count = count + Send2Ebook:downloadFileAndRemove(connection_url, remote_file_path, local_file_path)
              end
          info = InfoMessage:new{ text = T(_("Processing finished. Success: %1, failed: %2"), count -1, total_entries +1 - count) }
          end
    end
    UIManager:show(info)
    NetworkMgr:afterWifiAction()
end

function Send2Ebook:removeReadActicles()
    logger.dbg("Send2Ebook: Removing read articles from :", download_dir_path)
    for entry in lfs.dir(download_dir_path) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = download_dir_path .. entry
            if DocSettings:hasSidecarFile(entry_path) then
               local entry_mode = lfs.attributes(entry_path, "mode")
               if entry_mode == "file" then
                   os.remove(entry_path)
                   local sdr_dir = DocSettings:getSidecarDir(entry_path)
                   logger.dbg("Send2Ebook: sdr dir to be removed:", sdr_dir)
                   FFIUtil.purgeDir(sdr_dir)
               end
            end
        end
    end
    UIManager:show(InfoMessage:new{
       text = _("All read articles removed.")
    })
end

function Send2Ebook:setCustomDownloadDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("Send2Ebook: set download directory to: ", path)
            send2ebook_settings:saveSetting(config_key_custom_dl_dir, ("%s/"):format(path))
            send2ebook_settings:flush()

            initialized = false
            Send2Ebook:lazyInitialization()
        end,
    }:chooseDir()
end

function Send2Ebook:editFtpConnection()
    local item = send2ebook_settings:readSetting("ftp_config") or {text="ignore this field, it's not used here;) fill rest", address="ftp://", username="",password="" , folder="/"}
    local callbackEdit = function(updated_config, fields)
        local data = {text=fields[1], address=fields[2], username=fields[3],password=fields[4] , folder=fields[5]}
        send2ebook_settings:saveSetting("ftp_config", data)
        send2ebook_settings:flush()
        initialized = false
        Send2Ebook:lazyInitialization()
    end
    Ftp:config(item, callbackEdit)
end

function Send2Ebook:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and download_dir_path and download_dir_path == string.sub(document_full_path, 1, string.len(download_dir_path)) then
        logger.dbg("Send2Ebook: document_full_path:", document_full_path)
        logger.dbg("Send2Ebook: download_dir_path:", download_dir_path)
        logger.dbg("Send2Ebook: removing Send2Ebook file from history.")
        ReadHistory:removeItemByPath(document_full_path)
        self.ui:setLastDirForFileBrowser(download_dir_path)
    end
end

return Send2Ebook
