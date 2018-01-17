local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffi = require("ffi")
local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template

local NewsDownloader = WidgetContainer:new{}

local initialized = false
local wifi_enabled_before_action = true
local feed_config_file = "feed_config.lua"
local news_downloader_config_file = "news_downloader_settings.lua"
local config_key_custom_dl_dir = "custom_dl_dir";
local file_extension = ".html"
local news_download_dir_name = "news"
local news_download_dir_path, feed_config_path

-- if a title looks like <title>blabla</title> it'll just be feed.title
-- if a title looks like <title attr="alb">blabla</title> then we get a table
-- where [1] is the title string and the attributes are also available
local function getFeedTitle(possible_title)
    if type(possible_title) == "string" then
        return possible_title
    elseif possible_title[1] and type(possible_title[1]) == "string" then
        return possible_title[1]
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

-- TODO: implement as NetworkMgr:afterWifiAction with configuration options
function NewsDownloader:afterWifiAction()
    if not wifi_enabled_before_action then
        NetworkMgr:promptWifiOff()
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
                callback = function()
                    if not NetworkMgr:isOnline() then
                        wifi_enabled_before_action = false
                        NetworkMgr:beforeWifiAction(self.loadConfigAndProcessFeeds)
                    else
                        self:loadConfigAndProcessFeeds()
                    end
                end,
            },
            {
                text = _("Go to news folder"),
                callback = function()
                    local FileManager = require("apps/filemanager/filemanager")
                    if FileManager.instance then
                        FileManager.instance:reinit(news_download_dir_path)
                    else
                        FileManager:showFiles(news_download_dir_path)
                    end
                end,
            },
            {
                text = _("Remove news"),
                callback = function() self:removeNewsButKeepFeedConfig() end,
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
                                 news_download_dir_path)
                    })
                end,
            },
        },
    }
end

function NewsDownloader:lazyInitialization()
   if not initialized then
        logger.dbg("NewsDownloader: obtaining news folder")
        local news_downloader_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), news_downloader_config_file))
        if news_downloader_settings:has(config_key_custom_dl_dir) then
            news_download_dir_path = news_downloader_settings:readSetting(config_key_custom_dl_dir)
        else
            news_download_dir_path = ("%s/%s/"):format(DataStorage:getFullDataDir(), news_download_dir_name)
        end

        if not lfs.attributes(news_download_dir_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial directory")
            lfs.mkdir(news_download_dir_path)
        end
        feed_config_path = news_download_dir_path .. feed_config_file

        if not lfs.attributes(feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating initial feed config.")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, feed_config_file),
                         feed_config_path)
        end
        initialized = true
    end
end

function NewsDownloader:loadConfigAndProcessFeeds()
    local info = InfoMessage:new{ text = _("Loading news feed config…") }
    UIManager:show(info)
    logger.dbg("force repaint due to upcoming blocking calls")
    UIManager:forceRePaint()
    UIManager:close(info)

    local ok, feed_config = pcall(dofile, feed_config_path)
    if not ok or not feed_config then
        logger.error("NewsDownloader: Feed config not found.")
        return
    end

    if #feed_config <= 0 then
        logger.error('NewsDownloader: empty feed list.', feed_config_path)
        return
    end

    local unsupported_feeds_urls = {}

    local total_feed_entries = table.getn(feed_config)
    for idx, feed in ipairs(feed_config) do
        local url = feed[1]
        local limit = feed.limit
        local download_full_article = feed.download_full_article == nil or feed.download_full_article
        if url and limit then
            info = InfoMessage:new{ text = T(_("Processing %1/%2:\n%3"), idx, total_feed_entries, url) }
            UIManager:show(info)
            -- processFeedSource is a blocking call, so manually force a UI refresh beforehand
            UIManager:forceRePaint()
            NewsDownloader:processFeedSource(url, tonumber(limit), unsupported_feeds_urls, download_full_article)
            UIManager:close(info)
        else
            logger.warn('NewsDownloader: invalid feed config entry', feed)
        end
    end

    if #unsupported_feeds_urls <= 0 then
        UIManager:show(InfoMessage:new{
            text = _("Downloading news finished."),
            timeout = 1,
        })
    else
        local unsupported_urls = ""
        for k,url in pairs(unsupported_feeds_urls) do
            unsupported_urls = unsupported_urls .. url
            if k ~= #unsupported_feeds_urls then
                unsupported_urls = unsupported_urls .. ", "
            end
        end
        UIManager:show(InfoMessage:new{
            text = T(_("Downloading news finished. Could not process some feeds. Unsupported format in: %1"), unsupported_urls)
        })
    end
    NewsDownloader:afterWifiAction()
end

function NewsDownloader:processFeedSource(url, limit, unsupported_feeds_urls, download_full_article)
    local resp_lines = {}
    local parsed = socket_url.parse(url)
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    httpRequest({ url = url, sink = ltn12.sink.table(resp_lines), })
    local feeds = self:deserializeXMLString(table.concat(resp_lines))

    if not feeds then
        table.insert(unsupported_feeds_urls, url)
        return
    end

    local is_rss = feeds.rss and feeds.rss.channel and feeds.rss.channel.title and feeds.rss.channel.item and feeds.rss.channel.item[1] and feeds.rss.channel.item[1].title and feeds.rss.channel.item[1].link
    local is_atom = feeds.feed and feeds.feed.title and feeds.feed.entry[1] and feeds.feed.entry[1].title and feeds.feed.entry[1].link

    if is_atom then
        self:processAtom(feeds, limit, download_full_article)
    elseif is_rss then
        self:processRSS(feeds, limit, download_full_article)
    else
        table.insert(unsupported_feeds_urls, url)
        return
    end
end

function NewsDownloader:deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
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

function NewsDownloader:processAtom(feeds, limit, download_full_article)
    local feed_output_dir = string.format("%s%s/",
                                          news_download_dir_path,
                                          util.replaceInvalidChars(getFeedTitle(feeds.feed.title)))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.feed.entry) do
        if limit ~= 0 and index - 1 == limit then
            break
        end
        if download_full_article then
            self:downloadFeed(feed, feed_output_dir)
        else
            self:createFromDescription(feed, feed.context, feed_output_dir)
        end
    end
end

function NewsDownloader:processRSS(feeds, limit, download_full_article)
    local feed_output_dir = ("%s%s/"):format(
        news_download_dir_path, util.replaceInvalidChars(feeds.rss.channel.title))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.rss.channel.item) do
        if limit ~= 0 and index - 1 == limit then
            break
        end
        if download_full_article then
            self:downloadFeed(feed, feed_output_dir)
        else
            self:createFromDescription(feed, feed.description, feed_output_dir)
        end
    end
end

function NewsDownloader:downloadFeed(feed, feed_output_dir)
    local link = getFeedLink(feed.link)
    local news_dl_path = ("%s%s%s"):format(feed_output_dir,
                                               util.replaceInvalidChars(getFeedTitle(feed.title)),
                                               file_extension)
    logger.dbg("NewsDownloader: News file will be stored to :", news_dl_path)

    local parsed = socket_url.parse(link)
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    httpRequest({ url = link, sink = ltn12.sink.file(io.open(news_dl_path, 'w')), })
end

function NewsDownloader:createFromDescription(feed, context, feed_output_dir)
    local news_file_path = ("%s%s%s"):format(feed_output_dir,
                                           util.replaceInvalidChars(getFeedTitle(feed.title)),
                                           file_extension)
    logger.dbg("NewsDownloader: News file will be created :", news_file_path)
    local file = io.open(news_file_path, "w")
    local footer = _("This is just description of the feed. To download full article go to News Downloader settings and change 'download_full_article' to 'true'")

    local html = string.format([[<!DOCTYPE html>
<html>
<head><meta charset='UTF-8'><title>%s</title></head>
<body><header><h2>%s</h2></header><article>%s</article>
<br><footer><small>%s</small></footer>
</body>
</html>]], feed.title, feed.title, context, footer)
    file:write(html)
    file:close()
end

function NewsDownloader:removeNewsButKeepFeedConfig()
    logger.dbg("NewsDownloader: Removing news from :", news_download_dir_path)
    for entry in lfs.dir(news_download_dir_path) do
        if entry ~= "." and entry ~= ".." and entry ~= feed_config_file then
            local entry_path = news_download_dir_path .. "/" .. entry
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

function NewsDownloader:setCustomDownloadDirectory()
    UIManager:show(InfoMessage:new{
       text = _("To select a folder press down and hold it for 1 second.")
    })
    require("ui/downloadmgr"):new{
       title = _("Choose download directory"),
       onConfirm = function(path)
           logger.dbg("NewsDownloader: set download directory to: ", path)
           local news_downloader_settings = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), news_downloader_config_file))
           news_downloader_settings:saveSetting(config_key_custom_dl_dir, ("%s/"):format(path))
           news_downloader_settings:flush()

           logger.dbg("NewsDownloader: Coping to new download folder previous feed_config_file from: ", feed_config_path)
           FFIUtil.copyFile(feed_config_path, ("%s/%s"):format(path, feed_config_file))

           initialized = false
           self:lazyInitialization()
       end,
    }:chooseDir()
end

function NewsDownloader:onCloseDocument()
    local document_full_path = self.ui.document.file
    if  document_full_path and news_download_dir_path == string.sub(document_full_path, 1, string.len(news_download_dir_path)) then
        logger.dbg("NewsDownloader: document_full_path:", document_full_path)
        logger.dbg("NewsDownloader: news_download_dir_path:", news_download_dir_path)
        logger.dbg("NewsDownloader: removing NewsDownloader file from history.")
        ReadHistory:removeItemByPath(document_full_path)
    end
end

return NewsDownloader
