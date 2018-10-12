local DocSettings = require("frontend/docsettings")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local logger = require("logger")
local ltn12 = require('ltn12')
local mime = require('mime')
local http = require('socket.http')
local https = require('ssl.https')
local socket = require('socket')
local url = require('socket.url')
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local JSON = require("json")
local filemanagerutil = require("apps/filemanager/filemanagerutil")

local Wallabag = WidgetContainer:new{
    name = "wallabag",
}

function Wallabag:init()
    self.token_expiry = 0 -- default until first login
    self.ui.menu:registerToMainMenu(self)
    self.wb_settings = self.readSettings()
    self.server_url = self.wb_settings.data.wallabag.server_url
    self.client_id = self.wb_settings.data.wallabag.client_id
    self.client_secret = self.wb_settings.data.wallabag.client_secret
    self.username = self.wb_settings.data.wallabag.username
    self.password = self.wb_settings.data.wallabag.password
    self.directory = self.wb_settings.data.wallabag.directory
    self.tags = ""
    self.is_delete_finished = true
    self.is_delete_read = true
    self.is_archive_finished = false
    self.is_archive_read = false
    self.is_auto_delete = self.wb_settings.data.wallabag.is_auto_delete
    --logger.dbg('[YM] readSettings url: ', self.server_url)
end

function Wallabag:addToMainMenu(menu_items)
    menu_items.wallabag = {
        text = _("Wallabag sync"),
        sub_item_table = {
            {
                text = _("Retrieve new articles from server"),
                callback = function()
                    if not NetworkMgr:isOnline() then
                        NetworkMgr:promptWifiOn()
                        return
                    end
                    self:synchronise()
                    --self:refreshCurrentDirIfNeeded()
                end,
            },
            {
                -- TODO: overrride the settings !
                text = _("Delete/Archive finished articles remotely"),
                callback = function()
                    if not NetworkMgr:isOnline() then
                        NetworkMgr:promptWifiOn()
                        return
                    end
                    local num_deleted, num_archived = self:processLocalFiles( "manual1" )
                    UIManager:show(InfoMessage:new{
                        text = T(_('Articles processed.\nDeleted: %1\nArchived: %2'), num_deleted, num_archived)
                    })
                    --self:refreshCurrentDirIfNeeded()
                end,
            },
            -- TODO: replace with a full settings screen
            {   
                text = _("Always delete finished articles"),
                checked_func = function() return self.is_auto_delete end,
                callback = function()
                    self.is_auto_delete = not self.is_auto_delete
                    self:saveSettings()
                end,
            },
            {
                text = _("Server Settings"),
                keep_menu_open = true,
                callback = function()
                    self:editServerSettings()
                end,
            },
            -- TODO: missing local settings screen
            --{
            --    text = _("Local Settings"),
            --    keep_menu_open = true,
            --    callback = function()
            --        self:editLocalSettings()
            --    end,
            --},
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_('Wallabag is an open source Read-it-later service. This plugin synchronises with a Wallabag server.\n\nMore details: https://wallabag.org\n\nDownloads to local folder: %1'), download_dir_path)
                    })
                end,
            },
        },
    }
end

function Wallabag:getBearerToken()
    local now = os.time()
    if self.token_expiry - now > 300 then
        -- token still valid for a while, no need to renew
        return true
    end
    
    -- Check if the configuration is complete
    local function isempty(s)
        return s == nil or s == ''
    end

    if isempty(self.server_url) or isempty(self.username) or isempty(self.password)  or isempty(self.client_id) or isempty(self.client_secret) or isempty(self.directory) then
        UIManager:show(InfoMessage:new{
            text = _('Please configure the server and local settings.')
        })
        return false
    end

    -- Check if the download directory is valid
    local dir_mode = lfs.attributes(self.directory, "mode")
    logger.dbg("mode:", dir_mode)
    if dir_mode ~= "directory" then
         UIManager:show(InfoMessage:new{
            text = _('The download directory is not valid.\nPlease configure it in settings.')
        })
        return false
    end
 
    local login_url = "/oauth/v2/token"
    local auth = string.format("%s:%s", self.username, self.password)
    local body = "{ \"grant_type\": \"password\", \"client_id\": \"" .. self.client_id .. "\", \"client_secret\": \"" .. self.client_secret .. "\", \"username\": \"" .. self.username .. "\", \"password\": \"" .. self.password .. "\"}"
    local headers = { 
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#body),
        }
    local result = self:callAPI( 'POST', login_url, headers, body, "" )

    if result then
        self.access_token = result.access_token
        self.token_expiry = now + result.expires_in
        logger.dbg("token:", self.access_token)
        return true
    else
        UIManager:show(InfoMessage:new{
            text = _("Could not login to Wallabag server."), })
        return false
    end
end

function Wallabag:getArticleList()
    local articles_url = "/api/entries.json?archive=0&tags=" .. self.tags
    logger.dbg("articles url: ", articles_url)
    return self:callAPI( 'GET', articles_url, nil, "", "" )
end

function Wallabag:download(article)
    local skip_article = false
    local item_url = "/api/entries/" .. article.id .. "/export.epub"
    local parsed = url.parse(item_url)
    title = util.replaceSlashChar(title)
    local local_path = self.directory .. "/[w-id:" .. article.id .. "] " .. article.title:sub(1,30) .. ".epub"
    logger.dbg("DOWNLOAD: id: ", article.id)
    logger.dbg("DOWNLOAD: title: ", article.title)
    logger.dbg("DOWNLOAD: filename: ", local_path)
    
    if lfs.attributes(local_path) then
        -- file already exists, skip
        -- TODO: only skip if the date of local file is newer than server
        skip_article = true
        logger.dbg("**** skipping file: ", local_path)
    end
    
    if skip_article == false then
        return self:callAPI( 'GET', item_url, nil, "", local_path)
    end
end

-- method: (mandatory) GET, POST, DELETE, PATCH, etc...
-- apiurl: (mandatory) excluding the server path
-- headers: defaults to auth if given nil value, provide all headers necessary if in use
-- body: empty string if not needed
-- filepath: downloads the file if provided, returns JSON otherwise
function Wallabag:callAPI( method, apiurl, headers, body, filepath )
    local request, sink = {}, {}
    local parsed = url.parse(apiurl)
    request['url'] = self.server_url .. apiurl
    request['method'] = method
    if filepath ~= "" then
        request['sink'] = ltn12.sink.file(io.open(filepath, "w"))
    else
        request['sink'] = ltn12.sink.table(sink)
    end
    if headers == nil then
        headers = { ["Authorization"] = "Bearer " .. self.access_token, }
    end
    request['headers'] = headers
    if body ~= "" then
        request['source'] = ltn12.source.string(body)
    end
    logger.dbg("URL ", self.server_url .. apiurl)
    logger.dbg("method ", method)
    logger.dbg("headers ", headers)

    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    local code, headers = socket.skip(1, httpRequest(request))
    -- raise error message when network is unavailable
    if headers == nil then
        error(code)
    end
    if code == 200 then
        if filepath ~= "" then
            logger.dbg("file downloaded to", local_path)
            return true
        else
            local content = table.concat(sink)
            if content ~= "" and string.sub(content, 1,1) == "{" then
                local ok, result = pcall(JSON.decode, content)
                if ok and result then
                    logger.dbg("result ", result)
                    return result
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Server response is not valid."), })
                end
            else
                UIManager:show(InfoMessage:new{
                    text = _("Server response is not valid."), })
            end        
        end
    else
        if filepath ~= "" then
            msg = _("Could not download document.")
        else
            msg = _("Communication with server failed.")
        end
        UIManager:show(InfoMessage:new{
            text = msg, })
        return false
    end
end

function Wallabag:synchronise()
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)
    
    if self:getBearerToken() == false then
        return false
    end

    local deleted_count, archived_count = self:processLocalFiles()
    
    local info = InfoMessage:new{ text = _("Getting article list…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    local downloaded_count = 0
    if self.access_token ~= "" then
        articles = self:getArticleList()
        logger.dbg("number of articles: ", articles.total)
        --logger.dbg("articles: ", articles)

        local info = InfoMessage:new{ text = _("Downloading articles…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        for _, article in ipairs(articles._embedded.items) do
            logger.dbg("article: ", article.id)
            if self:download(article) then
                downloaded_count = downloaded_count + 1
            end
        end               
    end

    local msg
    if deleted_count ~= 0 or archived_count ~= 0 then
        msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2\nArchived: %3")
        info = InfoMessage:new{ text = T( msg, downloaded_count, deleted_count, archived_count ) }
    else
        msg = _("Processing finished.\n\nArticles downloaded: %1")
        info = InfoMessage:new{ text = T( msg, downloaded_count ) }
    end
    UIManager:show(info)
end

function Wallabag:processLocalFiles( mode )
    if mode then
        if self.is_auto_delete == false and mode ~= "manual" then
            logger.dbg("Automatic processing of local files disabled.")
            return 0, 0
        end
    end

    if self:getBearerToken() == false then
        return 0, 0
    end

    local num_deleted = 0
    local num_archived = 0
    if self.is_delete_finished or self.is_delete_read or self.is_archive_finished or self.is_archive_read then
        local info = InfoMessage:new{ text = _("Processing local files…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        logger.dbg("[YM] deleteOnServer: Removing read articles from :", self.directory)
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = self.directory .. "/" .. entry
                logger.dbg("[YM] delete? ", entry_path)
                if DocSettings:hasSidecarFile(entry_path) then
                    local docinfo = DocSettings:open(entry_path)
                    if docinfo.data.summary and docinfo.data.summary.status then
                        status = docinfo.data.summary.status
                    end
                    percent_finished = docinfo.data.percent_finished
                    logger.dbg("[YM] status ", status )
                    logger.dbg("[YM] percent ", percent_finished )

                    if status == "complete" or status == "abandoned" then
                        if self.is_delete_finished then
                            self:deleteArticle( entry_path )
                            num_deleted = num_deleted + 1
                        elseif self.is_archive_finished then
                            self:archiveArticle( entry_path )
                            num_archived = num_archived + 1
                        end
                    elseif percent_finished == 1 then -- 100% read
                        if self.is_delete_read then
                            self:deleteArticle( entry_path )
                            num_deleted = num_deleted + 1
                        elseif self.is_archive_read then
                            self:archiveArticle( entry_path )
                            num_archived = num_archived + 1
                        end
                    end                    
                end -- has sidecar
            end -- not . and ..
        end -- for entry
    end -- flag checks
    return num_deleted, num_archived
end

function Wallabag:deleteArticle( path )
    logger.dbg("deleting article ", path )
    offset = self.directory:len() + 2 -- skip / and advance to the next char
    if path:sub( offset , offset + 5) ~= "[w-id:" then
        logger.dbg("[YM] NO MATCH ", path:sub( offset , offset + 5) )
        return false
    end
    id = path:sub( offset + 6, path:find( "]", offset + 6 ) - 1 )
    logger.dbg("[YM] id ", id )

    self:callAPI( 'DELETE', "/api/entries/" .. id .. ".json", nil, "", "" )
    self:deleteLocalArticle( path )
end

function Wallabag:archiveArticle( path )
    logger.dbg("archiving article ", path )
    -- extract the Wallabag ID from the file name
    offset = self.directory:len() + 2 -- skip / and advance to the next char
    if path:sub( offset , offset + 5) ~= "[w-id:" then
        logger.dbg("[YM] NO MATCH ", path:sub( offset , offset + 5) )
        return false
    end
    id = path:sub( offset + 6, path:find( "]", offset + 6 ) - 1 )
    logger.dbg("[YM] id ", id )
    
    self:callAPI( 'PATCH', "/api/entries/" .. id .. ".json?archive=1", nil, "", "" )
    -- TODO: enable local delete when archiving works
    --self:deleteLocalArticle( path )
end

function Wallabag:deleteLocalArticle( path )
    local entry_mode = lfs.attributes(path, "mode")
    if entry_mode == "file" then
        os.remove(path)
        local sdr_dir = DocSettings:getSidecarDir( path )
        FFIUtil.purgeDir( sdr_dir )
        filemanagerutil.removeFileFromHistoryIfWanted( path )
   end
end

function Wallabag:refreshCurrentDirIfNeeded()
    -- TODO:
    -- If in the file mananer in the same directory as the download directory
    -- refresh to see the new files or get rid of the deleted ones.
    -- Is it possible ??
end

function Wallabag:editServerSettings()
    local text_info = "Enter the details of your Wallabag server and account.\n"..
        "\nClient ID and client secret are long strings so you might prefer to save the empty "..
        "settings and edit the config file directly:\n"..
        ".adds/koreader/settings/wallabagsettings.lua"..
        "\n\nRestart KOReader after editing the config file."
        
    self.settings_dialog = MultiInputDialog:new {
        title = _("Wallabag settings"),
        fields = {
            {
                text = self.server_url,
                --description = T(_("Server URL:")),
                input_type = "string",
                hint = _("Server URL")
            },
            {
                text = self.client_id,
                --description = T(_("Client ID and secret")),
                input_type = "string",
                hint = _("Client ID")
            },
            {
                text = self.client_secret,
                input_type = "string",
                hint = _("Client secret")
            },
            {
                text = self.username,
                --description = T(_("User name and password")),
                input_type = "string",
                hint = _("Username")
            },
            {
                text = self.password,
                input_type = "string",
                hint = _("Password")
            },
            {
                text = self.directory,
                --description = T(_("Download directory")),
                input_type = "string",
                hint = _("Download directory")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = MultiInputDialog:getFields()
                        local info_text = T(_"val1: %1", myfields[1])
                        logger.dbg( info_text )

                        self:saveSettings(myfields, "server")
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
        width = Screen:getWidth() * 0.95,
        height = Screen:getHeight() * 0.2,
        input_type = "string",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Wallabag:editLocalSettings()
    -- TODO
end

function Wallabag:saveSettings(fields, type)
    if fields then
        if type == "server" then
            self.server_url    = fields[1]
            self.client_id     = fields[2]
            self.client_secret = fields[3]
            self.username      = fields[4]
            self.password      = fields[5]
            self.directory     = fields[6]
        elseif type == "local" then
            -- TODO
        end
    end

    local tempsettings = {
        server_url     = self.server_url,
        client_id      = self.client_id,
        client_secret  = self.client_secret,
        username       = self.username,
        password       = self.password,
        directory      = self.directory,
        is_auto_delete = self.is_auto_delete,
    }
    self.wb_settings:saveSetting("wallabag", tempsettings)
    self.wb_settings:flush()

end

function Wallabag:readSettings()
    local wb_settings = LuaSettings:open(DataStorage:getSettingsDir().."/wallabag.lua")
    return wb_settings
end

function Wallabag:saveWBSettings(setting)
    if not self.wb_settings then self:readSettings() end
    self.wb_settings:saveSetting("wallabag", setting)
    self.wb_settings:flush()
end

return Wallabag
