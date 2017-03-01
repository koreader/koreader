local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local _ = require("gettext")

require("lib/xml")
require("lib/handler")

local config = require('newsConfig');


local NewsDownloader = InputContainer:new{}


function NewsDownloader:init()
    self.ui.menu:registerToMainMenu(self)
end


function NewsDownloader:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Simple News(RSS/Atom) Downloader"),
        sub_item_table = {
            {
                text = _("Download news"),
                callback = function() self:loadNewsSources() end,
            },
            {
                text = _("Clean news folder"),
                callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _("Not implemented yet."),
                        })
                end,
            },
            {
                text = _("Help"),
                callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _("Script uses config from feed.xml to download feeds to Koreader/News directory"),
                        })
                end,
            },
        },
    })
end

function NewsDownloader:loadNewsSources()
    UIManager:show(InfoMessage:new{
          text = _("Loading data.") ,
          timeout = 2,
    })
    local feedfileName = self:getFeedXmlPath();
    
    local feedSources = self:deserializeXML(feedfileName);

    for index, url in pairs(feedSources.feeds.feed) do
        UIManager:show(InfoMessage:new{
              text = _("Processing: ") .. url,
              timeout = 3,
          })
        local nameSuffix = config.FEED_SOURCE_SUFFIX;
        local dirprefix = config.NEWS_DOWNLOAD_DIR 
        local filename = dirprefix .. index .. nameSuffix;
        
        self:processFeedSource(url, filename)
    end 
    
    UIManager:show(InfoMessage:new{
      text = _("Downloading News Finished"),
      timeout = 2,
    })

end

function NewsDownloader:getFeedXmlPath()
    
    local feedfileName = config.FEED_FILE_NAME;
    return self:script_path() .. feedfileName;
end

function NewsDownloader:script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

function NewsDownloader:deserializeXML(filename)
  DEBUG("filename to deserialize: ", filename)
  local xmltext = ""
  local f, e = io.open(filename, "r")
  if f then
    --Gets the entire file content and stores into a string
    xmltext = f:read("*a")
  else
    error(e)
  end
  
  --Instantiate the object the states the XML file as a Lua table
  local xmlhandler = simpleTreeHandler()
  
  --Instantiate the object that parses the XML to a Lua table
  local xmlparser = xmlParser(xmlhandler)
  xmlparser:parse(xmltext)

  return xmlhandler.root;
end



function NewsDownloader:processFeedSource(url,filename)
   
   self:download(url,filename)
   local feeds = self:deserializeXML(filename);
   
   for index, feed in pairs(feeds.rss.channel.item) do
        local util = require("frontend/util")
        local title = util.replaceInvalidChars(feed.title)
    
        title = config.NEWS_DOWNLOAD_DIR ..title .. config.FILE_EXTENSION; 
        DEBUG(title)
        self:download(feed.link, title)
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


return NewsDownloader
