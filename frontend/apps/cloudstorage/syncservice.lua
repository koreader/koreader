local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local util = require("util")

local _ = require("gettext")

local server_types = {
    dropbox = _("Dropbox"),
    webdav = _("WebDAV"),
}
local indent = ""

local SyncService = Menu:extend{
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
    title = _("Cloud sync settings"),
    title_face = Font:getFace("smallinfofontbold"),
}

function SyncService:init()
    self.item_table = self:generateItemTable()
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    Menu.init(self)
end

function SyncService:generateItemTable()
    local item_table = {}
    -- select and/or add server
    local added_servers = LuaSettings:open(DataStorage:getSettingsDir().."/cloudstorage.lua"):readSetting("cs_servers") or {}
    for _, server in ipairs(added_servers) do
        if server.type == "dropbox" or server.type == "webdav" then
            local item = {
                text = indent .. server.name,
                address = server.address,
                username = server.username,
                password = server.password,
                type = server.type,
                url = server.url,
                mandatory = server_types[server.type],
            }
            item.callback = function()
                require("ui/downloadmgr"):new{
                item = item,
                onConfirm = function(path)
                    server.url = path
                    self.onConfirm(server)
                    self:onClose()
                end,
                }:chooseCloudDir()
            end
            table.insert(item_table, item)
        end
    end
    if #item_table > 0 then
        table.insert(item_table, 1, {
            text = _("Choose cloud service:"),
            bold = true,
        })
    end
    table.insert(item_table, {
        text = _("Add service"),
        bold = true,
        callback = function()
            local cloud_storage = require("apps/cloudstorage/cloudstorage"):new{}
            local onClose = cloud_storage.onClose
            cloud_storage.onClose = function(this)
                onClose(this)
                self:switchItemTable(nil, self:generateItemTable())
            end
            UIManager:show(cloud_storage)
        end
    })
    return item_table
end

function SyncService.getReadablePath(server)
    local url = util.stringStartsWith(server.url, "/") and server.url:sub(2) or server.url
    url = util.urlDecode(url) or url
    url = util.stringEndsWith(url, "/") and url or url .. "/"
    if server.type == "dropbox" then
        url = "/" .. url
    elseif server.type == "webdav" then
        url = (server.address:sub(-1) == "/" and server.address or server.address .. "/") .. url
    end
    if url:sub(-2) == "//" then url = url:sub(1, -2) end
    return url
end

function SyncService.removeLastSyncDB(path)
    os.remove(path .. ".sync")
end

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
function SyncService.sync(server, file_path, sync_cb, is_silent)
    if server.type == "dropbox" then
        if NetworkMgr:willRerunWhenOnline(function() SyncService.sync(server, file_path, sync_cb, is_silent) end) then
            return
        end
    else
        -- NOTE: Align behavior with CloudStorage:openCloudServer, where only Dropbox requires isOnline
        if NetworkMgr:willRerunWhenConnected(function() SyncService.sync(server, file_path, sync_cb, is_silent) end) then
            return
        end
    end

    local file_name = ffiutil.basename(file_path)
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
    if server.type ~= "dropbox" and server.type ~= "webdav" then
        show_msg(_("Wrong server type."))
        return
    end
    local code_response = 412 -- If-Match header failed
    local etag
    local api = server.type == "dropbox" and require("apps/cloudstorage/dropboxapi") or require("apps/cloudstorage/webdavapi")
    local token = server.password
    if server.type == "dropbox" and not (server.address == nil or server.address == "") then
        token = api:getAccessToken(server.password, server.address)
    end
    while code_response == 412 do
        os.remove(income_file_path)
        if server.type == "dropbox" then
            local url_base = server.url:sub(-1) == "/" and server.url or server.url.."/"
            code_response, etag = api:downloadFile(url_base..file_name, token, income_file_path)
        elseif server.type == "webdav" then
            local path = api:getJoinedPath(server.address, server.url)
            path = api:getJoinedPath(path, file_name)
            code_response, etag = api:downloadFile(path, server.username, server.password, income_file_path)
        end
        if code_response ~= 200 and code_response ~= 404
           and not (server.type == "dropbox" and code_response == 409) then
            show_msg()
            return
        end
        local ok, cb_return = pcall(sync_cb, file_path, cached_file_path, income_file_path)
        if not ok or not cb_return then
            show_msg()
            if not ok then require("logger").err("sync service callback failed:", cb_return) end
            return
        end
        if server.type == "dropbox" then
            local url_base = server.url == "/" and "" or server.url
            code_response = api:uploadFile(url_base, token, file_path, etag, true)
        elseif server.type == "webdav" then
            local path = api:getJoinedPath(server.address, server.url)
            path = api:getJoinedPath(path, file_name)
            code_response = api:uploadFile(path, server.username, server.password, file_path, etag)
        end
    end
    os.remove(income_file_path)
    if type(code_response) == "number" and code_response >= 200 and code_response < 300 then
        os.remove(cached_file_path)
        ffiutil.copyFile(file_path, cached_file_path)
        UIManager:show(Notification:new{
            text = _("Successfully synchronized."),
            timeout = 2,
        })
    else
        show_msg()
    end
end


return SyncService
