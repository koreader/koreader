local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local Cloud = WidgetContainer:extend{
    name = "cloudstorage",
    title = _("Cloud storage+"),
    settings_file = DataStorage:getSettingsDir() .. "/cloudstorage.lua",
    settings = nil,
    servers = nil, -- user servers (array)
    providers = nil, -- cloud providers (hash table); must provide at least .config, .run, .listFolder
    updated = nil,
}

function Cloud:init()
    self:getProviders()
    self:onDispatcherRegisterActions() -- will call loadSettings()
    self.ui.menu:registerToMainMenu(self)
end

function Cloud:getProviders()
    if not Cloud.providers then
        Cloud.providers = {}
        util.findFiles(self.path .. "/providers", function(fullpath, filename)
            if filename:match("%.lua$") then
                local ok, provider = pcall(dofile, fullpath)
                if ok and next(provider) and provider.name and provider.config and provider.run and provider.listFolder then
                    Cloud.providers[filename:sub(1, -5)] = provider
                end
            end
        end, false)
    end
end

function Cloud:loadSettings()
    if not Cloud.settings then
        Cloud.settings = LuaSettings:open(self.settings_file)
        if not next(Cloud.settings.data) then
            self.updated = true -- first run, force flush
        end
    end
    self.servers = Cloud.settings:readSetting("cs_servers", {})
end

function Cloud:onFlushSettings()
    if self.updated then
        Cloud.settings:flush()
        self.updated = nil
    end
end

function Cloud:onDispatcherRegisterActions()
    self:loadSettings()
    Dispatcher:registerAction("cloudstorage", { category="none", event="ShowCloudStorageList", title=self.title, general=true })
end

function Cloud:addToMainMenu(menu_items)
    menu_items.cloudstorage = {
        text = self.title,
        callback = function()
            self:onShowCloudStorageList()
        end,
    }
end

function Cloud:onShowCloudStorageList(caller_choose_folder_callback)
    local base
    local CloudStorage = require("cloudstorage")
    base = CloudStorage:new{
        title = self.title,
        subtitle = "",
        settings = self.settings,
        servers = self.servers,
        providers = self.providers,
        _manager = self,
        -- external modules can call the plugin to choose the remote folder
        -- see CloudStorage:showFolderChooseDialog() for details of calling the callback
        caller_choose_folder_callback = caller_choose_folder_callback,
        close_callback = function()
            if not caller_choose_folder_callback then
                if base.choose_folder_callback then
                    -- keep open after choosing a remote folder for our "Sync folder"
                    base:init(true)
                    UIManager:show(base)
                else
                    local download_dir = self.settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
                    local fc = self.ui.file_chooser
                    if fc and fc.path == download_dir then
                        fc:refreshPath()
                    end
                end
            end
        end,
    }
    for _, provider in pairs(self.providers) do
        provider.base = base
    end
    base:show()
end

function Cloud:stopPlugin()
    Cloud.providers = nil
end

-- cloud sync (Statistics, Vocabulary builder)

function Cloud:getServerNameType(server)
    local provider = server and server.type and self.providers[server.type]
    return provider and string.format("%s (%s)", server.name, provider.name)
end

function Cloud.getReadablePath(server)
    local url = server and server.url
    if url then
        url = util.stringStartsWith(url, "/") and url:sub(2) or url
        url = util.urlDecode(url) or url
        url = util.stringEndsWith(url, "/") and url or url .. "/"
        url = server.type == "dropbox" and "/" .. url
            or (server.address:sub(-1) == "/" and server.address or server.address .. "/") .. url
        url = url:sub(-2) == "//" and url:sub(1, -2) or url
    end
    return url
end

-- Former SyncService https://github.com/koreader/koreader/pull/9709
-- Prepares three files for sync_cb to call to do the actual syncing:
-- * local_file (one that is being used)
-- * income_file (one that has just been downloaded from Cloud to be merged, then to be deleted)
-- * cached_file (the one that was uploaded in the previous round of syncing)
--
-- How it works:
--
-- If we simply merge the local file with the income file (ignore duplicates), then items that have been deleted locally
-- but not remotely (on other devices) will re-emerge in the result file. The same goes for items deleted remotely but
-- not locally. To avoid this, we first need to delete them from both the income file and local file.
--
-- The problem is how to identify them, and that is when the cached file comes into play.
-- The cached file represents what local and remote agreed on previously (was identical to local and remote after being uploaded
-- the previous round), by comparing it with local file, items no longer in local file are ones being recently deleted.
-- The same applies to income file. Then we can delete them from both local and income files to be ready for merging. (The actual
-- deletion and merging procedures happen in sync_cb as users of this service will have different file specifications)
--
-- After merging, the income file is no longer needed and is deleted. The local file is uploaded and then a copy of it is saved
-- and renamed to replace the old cached file (thus the naming). The cached file stays (in the same folder) till being replaced
-- in the next round.
function Cloud:sync(server, file_path, sync_cb, is_silent, caller_pre_callback)
    local provider = server and server.type and self.providers[server.type]
    if not provider then return end
    provider.base = server
    provider.run(function()
        if caller_pre_callback then
            caller_pre_callback()
        end
        UIManager:nextTick(function()
            local file_name = ffiUtil.basename(file_path)
            local income_file_path = file_path .. ".temp" -- file downloaded from server
            local cached_file_path = file_path .. ".sync" -- file uploaded to server last time
            local fail_msg = _("Something went wrong when syncing, please check your network connection and try again later.")
            local show_msg = function(msg)
                if is_silent then return end
                UIManager:show(InfoMessage:new{
                    text = msg or fail_msg,
                    timeout = 3,
                })
            end
            local etag
            local code_response = 412 -- If-Match header failed
            while code_response == 412 do
                os.remove(income_file_path)
                code_response, etag = provider.downloadFile(server.url.."/"..file_name, income_file_path)
                if code_response ~= 200 and code_response ~= 404
                    and not (server.type == "dropbox" and code_response == 409)
                    and not (server.type == "ftp" and code_response == 550)
                then
                    show_msg()
                    return
                end
                local ok, cb_return = pcall(sync_cb, file_path, cached_file_path, income_file_path)
                if not ok or not cb_return then
                    show_msg()
                    if not ok then logger.err("sync service callback failed:", cb_return) end
                    return
                end
                code_response = provider.uploadFile(server.url, file_path, etag, true) or 412 -- FTP returns nil if failed
            end
            os.remove(income_file_path)
            if type(code_response) == "number" and code_response >= 200 and code_response < 300 then
                os.remove(cached_file_path)
                ffiUtil.copyFile(file_path, cached_file_path)
                UIManager:show(Notification:new{
                    text = _("Successfully synchronized."),
                    timeout = 2,
                })
            else
                show_msg()
            end
        end)
    end)
end

return Cloud
