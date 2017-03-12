local InputContainer = require("ui/widget/container/inputcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local DataStorage = require("datastorage")
local _ = require("gettext")
local FileManager = require("apps/filemanager/filemanager")
  
local config = require('newsConfig');


local NewsDownloader = InputContainer:new{}


function NewsDownloader:init()
	lfs.mkdir(self:getNewsDirPath());
    self.ui.menu:registerToMainMenu(self)
end


function NewsDownloader:addToMainMenu(tab_item_table)
    table.insert(tab_item_table.plugins, {
        text = _("Simple News(RSS/Atom) Downloader"),
        sub_item_table = {
            {
                text = _("Download news"),
                callback = function() self:loadNewsSources(); end,
            },
                        {
                text = _("Go to news folder"),
                callback = function()
                		 FileManager:showFiles(self:getNewsDirPath());
                end,
            },
            {
                text = _("Clean news folder"),
                callback = function()
                		self:clearNewsDir();
                        UIManager:show(InfoMessage:new{
                            text = _("Cleared news directory.")
                        })
                end,
            },
            {
                text = _("Help"),
                callback = function()
                        UIManager:show(InfoMessage:new{
                            text = _("Script uses config from " .. self:getNewsDirPath() .. config.FEED_FILE_NAME .. " to download feeds to " .. self:getNewsDirPath() .. " directory"),
                        })
                end,
            },
        },
    })
end

function NewsDownloader:loadNewsSources()
    UIManager:show(InfoMessage:new{
          text = _("Loading data.") ,
          timeout = 1,
    })
    local feedfileName = self:getFeedXmlPath();

    local feedSources = self:deserializeXML(feedfileName);

    for index, data in pairs(feedSources.feeds.feed) do
    	local url = data[1];
    	UIManager:show(InfoMessage:new{
              text = _("Processing: ") .. url,
              timeout = 3,
        });
        
    	local limitString = data._attr.limit;
    	local limit;
    	if limitString then
    		limit = tonumber(limitString);
    	end 
    	
        
        local nameSuffix = config.FEED_SOURCE_SUFFIX;
        local newsDirPath = self:getNewsDirPath();
        local newsSourceFilePath = newsDirPath .. index .. nameSuffix;

        self:processFeedSource(url, newsSourceFilePath, limit);
    end

    UIManager:show(InfoMessage:new{
      text = _("Downloading News Finished")
    })

end

function NewsDownloader:getFeedXmlPath()
	local newsDirPath = self:getNewsDirPath();
    local feedfileName = config.FEED_FILE_NAME;
    local feedXmlPath = newsDirPath.. feedfileName;
    DEBUG(feedXmlPath);
    return feedXmlPath;
end

function NewsDownloader:getNewsDirPath() 
	local baseDirPath = DataStorage:getDataDir() 
	local newsDirName = config.NEWS_DOWNLOAD_DIR;
	local newsDirPath = baseDirPath .. newsDirName;
	return newsDirPath;
end

function NewsDownloader:deserializeXML(filename)
  -- uses LuaXML https://github.com/manoelcampos/LuaXML
  -- The MIT License (MIT)
  -- Copyright (c) 2016 Manoel Campos da Silva Filho
  require("lib/xml")
  require("lib/handler")

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



function NewsDownloader:processFeedSource(url,feedSource, limit)

   self:download(url,feedSource)
   local feeds = self:deserializeXML(feedSource);

   for index, feed in pairs(feeds.rss.channel.item) do
   		if limit > 0 and limit < index then
   			break;
   		end 
        local util = require("frontend/util");
        local title = util.replaceInvalidChars(feed.title);
		local newsFilePath = self:getNewsDirPath() .. title .. config.FILE_EXTENSION;
        DEBUG(newsFilePath)
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
                
function NewsDownloader:clearNewsDir() 
	local newsDir = self:getNewsDirPath();
	self:removeAllExceptFeedConfig(newsDir);
end


function NewsDownloader:removeAllExceptFeedConfig(dir, rmdir)
	local ffi = require("ffi");
	
	require("ffi/zeromq_h")
	    for f in lfs.dir(dir) do
			local feedConfigFile = config.FEED_FILE_NAME;
			
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
