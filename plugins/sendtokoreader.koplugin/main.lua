local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local Ftp = require("apps/cloudstorage/ftp")
local FtpApi = require("apps/cloudstorage/ftpapi")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffi = require("ffi")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local SendToKoreader = WidgetContainer:new{}

local initialized = false
local wifi_enabled_before_action = true
local feed_config_file = "feed_config.lua"
local send_to_koreader_config_file = "send_to_koreader_settings.lua"
local config_key_custom_dl_dir = "custom_dl_dir";
local default_download_dir_name = "sendToKoreader"
local download_dir_path, feed_config_path

local function stringEnds(String,End)
   return End=='' or string.sub(String,-string.len(End))==End
end


function SendToKoreader:downloadFileAndRemove(item, address, user, pass, path, close)
    local url = FtpApi:generateUrl(address, user, pass) .. item
    local response = FtpApi:downloadFile(url)

    if response ~= nil then
        path = util.fixUtf8(path, "_")
        local file = io.open(path, "w")
        file:write(response)
        file:close()
        FtpApi:delete(url)
    else
        logger.err("Invalid address: ", url)
        return
    end
end


-- TODO: implement as NetworkMgr:afterWifiAction with configuration options
function SendToKoreader:afterWifiAction()
    if not wifi_enabled_before_action then
        NetworkMgr:promptWifiOff()
    end
end

function SendToKoreader:init()
    self.ui.menu:registerToMainMenu(self)
end

function SendToKoreader:addToMainMenu(menu_items)
    self:lazyInitialization()
    menu_items.send_to_koreader = {
        text = _("Send to Koreader"),
        sub_item_table = {
            {
                text = _("Download and remove from server"),
                callback = function()
                    self:process()
                end,
            },
            {
                text = _("Go to news folder"),
                callback = function()
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then
                        FileManager.instance:reinit(download_dir_path)
                    else
                        FileManager:showFiles(download_dir_path)
                    end
                end,
            },
            {
                text = _("Remove news"),
                callback = function() self:removeNewsButKeepConfig() end,
            },
            {
                text = _("Set custom download directory"),
                callback = function() self:setCustomDownloadDirectory() end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Change feeds configuration"),
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = T(_("To change feed (Atom/RSS) sources please manually edit the configuration file:\n%1\n\nIt is very simple and contains comments as well as sample configuration."),
                                         feed_config_path)
                            })
                        end,
                    },
                },
            },
            {
                text = _("Help"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_("News downloader retrieves RSS and Atom news entries and stores them to:\n%1\n\nEach entry is a separate html file, that can be browsed by KOReader file manager.\nItems download limit can be configured in Settings."),
                                 download_dir_path)
                    })
                end,
            },
        },
    }
end

function SendToKoreader:lazyInitialization()
   if not initialized then
        logger.dbg("SendToKoreader: obtaining news folder")
        local send_to_koreader_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), send_to_koreader_config_file))
        if send_to_koreader_settings:has(config_key_custom_dl_dir) then
            download_dir_path = send_to_koreader_settings:readSetting(config_key_custom_dl_dir)
        else
            download_dir_path = ("%s/%s/"):format(DataStorage:getFullDataDir(), default_download_dir_name)
        end

        if not lfs.attributes(download_dir_path, "mode") then
            logger.dbg("SendToKoreader: Creating initial directory")
            lfs.mkdir(download_dir_path)
        end
    end
end

function SendToKoreader:process()
    local info = InfoMessage:new{ text = _("Connecting ...") }
    UIManager:show(info)
    logger.dbg("force repaint due to upcoming blocking calls")
    UIManager:forceRePaint()
    UIManager:close(info)

    local host = "ftp://mkwk018.cba.pl"
    local user = "koreader"
    local passwd = "Koreader123"
    local folder = "/" .. user .. ".cba.pl"

    local count = 0
      local fileTable = Ftp:run(host, user, passwd, folder)
          local total_entries = table.getn(fileTable)
      for idx, ftpFile in ipairs(fileTable) do
      logger.dbg("ftpFile ", ftpFile)
          if ftpFile["type"] == "file" and stringEnds(ftpFile["text"], ".epub") then

          info = InfoMessage:new{ text = T(_("Processing %1/%2"), idx, total_entries) }
          UIManager:show(info)
          UIManager:forceRePaint()
          UIManager:close(info)

          local remote_file_path = ftpFile["url"]
          logger.dbg("remote_file_path", remote_file_path)
          local local_file_path = download_dir_path .. ftpFile["text"]
          self:downloadFileAndRemove(remote_file_path, host, user, passwd, local_file_path)
          count = count +1
          end
      end
      info = InfoMessage:new{ text = T(_("Processing finished. Processed: %1"), count) }
      UIManager:show(info)

    SendToKoreader:afterWifiAction()
end


function SendToKoreader:removeNewsButKeepConfig()
    logger.dbg("SendToKoreader: Removing news from :", download_dir_path)
    for entry in lfs.dir(download_dir_path) do
        if entry ~= "." and entry ~= ".." and entry ~= feed_config_file then
            local entry_path = download_dir_path .. "/" .. entry
            local entry_mode = lfs.attributes(entry_path, "mode")
            if entry_mode == "file" then
                ffi.C.remove(entry_path)
            elseif entry_mode == "directory" then
                FFIUtil.purgeDir(entry_path)
            end
        end
    end
    UIManager:show(InfoMessage:new{
       text = _("All news removed.")
    })
end

function SendToKoreader:setCustomDownloadDirectory()
    UIManager:show(InfoMessage:new{
       text = _("To select a folder press down and hold it for 1 second.")
    })
    require("ui/downloadmgr"):new{
       title = _("Choose download directory"),
       onConfirm = function(path)
           logger.dbg("SendToKoreader: set download directory to: ", path)
           local send_to_koreader_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), send_to_koreader_config_file))
           send_to_koreader_settings:saveSetting(config_key_custom_dl_dir, ("%s/"):format(path))
           send_to_koreader_settings:flush()

           logger.dbg("SendToKoreader: Coping to new download folder previous feed_config_file from: ", feed_config_path)
           FFIUtil.copyFile(feed_config_path, ("%s/%s"):format(path, feed_config_file))

           initialized = false
           self:lazyInitialization()
       end,
    }:chooseDir()
end

function SendToKoreader:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and download_dir_path == string.sub(document_full_path, 1, string.len(download_dir_path)) then
        logger.dbg("SendToKoreader: document_full_path:", document_full_path)
        logger.dbg("SendToKoreader: download_dir_path:", download_dir_path)
        logger.dbg("SendToKoreader: removing SendToKoreader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
    end
end



return SendToKoreader
