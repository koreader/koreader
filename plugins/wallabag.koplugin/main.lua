local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("frontend/luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen

-- constants
local article_id_preffix = "[w-id_"
local article_id_postfix = "] "
local failed, skipped, downloaded = 1, 2, 3

local Wallabag = WidgetContainer:new{
    name = "wallabag",
}

function Wallabag:init()
    self.token_expiry = 0
    -- default values so that user doesn't have to explicitely set them
    self.is_delete_finished = true
    self.is_delete_read = false
    self.is_auto_delete = false
    self.is_sync_remote_delete = false
    self.filter_tag = ""

    self.ui.menu:registerToMainMenu(self)
    self.wb_settings = self.readSettings()
    self.server_url = self.wb_settings.data.wallabag.server_url
    self.client_id = self.wb_settings.data.wallabag.client_id
    self.client_secret = self.wb_settings.data.wallabag.client_secret
    self.username = self.wb_settings.data.wallabag.username
    self.password = self.wb_settings.data.wallabag.password
    self.directory = self.wb_settings.data.wallabag.directory
    if self.wb_settings.data.wallabag.is_delete_finished ~= nil then
        self.is_delete_finished = self.wb_settings.data.wallabag.is_delete_finished
    end
    if self.wb_settings.data.wallabag.is_delete_read ~= nil then
        self.is_delete_read = self.wb_settings.data.wallabag.is_delete_read
    end
    if self.wb_settings.data.wallabag.is_auto_delete ~= nil then
        self.is_auto_delete = self.wb_settings.data.wallabag.is_auto_delete
    end
    if self.wb_settings.data.wallabag.is_sync_remote_delete ~= nil then
        self.is_sync_remote_delete = self.wb_settings.data.wallabag.is_sync_remote_delete
    end
    if self.wb_settings.data.wallabag.filter_tag then
        self.filter_tag = self.wb_settings.data.wallabag.filter_tag
    end

    -- workaround for dateparser only available if newsdownloader is active
    self.is_dateparser_available = false
    self.is_dateparser_checked = false

    -- workaround for dateparser, only once
    -- the parser is in newsdownloader.koplugin, check if it is available
    if not self.is_dateparser_checked then
        local res
        res, self.dateparser = pcall(require, "lib.dateparser")
        if res then self.is_dateparser_available = true end
        self.is_dateparser_checked = true
    end
end

function Wallabag:addToMainMenu(menu_items)
    menu_items.wallabag = {
        text = _("Wallabag"),
        sub_item_table = {
            {
                text = _("Retrieve new articles from server"),
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizeWallabag"))
                end,
            },
            {
                text = _("Delete finished articles remotely"),
                callback = function()
                    if not NetworkMgr:isOnline() then
                        NetworkMgr:promptWifiOn()
                        return
                    end
                    local num_deleted = self:processLocalFiles( "manual" )
                    UIManager:show(InfoMessage:new{
                        text = T(_("Articles processed.\nDeleted: %1"), num_deleted)
                    })
                    self:refreshCurrentDirIfNeeded()
                end,
                enabled_func = function()
                    return self.is_delete_finished or self.is_delete_read
                end,
            },
            {
                text = _("Go to download folder"),
                callback = function()
                    if FileManager.instance then
                        FileManager.instance:reinit( self.directory )
                    else
                        FileManager:showFiles( self.directory )
                    end
                end,
            },
            {
                text = _("Settings"),
                callback_func = function()
                    return nil
                end,
                sub_item_table = {
                    {
                        text = _("Configure Wallabag server"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                    {
                        text_func = function()
                            local path
                            if not self.directory or self.directory == "" then
                                path = _("Not set")
                            else
                                path = filemanagerutil.abbreviate(self.directory)
                            end
                            return T(_("Set download directory (%1)"), path)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setDownloadDirectory(touchmenu_instance)
                        end,
                    },
                    {
                        text_func = function()
                            local filter
                            if not self.filter_tag or self.filter_tag == "" then
                                filter = _("All articles")
                            else
                                filter = self.filter_tag
                            end
                            return T(_("Filter articles by tag (%1)"), filter)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setFilterTag(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Remotely delete finished articles"),
                        checked_func = function() return self.is_delete_finished end,
                        callback = function()
                            self.is_delete_finished = not self.is_delete_finished
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Remotely delete 100% read articles"),
                        checked_func = function() return self.is_delete_read end,
                        callback = function()
                            self.is_delete_read = not self.is_delete_read
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Process deletions when downloading"),
                        checked_func = function() return self.is_auto_delete end,
                        callback = function()
                            self.is_auto_delete = not self.is_auto_delete
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Synchronize remotely deleted files"),
                        checked_func = function() return self.is_sync_remote_delete end,
                        callback = function()
                            self.is_sync_remote_delete = not self.is_sync_remote_delete
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _([[Download directory: use a directory that is exclusively used by the Wallabag plugin. Existing files in this directory risk being deleted.

Articles marked as finished or 100% read can be deleted from the server. Those articles can also be deleted automatically when downloading new articles if the 'Process deletions during download' option is enabled.

The 'Synchronize remotely deleted files' option will remove local files that no longer exist on the server.]])
                            })
                        end,
                    }
                }
            },
            {
                text = _("Info"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[Wallabag is an open source read-it-later service. This plugin synchronizes with a Wallabag server.

More details: https://wallabag.org

Downloads to directory: %1]]), filemanagerutil.abbreviate(self.directory))
                    })
                end,
            },
        },
    }
end

function Wallabag:getBearerToken()

    -- Check if the configuration is complete
    local function isempty(s)
        return s == nil or s == ""
    end

    if isempty(self.server_url) or isempty(self.username) or isempty(self.password)  or isempty(self.client_id) or isempty(self.client_secret) or isempty(self.directory) then
        UIManager:show(InfoMessage:new{
            text = _("Please configure the server and local settings.")
        })
        return false
    end

    -- Check if the download directory is valid
    local dir_mode = lfs.attributes(self.directory, "mode")
    if dir_mode ~= "directory" then
         UIManager:show(InfoMessage:new{
            text = _("The download directory is not valid.\nPlease configure it in the settings.")
        })
        return false
    end
    if string.sub( self.directory, -1 ) ~= "/" then
        self.directory = self.directory .. "/"
    end

    local now = os.time()
    if self.token_expiry - now > 300 then
        -- token still valid for a while, no need to renew
        return true
    end

    local login_url = "/oauth/v2/token"

    local body = {
      grant_type = "password",
      client_id = self.client_id,
      client_secret = self.client_secret,
      username = self.username,
      password = self.password
    }

    local bodyJSON = JSON.encode(body)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#bodyJSON),
        }
    local result = self:callAPI( "POST", login_url, headers, bodyJSON, "" )

    if result then
        self.access_token = result.access_token
        self.token_expiry = now + result.expires_in
        return true
    else
        UIManager:show(InfoMessage:new{
            text = _("Could not login to Wallabag server."), })
        return false
    end
end

function Wallabag:getArticleList()
    local filtering = ""
    if self.filter_tag ~= "" then
        filtering = "&tags=" .. self.filter_tag
    end
    local articles_url = "/api/entries.json?archive=0" .. filtering
    return self:callAPI( "GET", articles_url, nil, "", "" )
end

function Wallabag:download(article)
    local skip_article = false
    local item_url = "/api/entries/" .. article.id .. "/export.epub"
    local title = util.replaceInvalidChars(article.title)
    local local_path = self.directory .. article_id_preffix .. article.id .. article_id_postfix .. title:sub(1,30) .. ".epub"
    logger.dbg("Wallabag: DOWNLOAD: id: ", article.id)
    logger.dbg("Wallabag: DOWNLOAD: title: ", article.title)
    logger.dbg("Wallabag: DOWNLOAD: filename: ", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- File already exists, skip it. Preferably only skip if the date of local file is newer than server's.
        -- newsdownloader.koplugin has a date parser but it is available only if the plugin is activated.
        -- TODO: find a better solution
        if self.is_dateparser_available then
            local server_date = self.dateparser.parse(article.updated_at)
            if server_date < attr.modification then
                skip_article = true
                logger.dbg("Wallabag: skipping file (date checked): ", local_path)
            end
        else
            skip_article = true
            logger.dbg("Wallabag: skipping file: ", local_path)
        end
    end

    if skip_article == false then
        if self:callAPI( "GET", item_url, nil, "", local_path) then
            return downloaded
        else
            return failed
        end
    end
    return skipped
end

-- method: (mandatory) GET, POST, DELETE, PATCH, etc...
-- apiurl: (mandatory) excluding the server path
-- headers: defaults to auth if given nil value, provide all headers necessary if in use
-- body: empty string if not needed
-- filepath: downloads the file if provided, returns JSON otherwise
function Wallabag:callAPI( method, apiurl, headers, body, filepath )
    local request, sink = {}, {}
    local parsed = url.parse(self.server_url)
    request["url"] = self.server_url .. apiurl
    request["method"] = method
    if filepath ~= "" then
        request["sink"] = ltn12.sink.file(io.open(filepath, "w"))
    else
        request["sink"] = ltn12.sink.table(sink)
    end
    if headers == nil then
        headers = { ["Authorization"] = "Bearer " .. self.access_token, }
    end
    request["headers"] = headers
    if body ~= "" then
        request["source"] = ltn12.source.string(body)
    end
    logger.dbg("Wallabag: URL     ", self.server_url .. apiurl)
    logger.dbg("Wallabag: method  ", method)

    http.TIMEOUT, https.TIMEOUT = 10, 10
    local httpRequest = parsed.scheme == "http" and http.request or https.request
    local code, resp_headers = socket.skip(1, httpRequest(request))
    -- raise error message when network is unavailable
    if resp_headers == nil then
        logger.dbg("Wallabag: Server error: ", code)
        return false
    end
    if code == 200 then
        if filepath ~= "" then
            logger.dbg("Wallabag: file downloaded to", filepath)
            return true
        else
            local content = table.concat(sink)
            if content ~= "" and string.sub(content, 1,1) == "{" then
                local ok, result = pcall(JSON.decode, content)
                if ok and result then
                    -- Only enable this log when needed, the output can be large
                    --logger.dbg("Wallabag: result ", result)
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
            local entry_mode = lfs.attributes(filepath, "mode")
            if entry_mode == "file" then
                os.remove(filepath)
                logger.dbg("Wallabag: Removed failed download: ", filepath)
            end
        else
            UIManager:show(InfoMessage:new{
                text = _("Communication with server failed."), })
        end
        return false
    end
end

function Wallabag:synchronize()
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    if self:getBearerToken() == false then
        return false
    end

    local deleted_count = self:processLocalFiles()

    info = InfoMessage:new{ text = _("Getting article list…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    local remote_article_ids = {}
    local downloaded_count = 0
    local failed_count = 0
    if self.access_token ~= "" then
        local articles = self:getArticleList()
        if articles then
            logger.dbg("Wallabag: number of articles: ", articles.total)

            info = InfoMessage:new{ text = _("Downloading articles…") }
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)
            for _, article in ipairs(articles._embedded.items) do
                logger.dbg("Wallabag: processing article ID: ", article.id)
                remote_article_ids[ tostring( article.id ) ] = true
                local res = self:download(article)
                if res == downloaded then
                    downloaded_count = downloaded_count + 1
                elseif res == failed then
                    failed_count = failed_count + 1
                end
            end
            -- synchronize remote deletions
            deleted_count = deleted_count + self:processRemoteDeletes( remote_article_ids )

            local msg
            if failed_count ~= 0 then
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2\nFailed: %3")
                info = InfoMessage:new{ text = T( msg, downloaded_count, deleted_count, failed_count ) }
            else
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2")
                info = InfoMessage:new{ text = T( msg, downloaded_count, deleted_count ) }
            end
            UIManager:show(info)
        end -- articles
    end -- access_token
end

function Wallabag:processRemoteDeletes( remote_article_ids )
    if not self.is_sync_remote_delete then
        logger.dbg("Wallabag: Processing of remote file deletions disabled.")
        return 0
    end
    logger.dbg("Wallabag: articles IDs from server: ", remote_article_ids)

    local info = InfoMessage:new{ text = _("Synchonising remote deletions…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)
    local deleted_count = 0
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = self.directory .. "/" .. entry
            local id = self:getArticleID( entry_path )
            if not remote_article_ids[ id ] then
                logger.dbg("Wallabag: Deleting local file (deleted on server): ", entry_path )
                self:deleteLocalArticle( entry_path )
                deleted_count = deleted_count + 1
            end
        end
    end -- for entry
    return deleted_count
end

function Wallabag:processLocalFiles( mode )
    if mode then
        if self.is_auto_delete == false and mode ~= "manual" then
            logger.dbg("Wallabag: Automatic processing of local files disabled.")
            return 0, 0
        end
    end

    if self:getBearerToken() == false then
        return 0, 0
    end

    local num_deleted = 0
    if self.is_delete_finished or self.is_delete_read then
        local info = InfoMessage:new{ text = _("Processing local files…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = self.directory .. "/" .. entry
                if DocSettings:hasSidecarFile(entry_path) then
                    local docinfo = DocSettings:open(entry_path)
                    local status
                    if docinfo.data.summary and docinfo.data.summary.status then
                        status = docinfo.data.summary.status
                    end
                    local percent_finished = docinfo.data.percent_finished
                    if status == "complete" or status == "abandoned" then
                        if self.is_delete_finished then
                            self:deleteArticle( entry_path )
                            num_deleted = num_deleted + 1
                        end
                    elseif percent_finished == 1 then -- 100% read
                        if self.is_delete_read then
                            self:deleteArticle( entry_path )
                            num_deleted = num_deleted + 1
                        end
                    end
                end -- has sidecar
            end -- not . and ..
        end -- for entry
    end -- flag checks
    return num_deleted
end

function Wallabag:addArticle(article_url)
    logger.dbg("Wallabag: adding article ", article_url)

    if not article_url or self:getBearerToken() == false then
        return false
    end

    local body = {
        url = article_url,
    }

    local body_JSON = JSON.encode(body)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#body_JSON),
        ["Authorization"] = "Bearer " .. self.access_token,
    }

    return self:callAPI("POST", "/api/entries.json", headers, body_JSON, "")
end

function Wallabag:deleteArticle( path )
    logger.dbg("Wallabag: deleting article ", path )
    local id = self:getArticleID( path )
    if id then
        self:callAPI( "DELETE", "/api/entries/" .. id .. ".json", nil, "", "" )
        self:deleteLocalArticle( path )
    end
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

function Wallabag:getArticleID( path )
    -- extract the Wallabag ID from the file name
    local offset = self.directory:len() + 2 -- skip / and advance to the next char
    local preffix_len = article_id_preffix:len()
    if path:sub( offset , offset + preffix_len - 1 ) ~= article_id_preffix then
        logger.warn("Wallabag: getArticleID: no match! ", path:sub( offset , offset + preffix_len - 1 ) )
        return
    end
    local endpos = path:find( article_id_postfix, offset + preffix_len )
    if endpos == nil then
        logger.warn("Wallabag: getArticleID: no match! " )
        return
    end
    local id = path:sub( offset + preffix_len, endpos - 1 )
    return id
end

function Wallabag:refreshCurrentDirIfNeeded()
    if FileManager.instance then
        FileManager.instance:onRefresh( )
    end
end

function Wallabag:setFilterTag(touchmenu_instance)
   self.tag_dialog = InputDialog:new {
        title =  _("Set a single tag to filter articles on"),
        input = self.filter_tag,
        input_type = "string",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.tag_dialog)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        self.filter_tag = self.tag_dialog:getInputText()
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.tag_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.tag_dialog)
    self.tag_dialog:onShowKeyboard()
end

function Wallabag:editServerSettings()
    local text_info = T(_([[
Enter the details of your Wallabag server and account.

Client ID and client secret are long strings so you might prefer to save the empty settings and edit the config file directly in your installation directory:
%1/wallabag.lua

Restart KOReader after editing the config file.]]), DataStorage:getSettingsDir())

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
                --description = T(_("Username and password")),
                input_type = "string",
                hint = _("Username")
            },
            {
                text = self.password,
                input_type = "string",
                text_type = "password",
                hint = _("Password")
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
                        self:saveSettings(myfields)
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

function Wallabag:setDownloadDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
       onConfirm = function(path)
           logger.dbg("Wallabag: set download directory to: ", path)
           self.directory = path
           self:saveSettings()
           touchmenu_instance:updateItems()
       end,
    }:chooseDir()
end

function Wallabag:saveSettings( fields )
    if fields then
        self.server_url    = fields[1]
        self.client_id     = fields[2]
        self.client_secret = fields[3]
        self.username      = fields[4]
        self.password      = fields[5]
    end

    local tempsettings = {
        server_url            = self.server_url,
        client_id             = self.client_id,
        client_secret         = self.client_secret,
        username              = self.username,
        password              = self.password,
        directory             = self.directory,
        filter_tag            = self.filter_tag,
        is_delete_finished    = self.is_delete_finished,
        is_delete_read        = self.is_delete_read,
        is_auto_delete        = self.is_auto_delete,
        is_sync_remote_delete = self.is_sync_remote_delete
    }
    self.wb_settings:saveSetting("wallabag", tempsettings)
    self.wb_settings:flush()

end

function Wallabag:readSettings()
    local wb_settings = LuaSettings:open(DataStorage:getSettingsDir().."/wallabag.lua")
    if not wb_settings.data.wallabag then
        wb_settings.data.wallabag = {}
    end
    return wb_settings
end

function Wallabag:saveWBSettings(setting)
    if not self.wb_settings then self:readSettings() end
    self.wb_settings:saveSetting("wallabag", setting)
    self.wb_settings:flush()
end

function Wallabag:onAddWallabagArticle(article_url)
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
        return
    end

    local wallabag_result = self:addArticle(article_url)
    if wallabag_result then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to Wallabag:\n%1"), article_url),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Error adding link to Wallabag:\n%1"), article_url),
        })
    end

    -- stop propagation
    return true
end

function Wallabag:onSynchronizeWallabag()
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn()
        return
    end
    self:synchronize()
    self:refreshCurrentDirIfNeeded()

    -- stop propagation
    return true
end

return Wallabag
