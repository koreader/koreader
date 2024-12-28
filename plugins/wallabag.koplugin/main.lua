--[[--
This plugin downloads a set number of the newest arcticles in your wallabag "Unread" list. As epubs,
or in their original formats. It can archive or delete articles from wallabag when you finish them
in KOReader. And it will delete or archive them locally when you finish them elsewhere.

@todo Integrate comments from https://github.com/koreader/koreader/pull/12949
@todo Translate the new menu labels? See https://github.com/koreader/koreader-translations
@todo Make sure all menu labels and message texts are wrapped in _() for translation
@todo An option to parse comma-separated reviews as tags, full text as review. Maybe strip tags?

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
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

-- Constants
local article_id_prefix = "[w-id_"
local article_id_postfix = "] "
local failed, skipped, downloaded = 1, 2, 3

local Wallabag = WidgetContainer:extend{
    name = "wallabag",
}

function Wallabag:onDispatcherRegisterActions()
    Dispatcher:registerAction("wallabag_download", {
        category = "none",
        event = "SynchronizeWallabag",
        title = _("wallabag retrieval"),
        general = true,
    })
    Dispatcher:registerAction("wallabag_queue_upload", {
        category = "none",
        event = "UploadWallabagQueue",
        title = _("wallabag queue upload"),
        general = true,
    })
    Dispatcher:registerAction("wallabag_status_upload", {
        category = "none",
        event = "UploadWallabagStatuses",
        title = _("wallabag statuses upload"),
        general = true,
    })
end -- Wallabag:onDispatcherRegisterActions

function Wallabag:init()
    self.token_expiry = 0
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.wb_settings = self:readSettings()

    -- These settings do not have defaults and need to be set by the user
    self.server_url = self.wb_settings.data.wallabag.server_url
    self.client_id = self.wb_settings.data.wallabag.client_id
    self.client_secret = self.wb_settings.data.wallabag.client_secret
    self.username = self.wb_settings.data.wallabag.username
    self.password = self.wb_settings.data.wallabag.password
    self.directory = self.wb_settings.data.wallabag.directory

    -- archive_directory only has a default if directory is set
    self.archive_directory = self.wb_settings.data.wallabag.archive_directory
    if not self.archive_directory or self.archive_directory == "" then
        if self.directory and self.directory ~= "" then
            self.archive_directory = self.directory .. "archive/"
        end
    end

    -- These settings do have defaults
    self.archive_abandoned             = self.wb_settings.data.wallabag.archive_abandoned or false
    self.archive_finished              = self.wb_settings.data.wallabag.archive_finished or true
    self.archive_read                  = self.wb_settings.data.wallabag.archive_read or false
    self.articles_per_sync             = self.wb_settings.data.wallabag.articles_per_sync or 30
    self.auto_archive                  = self.wb_settings.data.wallabag.auto_archive or false
    self.auto_tags                     = self.wb_settings.data.wallabag.auto_tags or ""
    self.delete_instead                = self.wb_settings.data.wallabag.delete_instead or false
    self.download_original_document    = self.wb_settings.data.wallabag.download_original_document or false
    self.filter_tag                    = self.wb_settings.data.wallabag.filter_tag or ""
    self.ignore_tags                   = self.wb_settings.data.wallabag.ignore_tags or ""
    self.remove_abandoned_from_history = self.wb_settings.data.wallabag.remove_abandoned_from_history or false
    self.remove_finished_from_history  = self.wb_settings.data.wallabag.remove_finished_from_history or false
    self.remove_read_from_history      = self.wb_settings.data.wallabag.remove_read_from_history or false
    self.send_review_as_tags           = self.wb_settings.data.wallabag.send_review_as_tags or false
    self.sync_remote_archive           = self.wb_settings.data.wallabag.sync_remote_archive or false
    self.upload_queue                  = self.wb_settings.data.wallabag.upload_queue or {}
    self.use_local_archive             = self.wb_settings.data.wallabag.use_local_archive or false

    -- workaround for dateparser only available if newsdownloader is active
    self.is_dateparser_available       = false
    self.is_dateparser_checked         = false

    -- workaround for dateparser, only once
    -- the parser is in newsdownloader.koplugin, check if it is available
    if not self.is_dateparser_checked then
        local res
        res, self.dateparser = pcall(require, "lib.dateparser")
        if res then self.is_dateparser_available = true end
        self.is_dateparser_checked = true
    end

    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("25_wallabag", function(this, link_url)
            return {
                text = _("Add to wallabag"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddWallabagArticle", link_url))
                end,
            }
        end)
    end
end -- Wallabag:init

--- Add Wallabag to the Tools menu in both the file manager and the reader.
function Wallabag:addToMainMenu(menu_items)
    menu_items.wallabag = {
        text = _("Wallabag"), -- Leave uppercase for a clean menu
        sub_item_table = {
            {
                text_func = function()
                    if self.auto_archive then
                        return _("Synchronize articles with server")
                    else
                        return _("Download new articles from server")
                    end
                end,
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizeWallabag"))
                end,
            },
            {
                text = T(
                    _("Upload queue of locally added articles to server (%1)"),
                    #self.upload_queue
                ),
                callback = function()
                    self.ui:handleEvent(Event:new("UploadWallabagQueue"))
                end,
                enabled_func = function()
                    return #self.upload_queue > 0
                end,
            },
            {
                text = _("Upload article statuses to server"),
                callback = function()
                    self.ui:handleEvent(Event:new("UploadWallabagStatuses"))
                end,
                enabled_func = function()
                    return self.archive_finished or self.archive_read or self.archive_abandoned
                end,
            },
            {
                text = _("Go to download directory"),
                callback = function()
                    self.ui:handleEvent(Event:new("GoToWallabagDirectory"))
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
                        text = _("Configure wallabag server"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                    {
                        text = _("Download settings"),
                        sub_item_table = {
                            {
                                text_func = function()
                                    local path
                                    if not self.directory or self.directory == "" then
                                        path = _("not set")
                                    else
                                        path = filemanagerutil.abbreviate(self.directory)
                                    end
                                    return T(_("Download directory: %1"), BD.dirpath(path))
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setDownloadDirectory(touchmenu_instance)
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Number of articles to download: %1"), self.articles_per_sync)
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setArticlesPerSync(touchmenu_instance)
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Only download articles with tag: %1"), self.filter_tag or "")
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setTagsDialog(
                                        touchmenu_instance,
                                        _("Tag to include"),
                                        _("Enter a single tag to filter articles on"),
                                        self.filter_tag,
                                        function(tag)
                                            self.filter_tag = tag
                                        end
                                    )
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Do not download articles with tags: %1"), self.ignore_tags or "")
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setTagsDialog(
                                        touchmenu_instance,
                                        _("Tags to ignore"),
                                        _("Enter a comma-separated list of tags to ignore"),
                                        self.ignore_tags,
                                        function(tags)
                                            self.ignore_tags = tags
                                        end
                                    )
                                end,
                            },
                            {
                                text = _("Prefer original non-HTML document"),
                                keep_menu_open = true,
                                checked_func = function()
                                    return self.download_original_document or false
                                end,
                                callback = function()
                                    self.download_original_document = not self.download_original_document
                                    self:saveSettings()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Remote mark-as-read settings"),
                        sub_item_table = {
                            {
                                text = _("Mark finished articles as read"),
                                checked_func = function() return self.archive_finished end,
                                callback = function()
                                    self.archive_finished = not self.archive_finished
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Mark 100% read articles as read"),
                                checked_func = function() return self.archive_read end,
                                callback = function()
                                    self.archive_read = not self.archive_read
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Mark articles on hold as read"),
                                checked_func = function() return self.archive_abandoned end,
                                callback = function()
                                    self.archive_abandoned = not self.archive_abandoned
                                    self:saveSettings()
                                end,
                                separator = true,
                            },
                            {
                                text = _("Auto-upload article statuses when downloading"),
                                checked_func = function() return self.auto_archive end,
                                callback = function()
                                    self.auto_archive = not self.auto_archive
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Delete instead of marking as read"),
                                checked_func = function() return self.delete_instead end,
                                callback = function()
                                    self.delete_instead = not self.delete_instead
                                    self:saveSettings()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Local delete settings"),
                        sub_item_table = {
                            {
                                text = _("Delete remotely archived and deleted articles locally"),
                                checked_func = function() return self.sync_remote_archive end,
                                callback = function()
                                    self.sync_remote_archive = not self.sync_remote_archive
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Move to archive directory instead of deleting"),
                                checked_func = function() return self.use_local_archive end,
                                callback = function()
                                    self.use_local_archive = not self.use_local_archive
                                    self:saveSettings()
                                end,
                            },
                            {
                                text_func = function()
                                    local path
                                    if not self.archive_directory or self.archive_directory == "" then
                                        path = _("not set")
                                    else
                                        path = filemanagerutil.abbreviate(self.archive_directory)
                                    end
                                    return T(_("Archive directory: %1"), BD.dirpath(path))
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setArchiveDirectory(touchmenu_instance)
                                end,
                                enabled_func = function()
                                    return self.use_local_archive
                                end,
                            },
                        },
                    },
                    {
                        text = _("History settings"),
                        sub_item_table = {
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
                            },
                            {
                                text = _("Remove articles on hold from history"),
                                keep_menu_open = true,
                                checked_func = function()
                                    return self.remove_abandoned_from_history or false
                                end,
                                callback = function()
                                    self.remove_abandoned_from_history = not self.remove_abandoned_from_history
                                    self:saveSettings()
                                end,
                                separator = true,
                            },
                        },
                        separator = true,
                    },
                    {
                        text_func = function()
                            return T(_("Tags to add to new articles: %1"), self.auto_tags or "")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setTagsDialog(
                                touchmenu_instance,
                                _("Tags to add to new articles"),
                                _("Enter a comma-separated list of tags to add when submitting a new article to wallabag."),
                                self.auto_tags,
                                function(tags)
                                    self.auto_tags = tags
                                end
                            )
                        end,
                    },
                    {
                        text = _("Send review as tags"),
                        help_text = _("This allow you to write tags in the review field, separated by commas, which will be uploaded to the article on wallabag."),
                        keep_menu_open = true,
                        checked_func = function()
                            return self.send_review_as_tags or false
                        end,
                        callback = function()
                            self.send_review_as_tags = not self.send_review_as_tags
                            self:saveSettings()
                        end,
                        separator = true,
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _([[Download directory: use a directory that is exclusively used by the wallabag plugin. Existing files in this directory risk being deleted.

Articles marked as finished, on hold or 100% read can be marked as read (or deleted) on the server. This is done automatically when retrieving new articles with the 'Auto-upload mark as read when downloading' setting.

The 'Delete remotely read and deleted articles locally' option will allow deletion of local files that are archived or deleted on the server.]]),
                            })
                        end,
                    },
                },
            },
            {
                text = _("Info"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[wallabag is an open source read-it-later service. This plugin synchronizes with a wallabag server.

More details: https://wallabag.org

Downloads to directory: %1]]), BD.dirpath(filemanagerutil.abbreviate(self.directory))),
                    })
                end,
            },
        },
    }
end -- Wallabag:addToMainMenu

--- Validate server settings and request an OAuth bearer token.
-- Do not request a new token if the saved one is valid for more than 5 minutes.
function Wallabag:getBearerToken()
    -- Add function to check if the configuration is complete
    local function is_empty(s)
        return s == nil or s == ""
    end

    -- check if the configuration is complete
    local server_empty = (
        is_empty(self.server_url)
        or is_empty(self.username)
        or is_empty(self.password)
        or is_empty(self.client_id)
        or is_empty(self.client_secret)
    )
    local directory_empty = is_empty(self.directory)
    if server_empty or directory_empty then
        logger.warn("Wallabag:getBearerToken: showing dialog because server_empty =", server_empty, "or directory_empty =", directory_empty)
        UIManager:show(MultiConfirmBox:new{
            text = _("Please configure the server settings and set a download directory."),
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
                    return _("Directory (★)")
                else
                    return _("Directory")
                end
            end,
            choice2_callback = function() self:setDownloadDirectory() end,
        })
        return false
    end

    -- Check if the download directory is valid
    local dir_mode = lfs.attributes(self.directory, "mode")
    if dir_mode ~= "directory" then
        logger.err("Wallabag:getBearerToken:", self.directory, "is not a directory")
        UIManager:show(InfoMessage:new{
            text = _("The download directory is not valid.\nPlease configure it in the settings."),
        })

        return false
    end

    -- Add trailing slash if it is missing
    if string.sub(self.directory, -1) ~= "/" then
        self.directory = self.directory .. "/"
    end

    -- Check if token is valid for at least 5 minutes. If so, no need to renew
    local now = os.time()
    if self.token_expiry - now > 300 then
        logger.dbg("Wallabag:getBearerToken: token valid for another", self.token_expiry - now, "s")
        return true
    end

    -- Construct and make API call
    local login_url = "/oauth/v2/token"
    local body = {
        grant_type = "password",
        client_id = self.client_id,
        client_secret = self.client_secret,
        username = self.username,
        password = self.password,
    }
    local body_json = JSON.encode(body)
    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#body_json),
    }
    logger.dbg("Wallabag:getBearerToken: making API call")
    local ok, result = self:callAPI("POST", login_url, headers, body_json)

    if ok then
        self.access_token = result.access_token
        self.token_expiry = now + result.expires_in

        logger.dbg("Wallabag:getBearerToken: new access token is valid for another", result.expires_in, "s")
        return true
    else
        logger.err("Wallabag:getBearerToken: could not login to wallabag server")
        UIManager:show(InfoMessage:new{ text = _("Could not login to wallabag server.") })
        return false
    end
end -- Wallabag:getBearerToken

--- Get a JSON formatted list of articles from the server.
-- The list should have self.article_per_sync item, or less if an error occurred.
-- If filter_tag is set, only articles containing this tag are queried.
-- If ignore_tags is defined, articles containing any of the tags are skipped.
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
        local ok, result, code = self:callAPI("GET", articles_url, nil, nil, nil, true)

        if not ok and result == "http_error" and code == 404 then
            -- We may have hit the last page, there are no more articles
            logger.dbg("Wallabag:getArticleList: requesting page", page, "failed with", result, code)
            break -- exit while loop but do return article_list
        elseif not ok then
            -- Some other error has occurred. Don't proceed with downloading or deleting articles
            logger.warn("Wallabag:getArticleList: requesting page", page, "failed with", result, code)
            UIManager:show(InfoMessage:new{ text = _("Requesting article list failed.") })
            return
        elseif result == nil then
            -- No error occurred, but no JSON was returned either
            logger.warn("Wallabag:getArticleList: requesting page", page, "did not return anything")
            UIManager:show(InfoMessage:new{ text = _("Requesting article list did not return anything.") })
            return
        end

        -- We're only interested in the actual articles in the JSON
        -- Build an array of those so it's easier to manipulate later
        local page_article_list = {}
        for _, article in ipairs(result._embedded.items) do
            table.insert(page_article_list, article)
        end

        -- Remove articles that have any of the tags in self.ignore_tags
        page_article_list = self:filterIgnoredTags(page_article_list)

        -- Append this page's filtered list to the final article_list
        for _, article in ipairs(page_article_list) do
            table.insert(article_list, article)
            if #article_list == self.articles_per_sync then
                logger.dbg("Wallabag:getArticleList: #article_list == self.articles_per_sync ==", self.articles_per_sync)
                break -- exit for loop
            end
        end

        page = page + 1
    end

    return article_list
end -- Wallabag:getArticleList

--- Remove all the articles from the list containing one of the ignored tags.
-- @param article_list Array containing a JSON formatted list of articles
-- @return Same array, but without any articles that contain an ignored tag.
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
                logger.dbg("Wallabag:filterIgnoredTags: skipping", article.id, "because it is tagged", tag.label)
                break -- no need to look for other tags
            end
        end

        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    return filtered_list
end -- Wallabag:filterIgnoredTags

--- Download a single article from the wallabag server given by the id in the article JSON.
-- @treturn int 1 failed, 2 skipped, 3 downloaded
function Wallabag:downloadArticle(article)
    local skip_article = false
    local title = util.getSafeFilename(article.title, self.directory, 230, 0)
    local file_ext = ".epub"
    local item_url = "/api/entries/" .. article.id .. "/export.epub"

    -- The mimetype is actually an HTTP Content-Type, so it can include a semicolon with stuff after it.
    -- Just in case we also trim it, though that shouldn't be necessary.
    -- A function represents `null` in our JSON.decode, because `nil` would just disappear.
    -- We can simplify that to not a string.
    local mimetype = type(article.mimetype) == string and util.trim(article.mimetype:match("^[^;]*")) or nil

    -- If the article links to a supported file type, we will download it directly.
    -- All webpages are HTML. Ignore them since we want the wallabag EPUB instead!
    if self.download_original_document then
        if mimetype ~= "text/html" and DocumentRegistry:hasProvider(nil, mimetype) then
            logger.dbg("Wallabag:downloadArticle: ignoring EPUB in favor of mimetype", mimetype)
            file_ext = "." .. DocumentRegistry:mimeToExt(article.mimetype)
            item_url = article.url
        elseif mimetype == nil and DocumentRegistry:hasProvider(article.url) then
            logger.dbg("Wallabag:downloadArticle: ignoring EPUB in favor of original", article.url)
            file_ext = "." .. util.getFileNameSuffix(article.url)
            item_url = article.url
        else
            logger.dbg("Wallabag:downloadArticle: not ignoring EPUB, because", article.url, "is HTML")
        end
    end

    local local_path = self.directory .. article_id_prefix .. article.id .. article_id_postfix .. title .. file_ext
    logger.dbg("Wallabag:downloadArticle: downloading", article.id, "to", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- File already exists, skip it. Preferably only skip if the date of local file is newer than server's.
        -- newsdownloader.koplugin has a date parser but it is available only if the plugin is activated.
        --- @todo find a better solution
        if self.is_dateparser_available then
            local server_date = self.dateparser.parse(article.updated_at)
            if server_date < attr.modification then
                skip_article = true
                logger.dbg("Wallabag:downloadArticle: skipping download because local copy at", local_path, "is newer")
            end
        else
            skip_article = true
            logger.dbg("Wallabag:downloadArticle: skipping download because local copy exists at", local_path)
        end
    end

    if skip_article == false then
        if self:callAPI("GET", item_url, nil, nil, local_path) then
            return downloaded -- 3
        else
            return failed     -- 1
        end
    end

    return skipped -- 2
end                -- Wallabag:downloadArticle

--- Call the wallabag API.
-- See https://app.wallabag.it/api/doc/ for methods and parameters.
-- @param method GET, POST, DELETE, PATCH, etc…
-- @param url URL endpoint on wallabag server without hostname, or full URL for external link
-- @param[opt] headers Defaults to Authorization for API endpoints, none for external
-- @param[opt] body Body to include in the request, if needed
-- @param[opt] filepath Downloads the file if provided, returns JSON otherwise
-- @param[opt=false] quiet
-- @treturn bool Whether the request was successful
-- @treturn string Error type if unsuccessful, filepath if success with path, JSON if without
-- @treturn int HTTP response code if unsuccessful (e.g. 404, 503, …)
function Wallabag:callAPI(method, url, headers, body, filepath, quiet)
    quiet = quiet or false

    local sink = {}
    local request = { method = method }

    -- Is it an API call, or a regular file direct download?
    --- @todo Separate call to internal API from the download on external server
    if url:sub(1, 1) == "/" then
        -- API call to our server, has the form "/random/api/call"
        request.url = self.server_url .. url
        request.headers = headers or {
            ["Authorization"] = "Bearer " .. self.access_token,
        }
    else -- Assume full URL (e.g. https://…)
        request.url = url
        request.headers = headers or {}
    end

    if filepath ~= nil then
        request.sink = ltn12.sink.file(io.open(filepath, "w"))
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    else
        request.sink = ltn12.sink.table(sink)
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    end

    if body ~= nil then
        request.source = ltn12.source.string(body)
    end

    logger.dbg("Wallabag:callAPI:", request.method, request.url)

    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- Raise error if network is unavailable
    if resp_headers == nil then
        if filepath then
            self:removeFailedDownload(filepath)
        end

        logger.err("Wallabag:callAPI: network error", status or code)
        return false, "network_error"
    end

    -- If the request returned successfully
    if code == 200 then
        if filepath then
            logger.dbg("Wallabag:callAPI: file downloaded to", filepath)
            return true, filepath
        else
            local content = table.concat(sink)

            -- If any JSON was downloaded
            if content ~= "" and string.sub(content, 1, 1) == "{" then
                local ok, result = pcall(JSON.decode, content)

                -- If the downloaded JSON could be parsed
                if ok and result then
                    logger.dbg("Wallabag:callAPI: JSON downloaded")
                    -- Only enable this log when needed, the output can be large
                    -- logger.dbg("result =", result)
                    return true, result
                else
                    logger.err("Wallabag:callAPI: response was no valid JSON", content)
                    UIManager:show(InfoMessage:new{ text = _("Server response is not valid.") })
                end
            else
                logger.err("Wallabag:callAPI: response was no JSON", content)
                UIManager:show(InfoMessage:new{ text = _("Server response is not valid.") })
            end

            return false, "json_error"
        end
    else
        if filepath then
            self:removeFailedDownload(filepath)
        elseif not quiet then
            UIManager:show(InfoMessage:new{ text = _("Communication with server failed.") })
        end

        logger.err("Wallabag:callAPI: HTTP error", status or code, resp_headers)
        return false, "http_error", code
    end
end -- Wallabag:callAPI

function Wallabag:removeFailedDownload(filepath)
    if filepath then
        local entry_mode = lfs.attributes(filepath, "mode")

        if entry_mode == "file" then
            os.remove(filepath)
            logger.dbg("Wallabag:removeFailedDownload: removed", filepath)
        end
    end
end -- Wallabag:removeFailedDownload

--- Add articles from local queue to wallabag, then download new articles.
-- If self.auto_archive is true, then local article statuses are uploaded before downloading.
-- @treturn bool Whether the synchronization process reached the end (with or without errors)
function Wallabag:downloadArticles()
    local info = InfoMessage:new{ text = _("Connecting to wallabag server…") }
    UIManager:show(info)

    local del_count_remote = 0
    local del_count_local = 0

    -- Update bearer token if needed
    if not self:getBearerToken() or self.access_token == "" then
        UIManager:close(info)
        return false
    end

    UIManager:close(info)

    -- Add articles from queue to remote
    local queue_count = self:uploadQueue()

    -- Upload local article statuses to remote
    if self.auto_archive == true then
        logger.dbg("Wallabag:downloadArticles: uploading statuses automatically")
        del_count_remote, del_count_local = self:uploadStatuses()
    else
        logger.dbg("Wallabag:downloadArticles: skipping status upload")
    end

    local remote_article_ids = {}
    local download_count = 0
    local fail_count = 0
    local skip_count = 0

    -- Get a list of articles to download
    info = InfoMessage:new{ text = _("Getting list of newest articles on wallabag…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local articles = self:getArticleList()
    UIManager:close(info)

    if articles then
        logger.dbg("Wallabag:downloadArticles: got a list of", #articles, "articles")
        info = InfoMessage:new{
            text = T(
                _("Got a list of %1 articles…"),
                #articles
            ),
            timeout = 5,
        }
        UIManager:show(info)
        UIManager:forceRePaint()

        for i, article in ipairs(articles) do -- Do not use `_`
            logger.dbg("Wallabag:downloadArticles: downloading", article.id)
            remote_article_ids[tostring(article.id)] = true

            local res = self:downloadArticle(article)

            if res == downloaded then
                logger.dbg("Wallabag:downloadArticles: downloading", article.id, "succeeded")
                download_count = download_count + 1
                info = InfoMessage:new{
                    text = T(
                        _("Downloaded article %1 of %2…"),
                        download_count,
                        #articles
                    ),
                    timeout = 5,
                }
                UIManager:show(info)
                UIManager:forceRePaint()
            elseif res == failed then
                logger.err("Wallabag:downloadArticles: downloading", article.id, "failed")
                fail_count = fail_count + 1
            else -- res == skipped
                logger.err("Wallabag:downloadArticles: downloading", article.id, "skipped")
                skip_count = skip_count + 1
            end
        end

        -- Synchronize remote deletions to local
        if self.sync_remote_archive then
            logger.dbg("Wallabag:downloadArticles: processing remote deletes…")
            del_count_local = del_count_local + self:processRemoteDeletes(remote_article_ids)
        else
            logger.dbg("Wallabag:downloadArticles: processing remote deletes skipped")
        end

        logger.info("Wallabag:downloadArticles: sync finished")
        local msg = _("Sync finished:")

        logger.info("Wallabag:downloadArticles: - queue_count =", queue_count)
        if queue_count > 0 then
            msg = msg .. T(_("\n- added from queue: %1"), queue_count)
        end

        logger.info("Wallabag:downloadArticles: - download_count =", download_count)
        msg = msg .. T(_("\n- downloaded: %1"), download_count)

        logger.dbg("Wallabag:downloadArticles: - skip_count =", skip_count)
        if skip_count > 0 then
            msg = msg .. T(_("\n- skipped: %1"), skip_count)
        end

        logger.info("Wallabag:downloadArticles: - fail_count =", fail_count)
        if fail_count > 0 then
            msg = msg .. T(_("\n- failed: %1"), fail_count)
        end

        logger.info("Wallabag:downloadArticles: - del_count_local =", del_count_local)
        if del_count_local > 0 then
            if self.use_local_archive then
                msg = msg .. T(_("\n- archived in KOReader: %1"), del_count_local)
            else
                msg = msg .. T(_("\n- deleted from KOReader: %1"), del_count_local)
            end
        end

        logger.info("Wallabag:downloadArticles: - del_count_remote =", del_count_remote)
        if del_count_remote > 0 then
            if self.delete_instead then
                msg = msg .. T(_("\n- deleted from wallabag: %1"), del_count_remote)
            else
                msg = msg .. T(_("\n- archived in wallabag: %1"), del_count_remote)
            end
        end

        UIManager:close(info)
        info = InfoMessage:new{ text = msg }
        UIManager:show(info)
        UIManager:forceRePaint()
    end -- articles

    return true
end -- Wallabag:downloadArticles

--- Upload any articles that were added to the queue.
-- In case there was no network connection to upload them at the time.
-- @tparam[opt] quiet bool Whether to supress the info message or not
-- @treturn int Number of article URLs added to the server
function Wallabag:uploadQueue(quiet)
    quiet = quiet or true

    local count = 0

    if self.upload_queue and next(self.upload_queue) ~= nil then
        local info = InfoMessage:new{ text = T(
            _("Uploading %1 articles from queue…"),
            #self.upload_queue
        ) }
        UIManager:show(info)

        for _, articleUrl in ipairs(self.upload_queue) do
            if self:addArticle(articleUrl) then
                count = count + 1
                --- @todo Add error handling
            end
        end

        self.upload_queue = {}
        self:saveSettings()
        UIManager:close(info)
    end

    if not quiet then
        local msg = T(_("Uploaded %1 articles from the queue to wallabag"), count)
        local info = InfoMessage:new{ text = msg }
        UIManager:show(info)
    end

    logger.info("Wallabag:uploadQueue: uploaded", count, "articles from the queue to wallabag")

    return count
end -- Wallabag:uploadQueue

--- Compare local IDs with remote_article_ids and delete or archive any that are missing.
-- @tparam remote_article_ids tab Article IDs of articles downloaded this sync run
-- @treturn int Number of locally deleted or archived articles
function Wallabag:processRemoteDeletes(remote_ids)
    logger.dbg("Wallabag:processRemoteDeletes: remote_ids =", remote_ids)

    local info = InfoMessage:new{ text = _("Synchronizing remote archivals and deletions…") }
    UIManager:show(info)
    UIManager:forceRePaint()

    local count = 0

    for entry in lfs.dir(self.directory) do
        local entry_path = self.directory .. entry

        if entry ~= "." and entry ~= ".." and lfs.attributes(entry_path, "mode") == "file" then
            local local_id = self:getArticleID(entry_path)

            if not remote_ids[local_id] then
                if self.use_local_archive then
                    logger.dbg("Wallabag:processRemoteDeletes: archiving", local_id, "at", entry_path)
                    count = count + self:archiveLocalArticle(entry_path)
                else
                    logger.dbg("Wallabag:processRemoteDeletes: deleting", local_id, "at", entry_path)
                    count = count + self:deleteLocalArticle(entry_path)
                end -- if self.use_local_archive
            else
                logger.dbg("Wallabag:processRemoteDeletes: local_id", local_id, "found in remote_ids; not archiving/deleting")
            end -- if not remote_article_ids[ id ]
        end     -- if entry ~= . and entry ~= ..
    end         -- for entry

    UIManager:close(info)
    return count
end -- Wallabag:processRemoteDeletes

--- Archive (or delete) locally finished articles on the wallabag server.
-- @tparam[opt] quiet bool Whether to supress the info message or not
function Wallabag:uploadStatuses(quiet)
    if quiet == nil then
        quiet = true
    end

    local count_remote = 0
    local count_local = 0

    -- Update bearer token if needed
    if self:getBearerToken() == false then
        logger.warn("Wallabag:uploadStatuses: could not update bearer token, skipping upload of statuses")

        return count_remote, count_local
    end

    if self.archive_finished or self.archive_read or self.archive_abandoned then
        local info = InfoMessage:new{ text = _("Uploading local article statuses…") }
        UIManager:show(info)
        UIManager:forceRePaint()

        for entry in lfs.dir(self.directory) do
            local skip = false

            if entry ~= "." and entry ~= ".." then
                local entry_path = self.directory .. entry

                if DocSettings:hasSidecarFile(entry_path) then
                    logger.dbg("Wallabag:uploadStatuses:", entry_path, "has sidecar file")

                    if self.send_review_as_tags then
                        self:addTagsFromReview(entry_path)
                    end

                    local doc_settings = DocSettings:open(entry_path)
                    local summary = doc_settings:readSetting("summary")
                    local status = summary and summary.status
                    local percent_finished = doc_settings:readSetting("percent_finished")

                    if (
                            (status == "complete" and self.archive_finished)
                            or (status == "abandoned" and self.archive_abandoned)
                            or (percent_finished == 1 and self.archive_read)
                        ) then
                        logger.dbg("Wallabag:uploadStatuses: - has been finished, so archiving/deleting on remote…")

                        if self:archiveArticle(entry_path) then
                            count_remote = count_remote + 1
                            logger.dbg("Wallabag:uploadStatuses: - archived/deleted on remote")
                        else
                            logger.warn("Wallabag:uploadStatuses: - could not archive/delete on remote")
                            skip = true -- Skip local archiving/deleting
                        end

                        if skip then
                            logger.dbg("Wallabag:uploadStatuses: - skipping local archiving/deleting")
                        else
                            if self.use_local_archive then
                                logger.dbg("Wallabag:uploadStatuses: - archiving locally as well")
                                count_local = count_local + self:archiveLocalArticle(entry_path)
                            else
                                logger.dbg("Wallabag:uploadStatuses: - deleting locally as well")
                                count_local = count_local + self:deleteLocalArticle(entry_path)
                            end -- if use local archive
                        end     -- if not skip
                    else        -- not finished
                        logger.dbg("Wallabag:uploadStatuses: - but has not been finished yet")
                    end         -- if finished
                end             -- if has sidecar
            end                 -- if not . or ..
        end                     -- for entry

        UIManager:close(info)
    end -- if self.archive

    logger.info("Wallabag:uploadStatuses: upload finished")
    logger.info("Wallabag:uploadStatuses: - count_remote =", count_remote)
    logger.info("Wallabag:uploadStatuses: - count_local =", count_local)
    logger.dbg("Wallabag:uploadStatuses: - quiet =", quiet)

    if not quiet then
        local msg = _("Upload finished:")

        if self.delete_instead then
            msg = msg .. T(_("\n- deleted from wallabag: %1"), count_remote)
        else
            msg = msg .. T(_("\n- archived on wallabag: %1"), count_remote)
        end

        if self.use_local_archive then
            msg = msg .. T(_("\n- archived in KOReader: %1"), count_local)
        else
            msg = msg .. T(_("\n- deleted from KOReader: %1"), count_local)
        end

        local info = InfoMessage:new{ text = msg }
        UIManager:show(info)
        UIManager:forceRePaint()
    end -- if not quiet

    return count_remote, count_local
end -- Wallabag:uploadStatuses

--- Add a new article (including any auto_tags) to the wallabag server.
-- @tparam article_url string Full URL of the article
-- @treturn bool Whether the API call could be made successfully
function Wallabag:addArticle(article_url)
    logger.dbg("Wallabag:addArticle: adding", article_url)

    -- Update bearer token if needed
    if not article_url or self:getBearerToken() == false then
        return false
    end

    local body = {
        url = article_url,
        tags = self.auto_tags,
    }

    local body_JSON = JSON.encode(body)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#body_JSON),
        ["Authorization"] = "Bearer " .. self.access_token,
    }

    return self:callAPI("POST /api/entries.json", headers, body_JSON) == true
end -- Wallabag:addArticle

--- Add tags from the local review to the article on wallabag.
-- @tparam path string Local path of the article
-- @treturn nil
function Wallabag:addTagsFromReview(path)
    logger.dbg("Wallabag:addTagsFromReview: managing tags for", path)

    local id = self:getArticleID(path)

    if id then
        local doc_settings = DocSettings:open(path)
        local summary = doc_settings:readSetting("summary")
        local tags = summary and summary.note

        if tags and tags ~= "" then
            logger.dbg("Wallabag:addTagsFromReview: sending tags", tags, "for", path)

            local body = {
                tags = tags,
            }

            local bodyJSON = JSON.encode(body)

            local headers = {
                ["Content-type"] = "application/json",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#bodyJSON),
                ["Authorization"] = "Bearer " .. self.access_token,
            }

            self:callAPI("POST /api/entries/" .. id .. "/tags.json", headers, bodyJSON)
        else
            logger.dbg("Wallabag:addTagsFromReview: no tags to send for", path)
        end
    end
end -- Wallabag:addTagsFromReview

--- Archive an article on wallabag, or if delete_instead, then delete.
-- @tparam path string Local path of the article
-- @treturn bool Whether archiving or deleting was completed
function Wallabag:archiveArticle(path)
    logger.dbg("Wallabag:archiveArticle: getting wallabag ID from", path)

    local id = self:getArticleID(path)

    if id then
        if self.delete_instead then
            logger.dbg("Wallabag:archiveArticle: deleting", path, "on remote")
            if self:callAPI("DELETE /api/entries/" .. id .. ".json") then
                return true
            end
        else
            local body = { archive = 1 }
            local bodyJSON = JSON.encode(body)
            local headers = {
                ["Content-type"] = "application/json",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#bodyJSON),
                ["Authorization"] = "Bearer " .. self.access_token,
            }

            logger.dbg("Wallabag:archiveArticle: archiving", path, "on remote")
            if self:callAPI("PATCH /api/entries/" .. id .. ".json", headers, bodyJSON) then
                return true
            end
        end -- if delete_instead
    end     -- if id

    return false
end -- Wallabag:archiveArticle

--- Move an article and its sidecar to archive_directory.
-- @tparam path string Local path of the article
-- @treturn int 1 if successful, 0 if not
function Wallabag:archiveLocalArticle(path)
    local result = 0

    -- Check if the archive directory is valid
    local dir_mode = lfs.attributes(self.archive_directory, "mode")
    if dir_mode == nil then
        util.makePath(self.archive_directory)
        UIManager:show(InfoMessage:new{
            text = T(_("Created the archive directory at %1."), self.archive_directory),
            timeout = 10,
        })
    elseif dir_mode ~= "directory" then
        UIManager:show(InfoMessage:new{
            text = _("The archive directory is not valid.\nPlease configure it in the settings."),
        })
        return result
    end

    if lfs.attributes(path, "mode") == "file" then
        local _, file = util.splitFilePathName(path)
        local new_path = self.archive_directory .. file
        if FileManager:moveFile(path, new_path) then
            result = 1
        end
        DocSettings.updateLocation(path, new_path, false) -- move sdr
        --- @todo Why is sdr copied instead of moved?
    end

    return result
end -- Wallabag:archiveLocalArticle

--- Delete an article and its sidecar locally.
-- @tparam path string Local path of the article
-- @treturn int 1 if successful, 0 if not
function Wallabag:deleteLocalArticle(path)
    local result = 0

    if lfs.attributes(path, "mode") == "file" then
        FileManager:deleteFile(path, true)
        result = 1
    end

    return result
end -- Wallabag:deleteLocalArticle

--- Extract the wallabag ID from the file name.
-- @tparam path string Local path of the article
-- @return ID as string if successful, nil if not
function Wallabag:getArticleID(path)
    local _, filename = util.splitFilePathName(path)
    local prefix_len = article_id_prefix:len()

    logger.dbg("Wallabag:getArticleID: getting id from", filename)

    if filename:sub(0, prefix_len) ~= article_id_prefix then
        logger.warn(filename:sub(0, prefix_len), "~=", article_id_prefix)
        return
    end

    local endpos = filename:find(article_id_postfix, prefix_len)

    if endpos == nil then
        logger.warn("Wallabag:getArticleID:", article_id_postfix, "was not found in", filename)
        return
    end

    local id = filename:sub(prefix_len + 1, endpos - 1)
    logger.dbg("Wallabag:getArticleID: got id", id, "from", filename)

    return id
end -- Wallabag:getArticleID

function Wallabag:refreshFileManager()
    if FileManager.instance then
        FileManager.instance:onRefresh()
    end
end -- Wallabag:refreshFileManager

--- A dialog used for setting filter_tag, ignore_tags and auto_tags.
function Wallabag:setTagsDialog(touchmenu_instance, title, description, value, callback)
    self.tags_dialog = InputDialog:new{
        title = title,
        description = description,
        input = value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.tags_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        callback(self.tags_dialog:getInputText())
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.tags_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.tags_dialog)
    self.tags_dialog:onShowKeyboard()
end -- Wallabag:setTagsDialog

--- The dialog shown when clicking "Configure wallabag server".
-- Or automatically, when getBearerToken is run with an incomplete server configuration.
function Wallabag:editServerSettings()
    local text_info = T(_([[
Enter the details of your wallabag server and account.

Client ID and client secret are long strings so you might prefer to save the empty settings and edit the config file directly in your installation directory:
%1/wallabag.lua

Restart KOReader after editing the config file.]]), BD.dirpath(DataStorage:getSettingsDir()))

    self.settings_dialog = MultiInputDialog:new{
        title = _("wallabag settings"),
        fields = {
            {
                text = self.server_url,
                hint = _("Server URL"),
            },
            {
                text = self.client_id,
                hint = _("Client ID"),
            },
            {
                text = self.client_secret,
                hint = _("Client secret"),
            },
            {
                text = self.username,
                hint = _("Username"),
            },
            {
                text = self.password,
                text_type = "password",
                hint = _("Password"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.settings_dialog)
                    end,
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end,
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields     = self.settings_dialog:getFields()
                        self.server_url    = myfields[1]:gsub("/*$ ") -- remove all trailing slashes
                        self.client_id     = myfields[2]
                        self.client_secret = myfields[3]
                        self.username      = myfields[4]
                        self.password      = myfields[5]
                        self:saveSettings()
                        UIManager:close(self.settings_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end -- Wallabag:editServerSettings

--- The dialog shown when clicking "Number of articles to download".
function Wallabag:setArticlesPerSync(touchmenu_instance)
    self.articles_dialog = InputDialog:new{
        title = _("Number of articles to download"),
        input = tostring(self.articles_per_sync),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.articles_dialog)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        self.articles_per_sync = math.max(1,
                            tonumber(self.articles_dialog:getInputText()) or self.articles_per_sync)
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.articles_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.articles_dialog)
    self.articles_dialog:onShowKeyboard()
end -- Wallabag:setArticlesPerSync

--- The dialog shown when clicking "Download directory".
-- Or automatically, when getBearerToken is run with an incomplete server configuration.
function Wallabag:setDownloadDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            self.directory = path
            self:saveSettings()
            logger.dbg("Wallabag:setDownloadDirectory: set download directory to", path)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }:chooseDir()
end -- Wallabag:setDownloadDirectory

--- The dialog shown when clicking "Archive directory"
function Wallabag:setArchiveDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            self.archive_directory = path
            self:saveSettings()
            logger.dbg("Wallabag:setArchiveDirectory: set archive directory to", path)
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }:chooseDir()
end -- Wallabag:setArchiveDirectory

function Wallabag:saveSettings()
    local tempsettings = {
        server_url                    = self.server_url,
        client_id                     = self.client_id,
        client_secret                 = self.client_secret,
        username                      = self.username,
        password                      = self.password,
        directory                     = self.directory,
        archive_directory             = self.archive_directory,
        archive_abandoned             = self.archive_abandoned,
        archive_finished              = self.archive_finished,
        archive_read                  = self.archive_read,
        articles_per_sync             = self.articles_per_sync,
        auto_archive                  = self.auto_archive,
        auto_tags                     = self.auto_tags,
        delete_instead                = self.delete_instead,
        download_original_document    = self.download_original_document,
        filter_tag                    = self.filter_tag,
        ignore_tags                   = self.ignore_tags,
        remove_abandoned_from_history = self.remove_abandoned_from_history,
        remove_finished_from_history  = self.remove_finished_from_history,
        remove_read_from_history      = self.remove_read_from_history,
        send_review_as_tags           = self.send_review_as_tags,
        sync_remote_archive           = self.sync_remote_archive,
        upload_queue                  = self.upload_queue,
        use_local_archive             = self.use_local_archive,
    }

    self.wb_settings:saveSetting("wallabag", tempsettings)
    self.wb_settings:flush()
end -- Wallabag:saveSettings

function Wallabag:readSettings()
    local wb_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/wallabag.lua")
    wb_settings:readSetting("wallabag", {})
    return wb_settings
end -- Wallabag:readSettings

--- Handler for addWallabagArticle event.
--- Uploads a new article to wallabag directly if there is a network connection, or add it to the
-- local upload queue.
function Wallabag:onAddWallabagArticle(article_url)
    if not NetworkMgr:isOnline() then
        self:addToUploadQueue(article_url)
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to upload queue:\n%1"), BD.url(article_url)),
            timeout = 10,
        })
        return
    end

    if self:addArticle(article_url) then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to wallabag:\n%1"), BD.url(article_url)),
            timeout = 10,
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Error adding link to wallabag:\n%1"), BD.url(article_url)),
        })
    end

    -- stop propagation
    return true
end -- Wallabag:onAddWallabagArticle

function Wallabag:onSynchronizeWallabag()
    local connect_callback = function()
        logger.dbg("Wallabag:onSynchronizeWallabag:connect_callback: downloading articles…")
        self:downloadArticles()
        logger.dbg("Wallabag:onSynchronizeWallabag:connect_callback: refreshing file manager…")
        self:refreshFileManager()
    end

    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end -- Wallabag:onSynchronizeWallabag

function Wallabag:onUploadWallabagQueue()
    local connect_callback = function()
        self:uploadQueue(false)
        self:refreshFileManager()
    end

    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end -- Wallabag:onUploadWallabagQueue

function Wallabag:onUploadWallabagStatuses()
    local connect_callback = function()
        self:uploadStatuses(false)
        self:refreshFileManager()
    end

    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end -- Wallabag:onUploadWallabagStatuses

function Wallabag:onGoToWallabagDirectory()
    if self.ui.document then
        self.ui:onClose()
        logger.dbg("Wallabag:onGoToWallabagDirectory: closed document")
    end

    if FileManager.instance then
        FileManager.instance:reinit(self.directory)
        logger.dbg("Wallabag:onGoToWallabagDirectory: reinitialized file manager at", self.directory)
    else
        FileManager:showFiles(self.directory)
        logger.dbg("Wallabag:onGoToWallabagDirectory: opened file manager at", self.directory)
    end

    -- stop propagation
    return true
end -- Wallabag:onGoToWallabagDirectory

--- Get percent read of the opened article.
function Wallabag:getLastPercent()
    local percent = self.ui.paging and self.ui.paging:getLastPercent() or self.ui.rolling:getLastPercent()
    return Math.roundPercent(percent)
end -- Wallabag:getLastPercent

function Wallabag:addToUploadQueue(article_url)
    table.insert(self.upload_queue, article_url)
    self:saveSettings()
    logger.dbg("Wallabag:addToUploadQueue: added", article_url, "to queue")
end -- Wallabag:addToUploadQueue

--- Handler for the closeDocument event.
-- If the opened article/book is saved in the wallabag directory, and if any of the
-- remove_from_history settings are set and matching, then remove it from history
function Wallabag:onCloseDocument()
    if self.remove_finished_from_history or self.remove_read_from_history or self.remove_abandoned_from_history then
        local document_full_path = self.ui.document.file
        local summary = self.ui.doc_settings:readSetting("summary")
        local status = summary and summary.status
        local is_finished = status == "complete"
        local is_read = self:getLastPercent() == 1
        local is_abandoned = status == "abandoned"

        if document_full_path
            and self.directory
            and (
                (self.remove_finished_from_history and is_finished)
                or (self.remove_read_from_history and is_read)
                or (self.remove_abandoned_from_history and is_abandoned)
            )
            and self.directory == string.sub(document_full_path, 1, string.len(self.directory)) then
            ReadHistory:removeItemByPath(document_full_path)
            self.ui:setLastDirForFileBrowser(self.directory)
        end
    end
end -- Wallabag:onCloseDocument

return Wallabag
