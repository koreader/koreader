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
local FEED_CONFIG_FILE = "feeds.xml"
local FILE_EXTENSION = ".html"
local NEWS_DL_DIR_NAME = "news"
local NEWS_DL_DIR, FEED_CONFIG_PATH

local function deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    local treehdl = require("lib/handler")
    local libxml = require("lib/xml")

    --Instantiate the object the states the XML file as a Lua table
    local xmlhandler = treehdl.simpleTreeHandler()
    --Instantiate the object that parses the XML to a Lua table
    libxml.xmlParser(xmlhandler):parse(xml_str)
    return xmlhandler.root
end

local function deserializeXML(filename)
    logger.dbg("NewsDownloader: File to deserialize: ", filename)
    local f, e = io.open(filename, "r")
    if f then
        local xmltext = f:read("*a")
        f:close()
        return deserializeXMLString(xmltext)
    else
        logger.warn("NewsDownloader: XML file not found", filename, e)
    end
end

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    if not initialized then
        NEWS_DL_DIR = string.format("%s/%s/", DataStorage:getDataDir(), NEWS_DL_DIR_NAME)
        if not lfs.attributes(NEWS_DL_DIR, "mode") then
            lfs.mkdir(NEWS_DL_DIR)
        end

        FEED_CONFIG_PATH = NEWS_DL_DIR .. FEED_CONFIG_FILE
        if not lfs.attributes(FEED_CONFIG_PATH, "mode") then
            logger.dbg("NewsDownloader: Creating init configuration")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, FEED_CONFIG_FILE),
                             FEED_CONFIG_PATH)
        end
        initialized = true
    end

    menu_items.rss_news_downloader = {
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
                        FileManager.instance:reinit(NEWS_DL_DIR)
                    else
                        FileManager:showFiles(NEWS_DL_DIR)
                    end
                end,
            },
            {
                text = _("Remove news"),
                callback = function()
                    -- puerge all downloaded news files, but keep the feed config
                    for entry in lfs.dir(NEWS_DL_DIR) do
                        if entry ~= "." and entry ~= ".." and entry ~= FEED_CONFIG_FILE then
                            local entry_path = NEWS_DL_DIR .. "/" .. entry
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
                                 FEED_CONFIG_PATH,
                                 NEWS_DL_DIR)
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

    local feed_config = deserializeXML(FEED_CONFIG_PATH)
    if not feed_config then return end
    if not feed_config.feeds then
        logger.warn('NewsDownloader: missing feeds from feed config', FEED_CONFIG_PATH)
        return
    end

    for index, feed in pairs(feed_config.feeds.feed) do
        local url = feed[1]
        local limit = feed._attr.limit
        if url and limit then
            info = InfoMessage:new{ text = T(_("Processing: %1"), url) }
            UIManager:show(info)
            -- processFeedSource is a blocking call, so manually force a UI refresh beforehand
            UIManager:forceRePaint()
            self:processFeedSource(url, tonumber(limit))
            UIManager:close(info)
        else
            logger.warn('NewsDownloader: invalid feed config entry', feed)
        end
    end

    UIManager:show(InfoMessage:new{
        text = _("Downloading news finished."),
        timeout = 1,
    })
end

function NewsDownloader:processFeedSource(url, limit)
    local resp_lines = {}
    http.request({ url = url, sink = ltn12.sink.table(resp_lines), })
    local feeds = deserializeXMLString(table.concat(resp_lines))
    if not feeds then return end
    if not feeds.rss or not feeds.rss.channel
            or not feeds.rss.channel.title or not feeds.rss.channel.item then
        logger.info('NewsDownloader: Got invalid feeds', feeds)
        return
    end

    local feed_output_dir = string.format("%s%s/",
                                          NEWS_DL_DIR,
                                          util.replaceInvalidChars(feeds.rss.channel.title))
    if not lfs.attributes(feed_output_dir, "mode") then
        lfs.mkdir(feed_output_dir)
    end

    for index, feed in pairs(feeds.rss.channel.item) do
        if index -1 == limit then
            break
        end
        local news_dl_path = string.format("%s%s%s",
                                           feed_output_dir,
                                           util.replaceInvalidChars(feed.title),
                                           FILE_EXTENSION)
        logger.dbg("NewsDownloader: News file will be stored to :", news_dl_path)
        http.request({ url = url, sink = ltn12.sink.file(io.open(news_dl_path, 'w')), })
    end
end

return NewsDownloader
