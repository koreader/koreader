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
    name = "newsdownloader",
}

local initialized = false
local feed_config_file_name = "feed_config.lua"
local news_downloader_config_file = "news_downloader_settings.lua"
local news_downloader_settings
local config_key_custom_dl_dir = "custom_dl_dir"
local file_extension = ".epub"
local news_download_dir_name = "news"
local news_download_dir_path, feed_config_path

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
    self:lazyInitialization()
    menu_items.news_downloader = {
        text = _("News (RSS/Atom) downloader"),
        sub_item_table = {
            {
                text = _("Download news"),
                keep_menu_open = true,
                callback = function()
                    NetworkMgr:runWhenOnline(function() self:loadConfigAndProcessFeedsWithUI() end)
                end,
            },
            {
                text = _("Go to news folder"),
                callback = function()
                    local FileManager = require("apps/filemanager/filemanager")
                    if self.ui.document then
                        self.ui:onClose()
                    end
                    if FileManager.instance then
                        FileManager.instance:reinit(news_download_dir_path)
                    else
                        FileManager:showFiles(news_download_dir_path)
                    end
                end,
            },
            {
                text = _("Remove news"),
                keep_menu_open = true,
                callback = function() self:removeNewsButKeepFeedConfig() end,
            },
            {
                text = _("Never download images"),
                keep_menu_open = true,
                checked_func = function()
                    return news_downloader_settings:isTrue("never_download_images")
                end,
                callback = function()
                    news_downloader_settings:toggle("never_download_images")
                    news_downloader_settings:flush()
                end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Change feeds configuration"),
                        keep_menu_open = true,
                        callback = function() self:changeFeedConfig() end,
                    },
                    {
                        text = _("Set custom download folder"),
                        keep_menu_open = true,
                        callback = function() self:setCustomDownloadDirectory() end,
                    },
                },
            },
            {
                text = _("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_("News downloader retrieves RSS and Atom news entries and stores them to:\n%1\n\nEach entry is a separate html file, that can be browsed by KOReader file manager.\nItems download limit can be configured in Settings."),
                                 BD.dirpath(news_download_dir_path))
                    })
                end,
            },
        },
    }
end

function NewsDownloader:lazyInitialization()
   if not initialized then
        logger.dbg("NewsDownloader: obtaining news folder")
        news_downloader_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), news_downloader_config_file))
        if news_downloader_settings:has(config_key_custom_dl_dir) then
            news_download_dir_path = news_downloader_settings:readSetting(config_key_custom_dl_dir)
        else
            news_download_dir_path = ("%s/%s/"):format(DataStorage:getFullDataDir(), news_download_dir_name)
        end

        if not lfs.attributes(news_download_dir_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial directory")
            lfs.mkdir(news_download_dir_path)
        end
        feed_config_path = news_download_dir_path .. feed_config_file_name

        if not lfs.attributes(feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial feed config.")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, feed_config_file_name),
                         feed_config_path)
        end
        initialized = true
    end
end

function NewsDownloader:loadConfigAndProcessFeeds()
    local UI = require("ui/trapper")
    UI:info("Loading news feed config…")
    logger.dbg("force repaint due to upcoming blocking calls")

    local ok, feed_config = pcall(dofile, feed_config_path)
    if not ok or not feed_config then
        UI:info(T(_("Invalid configuration file. Detailed error message:\n%1"), feed_config))
        return
    end

    if #feed_config <= 0 then
        logger.err('NewsDownloader: empty feed list.', feed_config_path)
        return
    end

    local never_download_images = news_downloader_settings:isTrue("never_download_images")

    local unsupported_feeds_urls = {}

    local total_feed_entries = #feed_config
    for idx, feed in ipairs(feed_config) do
        local url = feed[1]
        local limit = feed.limit
        local download_full_article = feed.download_full_article == nil or feed.download_full_article
        local include_images = not never_download_images and feed.include_images
        local enable_filter = feed.enable_filter or feed.enable_filter == nil
        local filter_element = feed.filter_element or feed.filter_element == nil
        if url and limit then
            local feed_message = T(_("Processing %1/%2:\n%3"), idx, total_feed_entries, BD.url(url))
            UI:info(feed_message)
            NewsDownloader:processFeedSource(url, tonumber(limit), unsupported_feeds_urls, download_full_article, include_images, feed_message, enable_filter, filter_element)
        else
            logger.warn('NewsDownloader: invalid feed config entry', feed)
        end
    end

    if #unsupported_feeds_urls <= 0 then
        UI:info("Downloading news finished.")
    else
        local unsupported_urls = ""
        for k,url in pairs(unsupported_feeds_urls) do
            unsupported_urls = unsupported_urls .. url
            if k ~= #unsupported_feeds_urls then
                unsupported_urls = BD.url(unsupported_urls) .. ", "
            end
        end
        UI:info(T(_("Downloading news finished. Could not process some feeds. Unsupported format in: %1"), unsupported_urls))
    end
    NetworkMgr:afterWifiAction()
end

function NewsDownloader:loadConfigAndProcessFeedsWithUI()
    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        self.loadConfigAndProcessFeeds()
    end)
end

function NewsDownloader:processFeedSource(url, limit, unsupported_feeds_urls, download_full_article, include_images, message, enable_filter, filter_element)

    local ok, response = pcall(function()
        return DownloadBackend:getResponseAsString(url)
    end)
    local feeds
    if ok then
        feeds = self:deserializeXMLString(response)
    end

    if not ok or not feeds then
        table.insert(unsupported_feeds_urls, url)
        return
    end

    local is_rss = feeds.rss and feeds.rss.channel and feeds.rss.channel.title and feeds.rss.channel.item and feeds.rss.channel.item[1] and feeds.rss.channel.item[1].title and feeds.rss.channel.item[1].link
    local is_atom = feeds.feed and feeds.feed.title and feeds.feed.entry[1] and feeds.feed.entry[1].title and feeds.feed.entry[1].link

    if is_atom then
        ok = pcall(function()
            return self:processAtom(feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
        end)
    elseif is_rss then
        ok = pcall(function()
            return self:processRSS(feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
        end)
    end
    if not ok or (not is_rss and not is_atom) then
        table.insert(unsupported_feeds_urls, url)
    end
end

function NewsDownloader:deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENSE_LuaXML
    local treehdl = require("lib/handler")
    local libxml = require("lib/xml")

    --Instantiate the object the states the XML file as a Lua table
    local xmlhandler = treehdl.simpleTreeHandler()
    --Instantiate the object that parses the XML to a Lua table
    local ok = pcall(function()
        libxml.xmlParser(xmlhandler):parse(xml_str)
    end)
    if not ok then return end
    return xmlhandler.root
end

function NewsDownloader:processAtom(feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
    local feed_output_dir = string.format("%s%s/",
                                          news_download_dir_path,
                                          util.getSafeFilename(getFeedTitle(feeds.feed.title)))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.feed.entry) do
        if limit ~= 0 and index - 1 == limit then
            break
        end
        local article_message = T(_("%1\n\nFetching article %2/%3:"), message, index, limit == 0 and #feeds.rss.channel.item or limit)
        if download_full_article then
            self:downloadFeed(feed, feed_output_dir, include_images, article_message, enable_filter, filter_element)
        else
            self:createFromDescription(feed, feed.content[1], feed_output_dir, include_images, article_message)
        end
    end
end

function NewsDownloader:processRSS(feeds, limit, download_full_article, include_images, message, enable_filter, filter_element)
    local feed_output_dir = ("%s%s/"):format(
        news_download_dir_path, util.getSafeFilename(util.htmlEntitiesToUtf8(feeds.rss.channel.title)))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.rss.channel.item) do
        if limit ~= 0 and index - 1 == limit then
            break
        end
        local article_message = T(_("%1\n\nFetching article %2/%3:"), message, index, limit == 0 and #feeds.rss.channel.item or limit)
        if download_full_article then
            self:downloadFeed(feed, feed_output_dir, include_images, article_message, enable_filter, filter_element)
        else
            self:createFromDescription(feed, feed.description, feed_output_dir, include_images, article_message)
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
                                             file_extension)

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
                                             file_extension)
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
    logger.dbg("NewsDownloader: Removing news from :", news_download_dir_path)
    for entry in lfs.dir(news_download_dir_path) do
        if entry ~= "." and entry ~= ".." and entry ~= feed_config_file_name then
            local entry_path = news_download_dir_path .. "/" .. entry
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
           news_downloader_settings:saveSetting(config_key_custom_dl_dir, ("%s/"):format(path))
           news_downloader_settings:flush()

           logger.dbg("NewsDownloader: Coping to new download folder previous feed_config_file_name from: ", feed_config_path)
           FFIUtil.copyFile(feed_config_path, ("%s/%s"):format(path, feed_config_file_name))

           initialized = false
           self:lazyInitialization()
       end,
    }:chooseDir()
end

function NewsDownloader:changeFeedConfig()
    local feed_config_file = io.open(feed_config_path, "rb")
    local config = feed_config_file:read("*all")
    feed_config_file:close()
    local config_editor
    config_editor = InputDialog:new{
        title = T(_("Config: %1"), BD.filepath(feed_config_path)),
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
                        feed_config_file = io.open(feed_config_path, "w")
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

function NewsDownloader:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and news_download_dir_path and news_download_dir_path == string.sub(document_full_path, 1, string.len(news_download_dir_path)) then
        logger.dbg("NewsDownloader: document_full_path:", document_full_path)
        logger.dbg("NewsDownloader: news_download_dir_path:", news_download_dir_path)
        logger.dbg("NewsDownloader: removing NewsDownloader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
        local doc_dir = util.splitFilePathName(document_full_path)
        self.ui:setLastDirForFileBrowser(doc_dir)
    end
end

return NewsDownloader
