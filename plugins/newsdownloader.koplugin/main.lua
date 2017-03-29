local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local util = require("frontend/util")
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
local FEED_SOURCE_SUFFIX = "_rss_tmp.xml"
local NEWS_DL_DIR, FEED_CONFIG_PATH

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(menu_items)
    if not initialized then
        NEWS_DL_DIR = DataStorage:getDataDir() .. "/news/"
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
        text = _("Simple News(RSS/Atom) Downloader"),
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
                        text = T(_("Plugin reads feeds config file: %1, and downloads their news to: %2. News limit can be set. To set you own news sources edit feeds config file. Only RSS, Atom is currently not supported."),
                                 FEED_CONFIG_PATH,
                                 NEWS_DL_DIR)
                    })
                end,
            },
        },
    }
end

function NewsDownloader:loadConfigAndProcessFeeds()
    UIManager:show(InfoMessage:new{
        text = _("Loading data."),
        timeout = 1,
    })

    local feed_config = self:deserializeXML(FEED_CONFIG_PATH)
    if not feed_config then return end
    if not feed_config.feeds then
        logger.warn('NewsDownloader: missing feeds from feed config', FEED_CONFIG_PATH)
        return
    end

    for index, feed in pairs(feed_config.feeds.feed) do
        local url = feed[1]
        local limit = feed._attr.limit
        if url and limit then
            -- TODO: blocking UI loop?
            UIManager:show(InfoMessage:new{
                text = T(_("Processing: %1"), url),
                timeout = 2,
            })
            -- FIXME: delete tmp_source_file?
            local tmp_source_file = NEWS_DL_DIR .. index .. FEED_SOURCE_SUFFIX
            self:processFeedSource(url,
                                   tmp_source_file,
                                   tonumber(limit))
        else
            logger.warn('NewsDownloader: invalid feed config entry', feed)
        end
    end

    UIManager:show(InfoMessage:new{
      text = _("Downloading news finished.")
    })
end

function NewsDownloader:deserializeXML(filename)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    require("lib/xml")
    require("lib/handler")

    logger.dbg("NewsDownloader: File to deserialize: ", filename)
    local xmltext
    local f, e = io.open(filename, "r")
    if f then
        xmltext = f:read("*a")
        f:close()
    else
        logger.warn("NewsDownloader: XML file not found", filename, e)
        return nil
    end

    --Instantiate the object the states the XML file as a Lua table
    local xmlhandler = simpleTreeHandler()

    --Instantiate the object that parses the XML to a Lua table
    local xmlparser = xmlParser(xmlhandler)
    xmlparser:parse(xmltext)

    return xmlhandler.root
end

function NewsDownloader:processFeedSource(url, feed_source, limit)
    -- FIXME: this is very inefficient
    self:download(url, feed_source)
    local feeds = self:deserializeXML(feed_source)
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
        self:download(feed.link, news_dl_path)
    end
end

function NewsDownloader:download(url, output_file_name)
    http.request({
        url = url,
        sink = ltn12.sink.file(io.open(output_file_name, 'w')),
    })
end

return NewsDownloader
