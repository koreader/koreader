local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local util = require("util")
local T = FFIUtil.template
local _ = require("gettext")
local logger = require("logger")
local ffi = require("ffi")
local http = require("socket.http")
local ltn12 = require("ltn12")
local LuaSettings = require("frontend/luasettings")

local NewsDownloader = WidgetContainer:new{}

local initialized = false
local feed_config_file = "feed_config.lua"
local news_downloader_config_file = "news_downloader_settings.lua"
local config_key_custom_dl_dir = "custom_dl_dir";
local file_extension = ".html"
local news_download_dir_name = "news"
local news_download_dir_path, feed_config_path


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
                callback = function() self:loadConfigAndProcessFeeds() end,
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
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_("To change feed (Atom/RSS) sources please manually edit the configuration file:\n%1\n\nIt is very simple and contains comments as well as sample configuration."),
                                 feed_config_path)
                    })
                end,
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
            news_download_dir_path = ("%s/%s/"):format(DataStorage:getDataDir(), news_download_dir_name)
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

    for idx, feed in ipairs(feed_config) do
        local url = feed[1]
        local limit = feed.limit
        if url and limit then
            info = InfoMessage:new{ text = T(_("Processing: %1"), url) }
            UIManager:show(info)
            -- processFeedSource is a blocking call, so manually force a UI refresh beforehand
            UIManager:forceRePaint()
            self:processFeedSource(url, tonumber(limit), unsupported_feeds_urls)
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
end

function NewsDownloader:processFeedSource(url, limit, unsupported_feeds_urls)
    local resp_lines = {}
    http.request({ url = url, sink = ltn12.sink.table(resp_lines), })
    local feeds = self:deserializeXMLString(table.concat(resp_lines))
    if not feeds then
        table.insert(unsupported_feeds_urls, url)
        return
    end

    local is_rss = feeds.rss and feeds.rss.channel and feeds.rss.channel.title and feeds.rss.channel.item and feeds.rss.channel.item[1] and feeds.rss.channel.item[1].title and feeds.rss.channel.item[1].link
    local is_atom = feeds.feed and feeds.feed.title and feeds.feed.entry.title and feeds.feed.entry.link and feeds.feed.entry[1] and feeds.feed.entry[1].title and feeds.feed.entry[1].link

    if is_atom then
        self:processAtom(feeds, limit)
    elseif is_rss then
        self:processRSS(feeds, limit)
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

function NewsDownloader:processAtom(feeds, limit)
    local feed_output_dir = string.format("%s%s/",
                                          news_download_dir_path,
                                          util.replaceInvalidChars(feeds.feed.title))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.feed.entry) do
        if index -1 == limit then
            break
        end
        self:downloadFeed(feed, feed_output_dir)
    end
end

function NewsDownloader:processRSS(feeds, limit)
    local feed_output_dir = ("%s%s/"):format(
        news_download_dir_path, util.replaceInvalidChars(feeds.rss.channel.title))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.rss.channel.item) do
        if index -1 == limit then
            break
        end
        self:downloadFeed(feed, feed_output_dir)
    end
end

function NewsDownloader:downloadFeed(feed, feed_output_dir)

    local news_dl_path = ("%s%s%s"):format(feed_output_dir,
                                               util.replaceInvalidChars(feed.title),
                                               file_extension)
    logger.dbg("NewsDownloader: News file will be stored to :", news_dl_path)
    http.request({ url = feed.link, sink = ltn12.sink.file(io.open(news_dl_path, 'w')), })
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

return NewsDownloader
