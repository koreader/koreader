--[[--
@module koplugin.pocket
]]

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
local LuaSettings = require("frontend/luasettings")
local Math = require("optmath")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template
local Screen = require("device").screen
local PocketApi = require("./api")


local DownloadBackend = require("epubdownloadbackend")

-- constants
local article_id_prefix = "[w-id_"
local article_id_postfix = "] "
local failed, skipped, downloaded = 1, 2, 3

local Pocket = WidgetContainer:new{
    name = "Pocket",
}

function Pocket:onDispatcherRegisterActions()
    Dispatcher:registerAction("pocket_download", { category="none", event="SynchronizePocket", title=_("Pocket retrieval"), device=true,})
end

function Pocket:init()
    self.is_delete_finished = true
    self.is_delete_read = false
    self.is_auto_delete = false
    self.is_sync_remote_delete = false
    self.is_archiving_deleted = false
    self.filter_tag = ""
    self.ignore_tags = ""

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.wb_settings = self.readSettings()
    self.articles_per_sync = self.wb_settings.data.pocket.articles_per_sync or 30
    self.default_consumer_key = '95098-ae9dbddd5a88261cc5d7d29d'
    self.consumer_key = self.wb_settings.data.pocket.consumer_key or self.default_consumer_key
    self.directory = self.wb_settings.data.pocket.directory
    if self.wb_settings.data.pocket.access_token ~= nil then
        self.access_token = self.wb_settings.data.pocket.access_token
    end
    if self.wb_settings.data.pocket.is_delete_finished ~= nil then
        self.is_delete_finished = self.wb_settings.data.pocket.is_delete_finished
    end
    if self.wb_settings.data.pocket.is_delete_read ~= nil then
        self.is_delete_read = self.wb_settings.data.pocket.is_delete_read
    end
    if self.wb_settings.data.pocket.is_auto_delete ~= nil then
        self.is_auto_delete = self.wb_settings.data.pocket.is_auto_delete
    end
    if self.wb_settings.data.pocket.is_sync_remote_delete ~= nil then
        self.is_sync_remote_delete = self.wb_settings.data.pocket.is_sync_remote_delete
    end
    if self.wb_settings.data.pocket.is_archiving_deleted ~= nil then
        self.is_archiving_deleted = self.wb_settings.data.pocket.is_archiving_deleted
    end
    if self.wb_settings.data.pocket.filter_tag then
        self.filter_tag = self.wb_settings.data.pocket.filter_tag
    end
    if self.wb_settings.data.pocket.ignore_tags then
        self.ignore_tags = self.wb_settings.data.pocket.ignore_tags
    end
    if self.wb_settings.data.pocket.articles_per_sync ~= nil then
        self.articles_per_sync = self.wb_settings.data.pocket.articles_per_sync
    end
    self.remove_finished_from_history = self.wb_settings.data.pocket.remove_finished_from_history or false
    self.download_queue = self.wb_settings.data.pocket.download_queue or {}
    self:initApi()

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

function Pocket:initApi()
    local function notempty(s)
        return s ~= nil and s ~= ""
    end
    if notempty(self.access_token) then
        self.api = PocketApi:new(self.consumer_key, self.access_token, self.articles_per_sync)
    else
        self.api = nil
    end
end

function Pocket:addToMainMenu(menu_items)
    menu_items.pocket = {
        text = _("Pocket"),
        sub_item_table = {
            {
                text = _("Retrieve new articles from server"),
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizePocket"))
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
                        text = _("Configure Pocket client"),
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
                                text = _([[Download directory: use a directory that is exclusively used by the Pocket plugin. Existing files in this directory risk being deleted.

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
                        text = T(_([[Pocket is a read-it-later service. This plugin synchronizes with with it.

See for more details: https://getpocket.com

Downloads to directory: %1]]), BD.dirpath(filemanagerutil.abbreviate(self.directory)))
                    })
                end,
            },
        },
    }
end

--- Get a JSON formatted list of articles from the server.
-- The list should have self.article_per_sync item, or less if an error occured.
-- If filter_tag is set, only articles containing this tag are queried.
-- If ignore_tags is defined, articles containing either of the tags are skipped.
function Pocket:getArticleList()
    local page = 0

    local article_list = {}
    -- query the server for articles until we hit our target number
    while #article_list < self.articles_per_sync do
        local articles_json = self.api:getArticleList(page, self.filter_tag)

        if not articles_json then
            -- we may have hit the last page, there are no more articles
            logger.dbg("Pocket: couldn't get page #", page)
            break -- exit while loop
        end

        local new_articles_list = articles_json.list

        -- Apply the filters
        new_articles_list = self:filterIgnoredTags(new_articles_list)

        -- Append the filtered list to the final article list
        for i, article in ipairs(new_articles_list) do
            if #article_list == self.articles_per_sync then
                logger.dbg("Pocket: hit the article target", self.articles_per_sync)
                break
            end
            table.insert(article_list, article)
        end

        page = page + 1
        if #articles_json.list < self.articles_per_sync then
            logger.dbg("Got last page")
            break
        end
    end

    return article_list
end

--- Remove all the articles from the list containing one of the ignored tags.
-- article_list: array containing a json formatted list of articles
-- returns: same array, but without any articles that contain an ignored tag.
function Pocket:filterIgnoredTags(article_list)
    -- decode all tags to ignore
    local ignoring = {}
    if self.ignore_tags ~= "" then
        for tag in util.gsplit(self.ignore_tags, "[,]+", false) do
            ignoring[tag] = true
        end
    end

    -- rebuild a list without the ignored articles
    local filtered_list = {}
    for _, article in pairs(article_list) do
        local skip_article = false
        local tags = article.tags or {}
        for _, tag in ipairs(tags) do
            if ignoring[tag.tag] then
                skip_article = true
                logger.dbg("Pocket: ignoring tag", tag.tag, "in article",
                           article.item_id, ":", article.resolved_title)
                break -- no need to look for other tags
            end
        end
        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    return filtered_list
end

--- Download Pocket article.
-- @string article
-- @treturn int 1 failed, 2 skipped, 3 downloaded
function Pocket:download(article)
    local skip_article = false
    local title = util.getSafeFilename(article.resolved_title, self.directory, 230, 0)
    local file_ext = ".epub"

    local local_path = self.directory .. '/' .. title .. file_ext
    local local_path = self.directory .. article_id_prefix .. article.id .. article_id_postfix .. title .. file_ext
    logger.dbg("Pocket: DOWNLOAD: id: ", article.item_id)
    logger.dbg("Pocket: DOWNLOAD: title: ", article.resolved_title)
    logger.dbg("Pocket: DOWNLOAD: filename: ", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- File already exists, skip it. Preferably only skip if the date of local file is newer than server's.
        -- newsdownloader.koplugin has a date parser but it is available only if the plugin is activated.
        --- @todo find a better solution
        if self.is_dateparser_available then
            local server_date = self.dateparser.parse(article.updated_at)
            if server_date < attr.modification then
                skip_article = true
                logger.dbg("Pocket: skipping file (date checked): ", local_path)
            end
        else
            skip_article = true
            logger.dbg("Pocket: skipping file: ", local_path)
        end
    end

    if skip_article == false then
        --- Pocket API returns urls with escaped / for some reason like https:\/\/example.org\/art1…
        local link = article.resolved_url:gsub("\\/", "/")
        local html = DownloadBackend:loadPage(link)
        DownloadBackend:createEpub(local_path, html, link, true, "Downloading Pocket article " .. link .. " as epub", false, nil)
        return downloaded
    end
    return skipped
end


function Pocket:synchronize()
    if not self:assertValidSettings() then
        return
    end
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

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
    local articles = self:getArticleList()
    if articles then
        logger.dbg("Pocket: number of articles: ", #articles)

        info = InfoMessage:new{ text = _("Downloading articles…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        for _, article in ipairs(articles) do
            logger.dbg("Pocket: processing article ID: ", article.item_id)
            remote_article_ids[ tostring(article.item_id) ] = true
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
    end
end

function Pocket:processRemoteDeletes(remote_article_ids)
    if not self.is_sync_remote_delete then
        logger.dbg("Pocket: Processing of remote file deletions disabled.")
        return 0
    end
    logger.dbg("Pocket: articles IDs from server: ", remote_article_ids)

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
                logger.dbg("Pocket: Deleting local file (deleted on server): ", entry_path)
                self:deleteLocalArticle(entry_path)
                deleted_count = deleted_count + 1
            end
        end
    end -- for entry
    return deleted_count
end

function Pocket:processLocalFiles(mode)
    if mode then
        if self.is_auto_delete == false and mode ~= "manual" then
            logger.dbg("Pocket: Automatic processing of local files disabled.")
            return 0, 0
        end
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

function Pocket:addArticle(article_url)
    logger.dbg("Pocket: adding article ", article_url)

    if not article_url or self:assertValidSettings() == false then
        return false
    end

    return self.api:addArticle(article_url)
end

function Pocket:removeArticle(path)
    logger.dbg("Pocket: removing article ", path)
    local id = self:getArticleID(path)
    logger.dbg("Removing pocket article id", id)
    if id then
        if self.is_archiving_deleted then
            self.api:modifyArticle(id, 'archive')
        else
            self.api:modifyArticle(id, 'delete')
        end
        self:deleteLocalArticle(path)
    end
end

function Pocket:deleteLocalArticle(path)
    local entry_mode = lfs.attributes(path, "mode")
    if entry_mode == "file" then
        os.remove(path)
        local sdr_dir = DocSettings:getSidecarDir(path)
        FFIUtil.purgeDir(sdr_dir)
        ReadHistory:fileDeleted(path)
   end
end

function Pocket:getArticleID(path)
    -- extract the Pocket ID from the file name
    local offset = self.directory:len() + 2 -- skip / and advance to the next char
    local prefix_len = article_id_prefix:len()
    if path:sub(offset , offset + prefix_len - 1) ~= article_id_prefix then
        logger.warn("Pocket: getArticleID: no match! ", path:sub(offset , offset + prefix_len - 1))
        return
    end
    local endpos = path:find(article_id_postfix, offset + prefix_len)
    if endpos == nil then
        logger.warn("Pocket: getArticleID: no match! ")
        return
    end
    local id = path:sub(offset + prefix_len, endpos - 1)
    return id
end

function Pocket:refreshCurrentDirIfNeeded()
    if FileManager.instance then
        FileManager.instance:onRefresh()
    end
end

function Pocket:assertValidSettings()
    -- Check if the configuration is complete
    if self.api == nil then
        self:editClientSettings()
        return false
    end
end

function Pocket:setFilterTag(touchmenu_instance)
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

function Pocket:setIgnoreTags(touchmenu_instance)
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

function Pocket:editClientSettings()
    local text_info = T(_([[
Enter the details of your Pocket account.

Consumer token (optional) and access token are long strings so you might prefer to save the empty settings and edit the config file directly in your installation directory:
%1/pocket.lua

Restart KOReader after editing the config file.]]), BD.dirpath(DataStorage:getSettingsDir()))
    self.client_settings_dialog = MultiInputDialog:new {
        title = _("Pocket client settings"),
        fields = {
            {
                text = self.articles_per_sync,
                description = _("Number of articles"),
                input_type = "number",
                hint = _("Number of articles to download per sync")
            },
            {
                text = self.consumer_key,
                description = T(_("Consumer key. Can be left empty (advanced users only).")),
                input_type = "string",
                hint = _("Consumer Key")
            },
            {
                text = self.access_token,
                description = T(_("Access token (required).")),
                input_type = "string",
                hint = _("Access token")
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
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = MultiInputDialog:getFields()
                        self.articles_per_sync = math.max(1, tonumber(myfields[1]) or self.articles_per_sync)
                        self.consumer_key = myfields[2] or self.default_consumer_key
                        self.access_token = myfields[3]
                        self:saveSettings(myfields)
                        self:initApi()
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

function Pocket:setDownloadDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
       onConfirm = function(path)
           logger.dbg("Pocket: set download directory to: ", path)
           self.directory = path
           self:saveSettings()
           touchmenu_instance:updateItems()
       end,
    }:chooseDir()
end

function Pocket:saveSettings()
    local tempsettings = {
        consumer_key          = self.consumer_key,
        access_token          = self.access_token,
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
    self.wb_settings:saveSetting("pocket", tempsettings)
    self.wb_settings:flush()
end

function Pocket:readSettings()
    local wb_settings = LuaSettings:open(DataStorage:getSettingsDir().."/pocket.lua")
    if not wb_settings.data.pocket then
        wb_settings.data.pocket = {}
    end
    return wb_settings
end

function Pocket:saveWBSettings(setting)
    if not self.wb_settings then self:readSettings() end
    self.wb_settings:saveSetting("pocket", setting)
    self.wb_settings:flush()
end

function Pocket:onAddPocketArticle(article_url)
    if not NetworkMgr:isOnline() then
        self:addToDownloadQueue(article_url)
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to download queue:\n%1"), BD.url(article_url)),
            timeout = 1,
         })
        return
    end

    local pocket_result = self:addArticle(article_url)
    if pocket_result then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to Pocket:\n%1"), BD.url(article_url)),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Error adding link to Pocket:\n%1"), BD.url(article_url)),
        })
    end

    -- stop propagation
    return true
end

function Pocket:onSynchronizePocket()
    local connect_callback = function()
        self:synchronize()
        self:refreshCurrentDirIfNeeded()
    end
    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end

function Pocket:getLastPercent()
    if self.ui.document.info.has_pages then
        return Math.roundPercent(self.ui.paging:getLastPercent())
    else
        return Math.roundPercent(self.ui.rolling:getLastPercent())
    end
end

function Pocket:addToDownloadQueue(article_url)
    table.insert(self.download_queue, article_url)
    self:saveSettings()
end

function Pocket:onCloseDocument()
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

return Pocket
