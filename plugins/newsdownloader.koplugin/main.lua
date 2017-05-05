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


local NewsDownloader = WidgetContainer:new{}

local initialized = false  -- for only once lazy initialization
local feed_config_file = "feed_config.lua"
local file_extension = ".html"
local news_download_dir_name = "news"
local news_download_dir_path, feed_config_path

local function deserializeXMLString(xml_str)
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

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    if not initialized then
        news_download_dir_path = ("%s/%s/"):format(DataStorage:getDataDir(), news_download_dir_name)
        if not lfs.attributes(news_download_dir_path, "mode") then
            lfs.mkdir(news_download_dir_path)
        end
        feed_config_path = news_download_dir_path .. feed_config_file
        initialized = true
    end

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
                callback = function()
                    -- puerge all downloaded news files, but keep the feed config
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
                end,
            },
            {
                text = _("Help"),
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_("News downloader can be configured in the feeds config file:\n%1\n\nIt downloads news items to:\n%2.\n\nTo set you own news sources edit foregoing feeds config file. Items download limit can be set there."),
                                 feed_config_path,
                                 news_download_dir_path)
                    })
                end,
            },
        },
    }
end

function NewsDownloader:loadConfigAndProcessFeeds()
    local info = InfoMessage:new{ text = _("Loading news feed config…") }
    UIManager:show(info)
    -- force repaint due to upcoming blocking calls
    UIManager:forceRePaint()
    UIManager:close(info)

    if not lfs.attributes(feed_config_path, "mode") then
        logger.dbg("NewsDownloader: Creating initial feed config.")
        FFIUtil.copyFile(FFIUtil.joinPath(self.path, feed_config_file),
                         feed_config_path)
    end
    local ok, feed_config = pcall(dofile, feed_config_path)
    if not ok or not feed_config then
        logger.info("NewsDownloader: Feed config not found.")
        return
    end

    if #feed_config <= 0 then
        logger.info('NewsDownloader: empty feed list.', feed_config_path)
        return
    end

    local unsupported_feeds_urls = {};

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
            text = T(_("Downloading finished. Could not process some feeds. Unsupported format in: %1"), unsupported_urls)
        })
    end
end

function NewsDownloader:processFeedSource(url, limit, unsupported_feeds_urls)
    local resp_lines = {}
    http.request({ url = url, sink = ltn12.sink.table(resp_lines), })
    local feeds = deserializeXMLString(table.concat(resp_lines))
    if not feeds then
        table.insert(unsupported_feeds_urls, url)
        return
    end

    local is_rss = feeds.rss and feeds.rss.channel and feeds.rss.channel.title and feeds.rss.channel.item;
    local is_atom = feeds.feed and feeds.feed.title and feeds.feed.entry.title and feeds.feed.entry.link;

    if not is_rss and not is_atom then
        table.insert(unsupported_feeds_urls, url)
        return
    end

    if is_atom then
        self:processAtom(feeds, limit);
    else
        self:processRSS(feeds, limit);
    end
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
        self:commonFeedProcess(feed, feed_output_dir);
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
        self:commonFeedProcess(feed, feed_output_dir);
    end
end

function NewsDownloader:commonFeedProcess(feed, feed_output_dir)

    local news_dl_path = ("%s%s%s"):format(feed_output_dir,
                                               util.replaceInvalidChars(feed.title),
                                               file_extension)
    logger.dbg("NewsDownloader: News file will be stored to :", news_dl_path)
    http.request({ url = feed.link, sink = ltn12.sink.file(io.open(news_dl_path, 'w')), })
end

return NewsDownloader
