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

local config = require('newsConfig')


local NewsDownloader = WidgetContainer:new{}
local initialized = false  -- for only once lazy initialization
local news_dl_dir, feed_config_path

function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end

function NewsDownloader:addToMainMenu(tab_item_table)
    if not initialized then
        news_dl_dir = DataStorage:getDataDir() .. config.NEWS_DOWNLOAD_DIR
        if not lfs.attributes(news_dl_dir, "mode") then
            lfs.mkdir(news_dl_dir)
        end

        feed_config_path = news_dl_dir .. config.FEED_CONFIG_FILE
        if not lfs.attributes(feed_config_path, "mode") then
            logger.dbg("NewsDownloader: Creating init configuration")
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, config.FEED_CONFIG_FILE),
                             feed_config_path)
        end
        initialized = true
    end

    table.insert(tab_item_table.plugins, {
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
                        FileManager.instance:reinit(news_dl_dir)
                    else
                        FileManager:showFiles(news_dl_dir)
                    end
                end,
            },
            {
                text = _("Remove news"),
                callback = function()
                    local feed_config_file = config.FEED_CONFIG_FILE
                    -- puerge all downloaded news files, but keep the feed config
                    for entry in lfs.dir(news_dl_dir) do
                        if entry ~= "." and entry ~= ".." and entry ~= feed_config_file then
                            local entry_path = news_dl_dir .. "/" .. entry
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
                                 feed_config_path,
                                 news_dl_dir)
                    })
                end,
            },
        },
    })
end

function NewsDownloader:loadConfigAndProcessFeeds()
    UIManager:show(InfoMessage:new{
        text = _("Loading data.") ,
        timeout = 1,
    })

    local feed_config = self:deserializeXML(feed_config_path)

    for index, feed in pairs(feed_config.feeds.feed) do
        -- FIXME: validation
        local url = feed[1]
        -- TODO: blocking UI loop?
        UIManager:show(InfoMessage:new{
            text = T(_("Processing: %1"), url),
            timeout = 2,
        })
        -- FIXME: delete tmp_source_file?
        local tmp_source_file = news_dl_dir .. index .. config.FEED_SOURCE_SUFFIX
        self:processFeedSource(url,
                               tmp_source_file,
                               tonumber(feed._attr.limit))
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

    logger.dbg("NewsDownloader: Filename to deserialize: ", filename)
    local xmltext
    local f, e = io.open(filename, "r")
    if f then
        --Gets the entire file content and stores into a string
        xmltext = f:read("*a")
    else
        -- FIXME: don't crash the whole reader
        error(e)
    end

    --Instantiate the object the states the XML file as a Lua table
    local xmlhandler = simpleTreeHandler() -- luacheck: ignore

    --Instantiate the object that parses the XML to a Lua table
    local xmlparser = xmlParser(xmlhandler) -- luacheck: ignore
    xmlparser:parse(xmltext)

    return xmlhandler.root
end

function NewsDownloader:processFeedSource(url, feed_source, limit)
    -- FIXME: this is very inefficient
    self:download(url, feed_source)
    local feeds = self:deserializeXML(feed_source)
    -- TODO: validate feeds
    local feed_output_dir = string.format("%s%s/",
                                          news_dl_dir,
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
                                           config.FILE_EXTENSION)
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
