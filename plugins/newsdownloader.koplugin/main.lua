local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local FileManager = require("apps/filemanager/filemanager")
local FFIUtil = require("ffi/util")
local util = require("frontend/util")
local T = FFIUtil.template
local _ = require("gettext")
local logger = require("logger")

local config = require('newsConfig')


local NewsDownloader = WidgetContainer:new{}


function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
    local feedConfigFilePath = self:getFeedConfigPath()
    if not lfs.attributes(feedConfigFilePath, "mode") ~= "file" then
      logger.dbg("NewsDownloader: Creating init configuration")
      local newsDir = self:getNewsDirPath()
      lfs.mkdir(newsDir)
      FFIUtil.copyFile(FFIUtil.joinPath(self.path, config.FEED_FILE_NAME),
                       feedConfigFilePath)
    end
end

function NewsDownloader:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Simple News(RSS/Atom) Downloader"),
        sub_item_table = {
            {
                text = _("Download news"),
                callback = function() self:loadConfigAndProcessFeeds(); end,
            },
            {
                text = _("Go to news folder"),
                callback = function()
                    if FileManager.instance then
                        FileManager.instance:reinit(self:getNewsDirPath())
                    else
                        FileManager:showFiles(self:getNewsDirPath())
                    end
                end,
            },
            {
                text = _("Remove news"),
                callback = function()
                    self:clearNewsDir()
                    UIManager:show(InfoMessage:new{
                        text = _("News removed.")
                    })
                end,
            },
            {
                text = _("Help"),
                callback = function()
                        UIManager:show(InfoMessage:new{
                            text = T(_("Plugin reads feeds config file: %1, and downloads their news to: %2. News limit can be set. To set you own news sources edit feeds config file. Only RSS, Atom is currently not supported."),
                                     self:getFeedConfigPath(),
                                     self:getNewsDirPath())
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

    local feedConfigFilePath = self:getFeedConfigPath()
    logger.dbg("NewsDownloader: Configuration file: ", feedConfigFilePath)

    local feedConfig = self:deserializeXML(feedConfigFilePath)

    for index, feed in pairs(feedConfig.feeds.feed) do
        local url = feed[1]
        UIManager:show(InfoMessage:new{
            text = T(_("Processing: %1"), url),
            timeout = 2,
        })

        local feedSourceTmpFilePath = self:createFeedSourceTmpFilePath(index)

        local downloadLimit = tonumber(feed._attr.limit)

        self:processFeedSource(url, feedSourceTmpFilePath, downloadLimit)
    end

    UIManager:show(InfoMessage:new{
      text = _("Downloading news finished.")
    })
end

function NewsDownloader:getFeedConfigPath()
    local newsDirPath = self:getNewsDirPath()
    local feedfileName = config.FEED_FILE_NAME
    local feedXmlPath = newsDirPath.. feedfileName
    return feedXmlPath
end

function NewsDownloader:createFeedSourceTmpFilePath(index)
    local nameSuffix = config.FEED_SOURCE_SUFFIX
    local newsDirPath = self:getNewsDirPath()
    local feedSourceTmpFilePath = newsDirPath .. index .. nameSuffix
    return feedSourceTmpFilePath
end

function NewsDownloader:getNewsDirPath()
    local baseDirPath = DataStorage:getDataDir()
    local newsDirName = config.NEWS_DOWNLOAD_DIR
    local newsDirPath = baseDirPath .. newsDirName
    return newsDirPath
end

function NewsDownloader:deserializeXML(filename)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    require("lib/xml")
    require("lib/handler")

    logger.dbg("NewsDownloader: Filename to deserialize: ", filename)
    local xmltext = ""
    local f, e = io.open(filename, "r")
    if f then
        --Gets the entire file content and stores into a string
        xmltext = f:read("*a")
    else
        error(e)
    end

    --Instantiate the object the states the XML file as a Lua table
    local xmlhandler = simpleTreeHandler() -- luacheck: ignore

    --Instantiate the object that parses the XML to a Lua table
    local xmlparser = xmlParser(xmlhandler) -- luacheck: ignore
    xmlparser:parse(xmltext)

    return xmlhandler.root
end

function NewsDownloader:processFeedSource(url,feedSource, limit)
    self:download(url,feedSource)
    local feeds = self:deserializeXML(feedSource)

    local feedOutputDirPath = self:createValidFeedOutputDirPath(feeds)
    lfs.mkdir(feedOutputDirPath)

    for index, feed in pairs(feeds.rss.channel.item) do
        if index -1 == limit then
            break
        end

        local newsTitle = util.replaceInvalidChars(feed.title)

        local newsFilePath = feedOutputDirPath .. newsTitle .. config.FILE_EXTENSION
        logger.dbg("NewsDownloader: News file will be stored to :", newsFilePath)
        self:download(feed.link, newsFilePath)
    end
end


function NewsDownloader:download(url,outputFilename)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local file = ltn12.sink.file(io.open(outputFilename, 'w'))
    http.request {
        url = url,
        sink = file,
    }
end

function NewsDownloader:createValidFeedOutputDirPath(feeds)
   local feedDir = util.replaceInvalidChars(feeds.rss.channel.title) .. "/"
   local feedOutputDirPath = self:getNewsDirPath() .. feedDir
   return feedOutputDirPath
end

function NewsDownloader:clearNewsDir()
    local newsDir = self:getNewsDirPath()
    self:removeAllExceptFeedConfig(newsDir)
end

function NewsDownloader:removeAllExceptFeedConfig(dir, rmdir)
    local ffi = require("ffi")
    for f in lfs.dir(dir) do
        local feedConfigFile = config.FEED_FILE_NAME
        local path = dir.."/"..f
        local mode = lfs.attributes(path, "mode")
        if mode == "file" and f ~= feedConfigFile then
            ffi.C.remove(path)
        elseif mode == "directory" and f ~= "." and f ~= ".." then
            self:removeAllExceptFeedConfig(path, true)
        end
    end
    if rmdir then
        ffi.C.rmdir(dir)
    end
end

return NewsDownloader
