--[[--
@module koplugin.wallabag
]]

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("frontend/luasettings")
local Math = require("optmath")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local http = require("socket.http")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen

-- constants
local article_id_prefix = "[w-id_"
local article_id_postfix = "] "
local failed, skipped, downloaded = 1, 2, 3

local Wallabag = WidgetContainer:new{
    name = "wallabag",
}

function Wallabag:onDispatcherRegisterActions()
    Dispatcher:registerAction("wallabag_download", { category="none", event="SynchronizeWallabag", title=_("Wallabag retrieval"), device=true,})
end

function Wallabag:init()
    self.token_expiry = 0
    -- default values so that user doesn't have to explicitely set them
    self.is_delete_finished = true
    self.is_delete_read = false
    self.is_auto_delete = false
    self.is_sync_remote_delete = false
    self.is_archiving_deleted = false
    self.filter_tag = ""
    self.ignore_tags = ""
    self.articles_per_sync = 30

    self:onDispatcherRegisterActions()
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
    if self.wb_settings.data.wallabag.is_archiving_deleted ~= nil then
        self.is_archiving_deleted = self.wb_settings.data.wallabag.is_archiving_deleted
    end
    if self.wb_settings.data.wallabag.filter_tag then
        self.filter_tag = self.wb_settings.data.wallabag.filter_tag
    end
    if self.wb_settings.data.wallabag.ignore_tags then
        self.ignore_tags = self.wb_settings.data.wallabag.ignore_tags
    end
    if self.wb_settings.data.wallabag.articles_per_sync ~= nil then
        self.articles_per_sync = self.wb_settings.data.wallabag.articles_per_sync
    end
    self.remove_finished_from_history = self.wb_settings.data.wallabag.remove_finished_from_history or false
    self.download_queue = self.wb_settings.data.wallabag.download_queue or {}

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
                    local connect_callback = function()
                        local num_deleted = self:processLocalFiles("manual")
                        UIManager:show(InfoMessage:new{
                            text = T(_("Articles processed.\nDeleted: %1"), num_deleted)
                        })
                        self:refreshCurrentDirIfNeeded()
                    end
                    NetworkMgr:runWhenOnline(connect_callback)
                end,
                enabled_func = function()
                    return self.is_delete_finished or self.is_delete_read
                end,
            },
            {
                text = _("Go to download folder"),
                callback = function()
                    if self.ui.document then
                        self.ui:onClose()
                    end
                    if FileManager.instance then
                        FileManager.instance:reinit(self.directory)
                    else
                        FileManager:showFiles(self.directory)
                    end
                end,
            },
            {
                text = _("Settings"),
                callback_func = function()
                    return nil
                end,
                separator = true,
                sub_item_table = {
                    {
                        text = _("Configure Wallabag server"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                    {
                        text = _("Configure Wallabag client"),
                        keep_menu_open = true,
                        callback = function()
                            self:editClientSettings()
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
                            return T(_("Set download directory (%1)"), BD.dirpath(path))
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setDownloadDirectory(touchmenu_instance)
                        end,
                        separator = true,
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
                        text_func = function()
                            if not self.ignore_tags or self.ignore_tags == "" then
                                return _("Ignore tags")
                            end
                            return T(_("Ignore tags (%1)"), self.ignore_tags)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setIgnoreTags(touchmenu_instance)
                        end,
                        separator = true,
                    },
                    {
                        text = _("Article deletion"),
                        separator = true,
                        sub_item_table = {
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
                                separator = true,
                            },
                            {
                                text = _("Mark as read instead of deleting"),
                                checked_func = function() return self.is_archiving_deleted end,
                                callback = function()
                                    self.is_archiving_deleted = not self.is_archiving_deleted
                                    self:saveSettings()
                                end,
                                separator = true,
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
                        },
                    },
                    {
                        text = _("Remove finished articles from history"),
                        keep_menu_open = true,
                        checked_func = function()
                            return self.remove_finished_from_history or false
                        end,
                        callback = function()
                            self.remove_finished_from_history = not self.remove_finished_from_history
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Remove 100% read articles from history"),
                        keep_menu_open = true,
                        checked_func = function()
                            return self.remove_read_from_history or false
                        end,
                        callback = function()
                            self.remove_read_from_history = not self.remove_read_from_history
                            self:saveSettings()
                        end,
                        separator = true,
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

Downloads to directory: %1]]), BD.dirpath(filemanagerutil.abbreviate(self.directory)))
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

    local server_empty = isempty(self.server_url) or isempty(self.username) or isempty(self.password) or isempty(self.client_id) or isempty(self.client_secret)
    local directory_empty = isempty(self.directory)
    if server_empty or directory_empty then
        UIManager:show(MultiConfirmBox:new{
            text = _("Please configure the server settings and set a download folder."),
            choice1_text_func = function()
                if server_empty then
                    return _("Server (★)")
                else
                    return _("Server")
                end
            end,
            choice1_callback = function() self:editServerSettings() end,
            choice2_text_func = function()
                if directory_empty then
                    return _("Folder (★)")
                else
                    return _("Folder")
                end
            end,
            choice2_callback = function() self:setDownloadDirectory() end,
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
    if string.sub(self.directory, -1) ~= "/" then
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
    local result = self:callAPI("POST", login_url, headers, bodyJSON, "")

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

--- Get a JSON formatted list of articles from the server.
-- The list should have self.article_per_sync item, or less if an error occured.
-- If filter_tag is set, only articles containing this tag are queried.
-- If ignore_tags is defined, articles containing either of the tags are skipped.
function Wallabag:getArticleList()
    local filtering = ""
    if self.filter_tag ~= "" then
        filtering = "&tags=" .. self.filter_tag
    end

    local article_list = {}
    local page = 1
    -- query the server for articles until we hit our target number
    while #article_list < self.articles_per_sync do
        -- get the JSON containing the article list
        local articles_url = "/api/entries.json?archive=0"
                          .. "&page=" .. page
                          .. "&perPage=" .. self.articles_per_sync
                          .. filtering
        local articles_json = self:callAPI("GET", articles_url, nil, "", "", true)

        if not articles_json then
            -- we may have hit the last page, there are no more articles
            logger.dbg("Wallabag: couldn't get page #", page)
            break -- exit while loop
        end

        -- We're only interested in the actual articles in the JSON
        -- build an array of those so it's easier to manipulate later
        local new_article_list = {}
        for _, article in ipairs(articles_json._embedded.items) do
            table.insert(new_article_list, article)
        end

        -- Apply the filters
        new_article_list = self:filterIgnoredTags(new_article_list)

        -- Append the filtered list to the final article list
        for i, article in ipairs(new_article_list) do
            if #article_list == self.articles_per_sync then
                logger.dbg("Wallabag: hit the article target", self.articles_per_sync)
                break
            end
            table.insert(article_list, article)
        end

        page = page + 1
    end

    return article_list
end

--- Remove all the articles from the list containing one of the ignored tags.
-- article_list: array containing a json formatted list of articles
-- returns: same array, but without any articles that contain an ignored tag.
function Wallabag:filterIgnoredTags(article_list)
    -- decode all tags to ignore
    local ignoring = {}
    if self.ignore_tags ~= "" then
        for tag in util.gsplit(self.ignore_tags, "[,]+", false) do
            ignoring[tag] = true
        end
    end

    -- rebuild a list without the ignored articles
    local filtered_list = {}
    for _, article in ipairs(article_list) do
        local skip_article = false
        for _, tag in ipairs(article.tags) do
            if ignoring[tag.label] then
                skip_article = true
                logger.dbg("Wallabag: ignoring tag", tag.label, "in article",
                           article.id, ":", article.title)
                break -- no need to look for other tags
            end
        end
        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    return filtered_list
end

--- Download Wallabag article.
-- @string article
-- @treturn int 1 failed, 2 skipped, 3 downloaded
function Wallabag:download(article)
    local skip_article = false
    local title = util.getSafeFilename(article.title, self.directory, 230, 0)
    local file_ext = ".epub"
    local item_url = "/api/entries/" .. article.id .. "/export.epub"

    -- If the article links to a supported file, we will download it directly.
    -- All webpages are HTML. Ignore them since we want the Wallabag EPUB instead!
    if article.mimetype ~= "text/html" then
        if DocumentRegistry:hasProvider(nil, article.mimetype) then
            file_ext = "."..DocumentRegistry:mimeToExt(article.mimetype)
            item_url = article.url
        -- A function represents `null` in our JSON.decode, because `nil` would just disappear.
        -- In that case, fall back to the file extension.
        elseif type(article.mimetype) == "function" and DocumentRegistry:hasProvider(article.url) then
            file_ext = ""
            item_url = article.url
        end
    end

    local local_path = self.directory .. article_id_prefix .. article.id .. article_id_postfix .. title .. file_ext
    logger.dbg("Wallabag: DOWNLOAD: id: ", article.id)
    logger.dbg("Wallabag: DOWNLOAD: title: ", article.title)
    logger.dbg("Wallabag: DOWNLOAD: filename: ", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- File already exists, skip it. Preferably only skip if the date of local file is newer than server's.
        -- newsdownloader.koplugin has a date parser but it is available only if the plugin is activated.
        --- @todo find a better solution
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
        if self:callAPI("GET", item_url, nil, "", local_path) then
            return downloaded
        else
            return failed
        end
    end
    return skipped
end

-- method: (mandatory) GET, POST, DELETE, PATCH, etc...
-- apiurl: (mandatory) API call excluding the server path, or full URL to a file
-- headers: defaults to auth if given nil value, provide all headers necessary if in use
-- body: empty string if not needed
-- filepath: downloads the file if provided, returns JSON otherwise
---- @todo separate call to internal API from the download on external server
function Wallabag:callAPI(method, apiurl, headers, body, filepath, quiet)
    local sink = {}
    local request = {}

    -- Is it an API call, or a regular file direct download?
    if apiurl:sub(1, 1) == "/" then
        -- API call to our server, has the form "/random/api/call"
        request.url = self.server_url .. apiurl
        if headers == nil then
            headers = {
                ["Authorization"] = "Bearer " .. self.access_token,
            }
        end
    else
        -- regular url link to a foreign server
        local file_url = apiurl
        request.url = file_url
        if headers == nil then
            -- no need for a token here
            headers = {}
        end
    end

    request.method = method
    if filepath ~= "" then
        request.sink = ltn12.sink.file(io.open(filepath, "w"))
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    else
        request.sink = ltn12.sink.table(sink)
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    end
    request.headers = headers
    if body ~= "" then
        request.source = ltn12.source.string(body)
    end
    logger.dbg("Wallabag: URL     ", request.url)
    logger.dbg("Wallabag: method  ", method)

    local code, resp_headers = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
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
        elseif not quiet then
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
    if self.download_queue and next(self.download_queue) ~= nil then
        info = InfoMessage:new{ text = _("Adding articles from queue…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        for _, articleUrl in ipairs(self.download_queue) do
            self:addArticle(articleUrl)
        end
        self.download_queue = {}
        self:saveSettings()
        UIManager:close(info)
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
            logger.dbg("Wallabag: number of articles: ", #articles)

            info = InfoMessage:new{ text = _("Downloading articles…") }
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)
            for _, article in ipairs(articles) do
                logger.dbg("Wallabag: processing article ID: ", article.id)
                remote_article_ids[ tostring(article.id) ] = true
                local res = self:download(article)
                if res == downloaded then
                    downloaded_count = downloaded_count + 1
                elseif res == failed then
                    failed_count = failed_count + 1
                end
            end
            -- synchronize remote deletions
            deleted_count = deleted_count + self:processRemoteDeletes(remote_article_ids)

            local msg
            if failed_count ~= 0 then
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2\nFailed: %3")
                info = InfoMessage:new{ text = T(msg, downloaded_count, deleted_count, failed_count) }
            else
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2")
                info = InfoMessage:new{ text = T(msg, downloaded_count, deleted_count) }
            end
            UIManager:show(info)
        end -- articles
    end -- access_token
end

function Wallabag:processRemoteDeletes(remote_article_ids)
    if not self.is_sync_remote_delete then
        logger.dbg("Wallabag: Processing of remote file deletions disabled.")
        return 0
    end
    logger.dbg("Wallabag: articles IDs from server: ", remote_article_ids)

    local info = InfoMessage:new{ text = _("Synchronizing remote deletions…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)
    local deleted_count = 0
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = self.directory .. "/" .. entry
            local id = self:getArticleID(entry_path)
            if not remote_article_ids[ id ] then
                logger.dbg("Wallabag: Deleting local file (deleted on server): ", entry_path)
                self:deleteLocalArticle(entry_path)
                deleted_count = deleted_count + 1
            end
        end
    end -- for entry
    return deleted_count
end

function Wallabag:processLocalFiles(mode)
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
                            self:removeArticle(entry_path)
                            num_deleted = num_deleted + 1
                        end
                    elseif percent_finished == 1 then -- 100% read
                        if self.is_delete_read then
                            self:removeArticle(entry_path)
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

function Wallabag:removeArticle(path)
    logger.dbg("Wallabag: removing article ", path)
    local id = self:getArticleID(path)
    if id then
        if self.is_archiving_deleted then
            local body = {
                archive = 1
            }
            local bodyJSON = JSON.encode(body)

            local headers = {
                ["Content-type"] = "application/json",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#bodyJSON),
                ["Authorization"] = "Bearer " .. self.access_token,
            }

            self:callAPI("PATCH", "/api/entries/" .. id .. ".json", headers, bodyJSON, "")
        else
            self:callAPI("DELETE", "/api/entries/" .. id .. ".json", nil, "", "")
        end
        self:deleteLocalArticle(path)
    end
end

function Wallabag:deleteLocalArticle(path)
    local entry_mode = lfs.attributes(path, "mode")
    if entry_mode == "file" then
        os.remove(path)
        local sdr_dir = DocSettings:getSidecarDir(path)
        FFIUtil.purgeDir(sdr_dir)
        ReadHistory:fileDeleted(path)
   end
end

function Wallabag:getArticleID(path)
    -- extract the Wallabag ID from the file name
    local offset = self.directory:len() + 2 -- skip / and advance to the next char
    local prefix_len = article_id_prefix:len()
    if path:sub(offset , offset + prefix_len - 1) ~= article_id_prefix then
        logger.warn("Wallabag: getArticleID: no match! ", path:sub(offset , offset + prefix_len - 1))
        return
    end
    local endpos = path:find(article_id_postfix, offset + prefix_len)
    if endpos == nil then
        logger.warn("Wallabag: getArticleID: no match! ")
        return
    end
    local id = path:sub(offset + prefix_len, endpos - 1)
    return id
end

function Wallabag:refreshCurrentDirIfNeeded()
    if FileManager.instance then
        FileManager.instance:onRefresh()
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

function Wallabag:setIgnoreTags(touchmenu_instance)
   self.ignore_tags_dialog = InputDialog:new {
        title =  _("Tags to ignore"),
        description = _("Enter a comma-separated list of tags to ignore."),
        input = self.ignore_tags,
        input_type = "string",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.ignore_tags_dialog)
                    end,
                },
                {
                    text = _("Set tags"),
                    is_enter_default = true,
                    callback = function()
                        self.ignore_tags = self.ignore_tags_dialog:getInputText()
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.ignore_tags_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.ignore_tags_dialog)
    self.ignore_tags_dialog:onShowKeyboard()
end

function Wallabag:editServerSettings()
    local text_info = T(_([[
Enter the details of your Wallabag server and account.

Client ID and client secret are long strings so you might prefer to save the empty settings and edit the config file directly in your installation directory:
%1/wallabag.lua

Restart KOReader after editing the config file.]]), BD.dirpath(DataStorage:getSettingsDir()))

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
                        self.server_url    = myfields[1]
                        self.client_id     = myfields[2]
                        self.client_secret = myfields[3]
                        self.username      = myfields[4]
                        self.password      = myfields[5]
                        self:saveSettings()
                        self.settings_dialog:onClose()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
        input_type = "string",
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Wallabag:editClientSettings()
    self.client_settings_dialog = MultiInputDialog:new {
        title = _("Wallabag client settings"),
        fields = {
            {
                text = self.articles_per_sync,
                description = _("Number of articles"),
                input_type = "number",
                hint = _("Number of articles to download per sync")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.client_settings_dialog:onClose()
                        UIManager:close(self.client_settings_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = MultiInputDialog:getFields()
                        self.articles_per_sync = math.max(1, tonumber(myfields[1]) or self.articles_per_sync)
                        self:saveSettings(myfields)
                        self.client_settings_dialog:onClose()
                        UIManager:close(self.client_settings_dialog)
                    end
                },
            },
        },
        width = math.floor(Screen:getWidth() * 0.95),
        height = math.floor(Screen:getHeight() * 0.2),
        input_type = "string",
    }
    UIManager:show(self.client_settings_dialog)
    self.client_settings_dialog:onShowKeyboard()
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

function Wallabag:saveSettings()
    local tempsettings = {
        server_url            = self.server_url,
        client_id             = self.client_id,
        client_secret         = self.client_secret,
        username              = self.username,
        password              = self.password,
        directory             = self.directory,
        filter_tag            = self.filter_tag,
        ignore_tags           = self.ignore_tags,
        is_delete_finished    = self.is_delete_finished,
        is_delete_read        = self.is_delete_read,
        is_archiving_deleted  = self.is_archiving_deleted,
        is_auto_delete        = self.is_auto_delete,
        is_sync_remote_delete = self.is_sync_remote_delete,
        articles_per_sync     = self.articles_per_sync,
        remove_finished_from_history = self.remove_finished_from_history,
        remove_read_from_history = self.remove_read_from_history,
        download_queue        = self.download_queue,
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
        self:addToDownloadQueue(article_url)
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to download queue:\n%1"), BD.url(article_url)),
            timeout = 1,
         })
        return
    end

    local wallabag_result = self:addArticle(article_url)
    if wallabag_result then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to Wallabag:\n%1"), BD.url(article_url)),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Error adding link to Wallabag:\n%1"), BD.url(article_url)),
        })
    end

    -- stop propagation
    return true
end

function Wallabag:onSynchronizeWallabag()
    local connect_callback = function()
        self:synchronize()
        self:refreshCurrentDirIfNeeded()
    end
    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end

function Wallabag:getLastPercent()
    if self.ui.document.info.has_pages then
        return Math.roundPercent(self.ui.paging:getLastPercent())
    else
        return Math.roundPercent(self.ui.rolling:getLastPercent())
    end
end

function Wallabag:addToDownloadQueue(article_url)
    table.insert(self.download_queue, article_url)
    self:saveSettings()
end

function Wallabag:onCloseDocument()
    if self.remove_finished_from_history or self.remove_read_from_history then
        local document_full_path = self.ui.document.file
        local is_finished
        if self.ui.status.settings.data.summary and self.ui.status.settings.data.summary.status then
            local status = self.ui.status.settings.data.summary.status
            is_finished = (status == "complete" or status == "abandoned")
        end
        local is_read = self:getLastPercent() == 1

        if document_full_path
           and self.directory
           and ( (self.remove_finished_from_history and is_finished) or (self.remove_read_from_history and is_read) )
           and self.directory == string.sub(document_full_path, 1, string.len(self.directory)) then
            ReadHistory:removeItemByPath(document_full_path)
            self.ui:setLastDirForFileBrowser(self.directory)
        end
    end
end

return Wallabag
