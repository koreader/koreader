local BD = require("ui/bidi")
local DataStorage = require("datastorage")
--local DownloadBackend = require("internaldownloadbackend")
--local DownloadBackend = require("luahttpdownloadbackend")
local DownloadBackend = require("epubdownloadbackend")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local dateparser = require("lib.dateparser")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local NewsDownloader = WidgetContainer:new{
    name = "news_downloader",
    initialized = false,
    feed_config_file = "feed_config.lua",
    feed_config_path = nil,
    news_config_file = "news_settings.lua",
    settings = nil,
    download_dir_name = "news",
    download_dir = nil,
    file_extension = ".epub",
    config_key_custom_dl_dir = "custom_dl_dir",
    kv = {}
}

local FEED_TYPE_RSS = "rss"
local FEED_TYPE_ATOM = "atom"

--local initialized = false
--local feed_config_file_name = "feed_config.lua"
--local news_downloader_config_file = "news_downloader_settings.lua

-- if a title looks like <title>blabla</title> it'll just be feed.title
-- if a title looks like <title attr="alb">blabla</title> then we get a table
-- where [1] is the title string and the attributes are also available
local function getFeedTitle(possible_title)
    if type(possible_title) == "string" then
        return util.htmlEntitiesToUtf8(possible_title)
    elseif possible_title[1] and type(possible_title[1]) == "string" then
        return util.htmlEntitiesToUtf8(possible_title[1])
    end
end

-- there can be multiple links
-- for now we just assume the first link is probably the right one
-- @todo write unit tests
-- some feeds that can be used for unit test
-- http://fransdejonge.com/feed/ for multiple links
-- https://github.com/koreader/koreader/commits/master.atom for single link with attributes
local function getFeedLink(possible_link)
    local E = {}
    if type(possible_link) == "string" then
        return possible_link
    elseif (possible_link._attr or E).href then
        return possible_link._attr.href
    elseif ((possible_link[1] or E)._attr or E).href then
        return possible_link[1]._attr.href
    end
end

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    menu_items.news_downloader = {
        text = _("News (RSS/Atom) downloader"),
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

function NewsDownloader:getSubMenuItems()
    self:lazyInitialization()
    local sub_item_table
    sub_item_table = {
        {
            text = _("Go to news folder"),
            callback = function()
                self:openDownloadsFolder()
            end,
        },
        {
            text = _("Download news feeds"),
            callback = function()
                NetworkMgr:runWhenOnline(function() self:loadConfigAndProcessFeedsWithUI() end)
            end,
        },
        {
            text = _("Remove all downloaded items"),
            keep_menu_open = true,
            callback = function() self:removeNewsButKeepFeedConfig() end,
        },
        {
            text = _("Settings"),
            sub_item_table = {
                {
                    text = _("Edit feeds configuration file"),
                    keep_menu_open = true,
                    callback = function() self:changeFeedConfig() end,
                },
                {
                    text = _("Set custom download folder"),
                    keep_menu_open = true,
                    callback = function() self:setCustomDownloadDirectory() end,
                },
                {
                    text = _("Never download images"),
                    keep_menu_open = true,
                    checked_func = function()
                        return self.settings:isTrue("never_download_images")
                    end,
                    callback = function()
                        self.settings:toggle("never_download_images")
                        self.settings:flush()
                    end,
                },
            },
        },
        {
            text = _("Help"),
            keep_menu_open = true,
            callback = function()
                UIManager:show(InfoMessage:new{
                                   text = T(_("News downloader retrieves RSS and Atom news entries and stores them to:\n%1\n\nEach entry is a separate html file, that can be browsed by KOReader file manager.\nItems download limit can be configured in Settings."),
                                            BD.dirpath(self.download_dir))
                })
            end,
        },
    }
    return sub_item_table
end
-- lazyInitialization sets up variables that point to the
-- downloads folder and the feeds configuration file
function NewsDownloader:lazyInitialization()
    if not self.initialized then
        logger.dbg("NewsDownloader: obtaining news folder")
        self.settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.news_config_file))
        -- Check to see if a custom download directory has been set
        if self.settings:has(self.config_key_custom_dl_dir) then
            self.download_dir = self.settings:readSetting(self.config_key_custom_dl_dir)
        else
            self.download_dir =
                ("%s/%s/"):format(
                    DataStorage:getFullDataDir(),
                    self.download_dir_name)
        end
        logger.dbg("NewsDownloader: Custom directory set to:", self.download_dir)
        -- If the directory doesn't exist we will create it
        if not lfs.attributes(self.download_dir, "mode") then
            logger.dbg("NewsDownloader: Creating initial directory")
            lfs.mkdir(self.download_dir)
        end
        -- Now set the path to the feed configuration file
        self.feed_config_path = self.download_dir .. self.feed_config_file
        -- If the configuration file doesn't exist create it
        if not lfs.attributes(self.feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial feed config.")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, self.feed_config_file),
                             self.feed_config_path)
        end
        self.initialized = true
    end
end

function NewsDownloader:loadConfigAndProcessFeeds()
    local UI = require("ui/trapper")
    UI:info("Loading news feed config…")
    logger.dbg("force repaint due to upcoming blocking calls")

    local ok, feed_config = pcall(dofile, self.feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end
    -- If the file contains no table elements, then the user hasn't set any feeds
    if #feed_config <= 0 then
        logger.err('NewsDownloader: empty feed list.', self.feed_config_path)
        -- TODO: Ask them to set the first feed. Perhaps even suggest something?!
        return
    end

    local never_download_images = self.settings:isTrue("never_download_images")
    local unsupported_feeds_urls = {}
    local total_feed_entries = #feed_config
    local feed_message

    for idx, feed in ipairs(feed_config) do
        local url = feed[1]
        local limit = feed.limit
        local download_full_article = feed.download_full_article == nil or feed.download_full_article
        local include_images = not never_download_images and feed.include_images
        local enable_filter = feed.enable_filter or feed.enable_filter == nil
        local filter_element = feed.filter_element or feed.filter_element == nil
        -- Check if the two required attributes are set
        if url and limit then
            feed_message = T(_("Processing %1/%2:\n%3"), idx, total_feed_entries, BD.url(url))
            UI:info(feed_message)
            -- Process, i.e.: "Download"
            self:processFeedSource(
                url,
                tonumber(limit),
                unsupported_feeds_urls,
                download_full_article,
                include_images,
                feed_message,
                enable_filter,
                filter_element)
        else
            logger.warn('NewsDownloader: invalid feed config entry.', feed)
        end
    end

    if #unsupported_feeds_urls <= 0 then
        -- When no errors are present, we get a happy message.
        feed_message = "Downloading news finished. "
    else
        -- When some errors are present, we get a sour message.
        local unsupported_urls = ""
        for key, value in pairs(unsupported_feeds_urls) do
            -- Create the error message
            unsupported_urls = unsupported_urls .. " " .. value[1] .. " " .. value[2]
            -- Not sure what this does
            if key ~= #unsupported_feeds_urls then
                unsupported_urls = BD.url(unsupported_urls) .. ", "
            end
        end
        -- Tell the user there were problems
        feed_message = "Downloading news finished with errors. "
        go_to_config_file = UI:confirm(
            T(
                [[
Could not process some feeds.
Unsupported format in: %1. Please
review your feed configuration file.]], unsupported_urls),
            "Continue",
            ""
        )
    end
    -- Clear the info widgets before displaying the confirm box
    UI:clear()
    -- Ask the user if they want to see their downloads
    feed_message = feed_message .. "Go to downloaders folder?"
    return_to_menu = UI:confirm(feed_message, "Go to downloads", "Close")

    if return_to_menu then
        NetworkMgr:afterWifiAction()
        return
    else
        -- Go to downloads folder
        UI:clear()
        self:openDownloadsFolder()
        NetworkMgr:afterWifiAction()
        return
    end
end

function NewsDownloader:loadConfigAndProcessFeedsWithUI()
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
            self:loadConfigAndProcessFeeds()
    end)
end

function NewsDownloader:processFeedSource(url, limit, unsupported_feeds_urls, download_full_article, include_images, message, enable_filter, filter_element)
    local ok, response = pcall(function()
            return DownloadBackend:getResponseAsString(url)
    end)
    local feeds
    -- Check to see if the response is OK to deserialize
    if ok then
        feeds = self:deserializeXMLString(response)
    end
    -- If the response is not OK, or feeds returned nil,
    -- add the URL to the unsupported feeds list
    if not ok or not feeds then
        local error_message
        if not ok then
            error_message = "(Reason: Failed to download content)"
        else
            error_message = "(Reason: Error during feed deserialization)"
        end
        table.insert(
            unsupported_feeds_urls,
            {
                url,
                error_message
            }
        )
        return
    end
    -- Check to see if the feed uses RSS
    local is_rss = feeds.rss
        and feeds.rss.channel
        and feeds.rss.channel.title
        and feeds.rss.channel.item
        and feeds.rss.channel.item[1]
        and feeds.rss.channel.item[1].title
        and feeds.rss.channel.item[1].link
    -- Check to see if the feed uses Atom
    local is_atom = feeds.feed
        and feeds.feed.title
        and feeds.feed.entry[1]
        and feeds.feed.entry[1].title
        and feeds.feed.entry[1].link
    -- Process the feeds accordingly.
    if is_atom then
        ok = pcall(function()
                return self:processFeed(
                    FEED_TYPE_ATOM,
                    feeds,
                    limit,
                    download_full_article,
                    include_images,
                    message,
                    enable_filter,
                    filter_element
                )
        end)
    elseif is_rss then
        ok = pcall(function()
                return self:processFeed(
                    FEED_TYPE_RSS,
                    feeds,
                    limit,
                    download_full_article,
                    include_images,
                    message,
                    enable_filter,
                    filter_element
                )
        end)
    end
    -- If the feed can't be processed, or it is neither
    -- Atom or RSS, then add it to the unsupported feeds list
    -- and return an error message
    if not ok or (not is_rss and not is_atom) then
        local error_message
        if not ok then
            error_message = "(Reason: Failed to download content)"
        elseif not is_rss then
            error_message = "(Reason: Couldn't process RSS)"
        elseif not is_atom then
            error_message = "(Reason: Couldn't process Atom)"
        end
        table.insert(
            unsupported_feeds_urls,
            {
                url,
                error_message
            }
        )
    end
end

function NewsDownloader:deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENSE_LuaXML
    local treehdl = require("lib/handler")
    local libxml = require("lib/xml")
    --Instantiate the object that states the XML file as a Lua table
    local xmlhandler = treehdl.simpleTreeHandler()
    --Instantiate the object that parses the XML to a Lua table
    local ok = pcall(function()
            libxml.xmlParser(xmlhandler):parse(xml_str)
    end)
    if not ok then return end
    return xmlhandler.root
end

function NewsDownloader:processAtom(feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
    -- Get the path to the output directory
    local feed_output_dir = string.format(
        "%s%s/",
        self.download_dir,
        util.getSafeFilename(getFeedTitle(feeds.feed.title))
    )
    -- Create the output directory if it doesn't exist
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end
    -- Download the feed
    for index, feed in pairs(feeds.feed.entry) do
        -- If limit has been met, stop downloading feed
        if limit ~= 0 and index - 1 == limit then
            break
        end
        local total_articles = limit == 0
            and #feeds.rss.channel.item
            or limit
        -- Create a message to display during the processing
        local article_message = T(
            _("%1\n\nFetching article %2/%3:"),
            message,
            index,
            total
        )
        -- Download the feed
        if download_full_article then
            self:downloadFeed(
                feed,
                feed_output_dir,
                include_images,
                article_message,
                enable_filter,
                filter_element
            )
        else
            self:createFromDescription(
                feed,
                feed.content[1],
                feed_output_dir,
                include_images,
                article_message
            )
        end
    end
end

function NewsDownloader:processFeed(feed_type, feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
    local feed_title
    local feed_item
    local total_feeds
    -- Setup the above vars based on feed type
    if feed_type == FEED_TYPE_RSS then
        feed_title = util.htmlEntitiesToUtf8(feeds.rss.channel.title)
        feed_item = feeds.rss.channel.item
        total_items = (limit == 0)
            and #feeds.rss.channel.item
            or limit
    else
        logger.dbg(feeds)
        feed_title = getFeedTitle(feeds.feed.title)
        feed_item = feeds.feed.entry
        total_items = (limit == 0)
            and #feeds.feed.entry
            or limit
    end
    -- Get the path to the output directory
    local feed_output_dir = ("%s%s/"):format(
        self.download_dir,
        util.getSafeFilename(util.htmlEntitiesToUtf8(feed_title)))
    -- Create the output directory if it doesn't exist
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end
    -- Download the feed
    for index, feed in pairs(feed_item) do
        -- If limit has been met, stop downloading feed
        if limit ~= 0 and index - 1 == limit then
            break
        end
        -- Create a message to display during the processing
        local article_message = T(
            _("%1\n\nFetching article %2/%3:"),
            message,
            index,
            total_items
        )
        -- Get the feed description
        local feed_description
        if feed_type == FEED_TYPE_RSS then
            feed_description = feed.description
        else
            feed_description = feed.summary
        end
        -- Download the article
        if download_full_article then
            self:downloadFeed(
                feed,
                feed_output_dir,
                include_images,
                article_message,
                enable_filter,
                filter_element
            )
        else
            self:createFromDescription(
                feed,
                feed_description,
                feed_output_dir,
                include_images,
                article_message
            )
        end
    end
end

local function parseDate(dateTime)
    -- uses lua-feedparser https://github.com/slact/lua-feedparser
    -- feedparser is available under the (new) BSD license.
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENCE_lua-feedparser
    local date = dateparser.parse(dateTime)
    return os.date("%y-%m-%d_%H-%M_", date)
end

-- This appears to be used by Atom feeds in processFeed
local function getTitleWithDate(feed)
    local title = util.getSafeFilename(getFeedTitle(feed.title))
    if feed.updated then
        title = parseDate(feed.updated) .. title
    elseif feed.pubDate then
        title = parseDate(feed.pubDate) .. title
    elseif feed.published then
        title = parseDate(feed.published) .. title
    end
    return title
end

function NewsDownloader:downloadFeed(feed, feed_output_dir, include_images, message, enable_filter, filter_element)
    local title_with_date = getTitleWithDate(feed)
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                             title_with_date,
                                             self.file_extension)

    local file_mode = lfs.attributes(news_file_path, "mode")
    if file_mode == "file" then
        logger.dbg("NewsDownloader:", news_file_path, "already exists. Skipping")
    else
        logger.dbg("NewsDownloader: News file will be stored to :", news_file_path)
        local article_message = T(_("%1\n%2"), message, title_with_date)
        local link = getFeedLink(feed.link)
        local html = DownloadBackend:loadPage(link)
        DownloadBackend:createEpub(news_file_path, html, link, include_images, article_message, enable_filter, filter_element)
    end
end

function NewsDownloader:createFromDescription(feed, content, feed_output_dir, include_images, message)
    local title_with_date = getTitleWithDate(feed)
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                             title_with_date,
                                             self.file_extension)
    local file_mode = lfs.attributes(news_file_path, "mode")
    if file_mode == "file" then
        logger.dbg("NewsDownloader:", news_file_path, "already exists. Skipping")
    else
        logger.dbg("NewsDownloader: News file will be stored to :", news_file_path)
        local article_message = T(_("%1\n%2"), message, title_with_date)
        local footer = _("This is just a description of the feed. To download the full article instead, go to the News Downloader settings and change 'download_full_article' to 'true'.")

        local html = string.format([[<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'><title>%s</title></head>
<body><header><h2>%s</h2></header><article>%s</article>
<br><footer><small>%s</small></footer>
</body>
</html>]], feed.title, feed.title, content, footer)
        local link = getFeedLink(feed.link)
        DownloadBackend:createEpub(news_file_path, html, link, include_images, article_message)
    end
end

function NewsDownloader:removeNewsButKeepFeedConfig()
    logger.dbg("NewsDownloader: Removing news from :", self.download_dir)
    for entry in lfs.dir(self.download_dir) do
        if entry ~= "." and entry ~= ".." and entry ~= self.feed_config_file then
            local entry_path = self.download_dir .. "/" .. entry
            local entry_mode = lfs.attributes(entry_path, "mode")
            if entry_mode == "file" then
                os.remove(entry_path)
            elseif entry_mode == "directory" then
                FFIUtil.purgeDir(entry_path)
            end
        end
    end
    UIManager:show(InfoMessage:new{
                       text = _("All news removed.")
    })
end

function NewsDownloader:setCustomDownloadDirectory()
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            logger.dbg("NewsDownloader: set download directory to: ", path)
            self.settings:saveSetting(self.config_key_custom_dl_dir, ("%s/"):format(path))
            self.settings:flush()

            logger.dbg("NewsDownloader: Coping to new download folder previous self.feed_config_file from: ", self.feed_config_path)
            FFIUtil.copyFile(self.feed_config_path, ("%s/%s"):format(path, self.feed_config_file))

            self.initialized = false
            self:lazyInitialization()
        end,
                                 }:chooseDir()
end

function NewsDownloader:editFeedUrl(url, id)
    -- How should this work?
    -- WEll, it needs to know where the url is 'coming from', which is to say,
    -- where in the config file it exists. we need an id, like, element 1, or element 3
end

function NewsDownloader:changeFeedConfig()
    local feed_config_file = io.open(self.feed_config_path, "rb")
    local config = feed_config_file:read("*all")
    feed_config_file:close()
    local config_editor
    config_editor = InputDialog:new{
        title = T(_("Config: %1"), BD.filepath(self.feed_config_path)),
        input = config,
        input_type = "string",
        para_direction_rtl = false, -- force LTR
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = function()
            return config
        end,
        save_callback = function(content)
            if content and #content > 0 then
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local syntax_okay, syntax_error = pcall(loadstring(content))
                    if syntax_okay then
                        feed_config_file = io.open(self.feed_config_path, "w")
                        feed_config_file:write(content)
                        feed_config_file:close()
                        return true, _("Configuration saved")
                    else
                        return false, T(_("Configuration invalid: %1"), syntax_error)
                    end
                else
                    return false, T(_("Configuration invalid: %1"), parse_error)
                end
            end
            return false, _("Configuration empty")
        end,
    }
    UIManager:show(config_editor)
    config_editor:onShowKeyboard()
end
function NewsDownloader:openDownloadsFolder()
    local FileManager = require("apps/filemanager/filemanager")
    if self.ui.document then
        self.ui:onClose()
    end
    if FileManager.instance then
        FileManager.instance:reinit(self.download_dir)
    else
        FileManager:showFiles(self.download_dir)
    end
end

function NewsDownloader:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and self.download_dir and self.download_dir == string.sub(document_full_path, 1, string.len(self.download_dir)) then
        logger.dbg("NewsDownloader: document_full_path:", document_full_path)
        logger.dbg("NewsDownloader: self.download_dir:", self.download_dir)
        logger.dbg("NewsDownloader: removing NewsDownloader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
        local doc_dir = util.splitFilePathName(document_full_path)
        self.ui:setLastDirForFileBrowser(doc_dir)
    end
end

--
-- KeyValuePage doesn't like to get a table with sub tables.
-- This function flattens an array, moving all nested tables
-- up the food chain, so to speak
--
function NewsDownloader:flattenArray(base_array, source_array)
    for key, value in pairs(source_array) do
        if value[2] == nil then
            -- If the value is empty, then it's probably supposed to be a line
            table.insert(
                base_array,
                "---"
            )
        else
            if value["callback"] then
                table.insert(
                    base_array,
                    {
                        value[1], value[2], callback = value["callback"]
                    }
                )
            else
                table.insert(
                    base_array,
                    {
                        value[1], value[2]
                    }
                )
            end
        end
    end
    return base_array
end

return NewsDownloader
