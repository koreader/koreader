local util = require("frontend/util")

local Subscription = require("subscription/subscription")
local FeedFactory = require("feed/feedfactory")
local socket_url = require("socket.url")
local DataStorage = require("datastorage")
local GazetteMessages = require("gazettemessages")
local Results = require("subscription/result/results")

Feed = Subscription:new{
   subscription_type = "feed",
   url = nil,
   limit = 3,
   include_images = false, -- not implemented
   enabled_filter = false, -- not implemented
   filter_element = nil, -- not implemented
   download_directory = nil,
   content_source = nil,
}

Feed.CONTENT_SOURCE = {
   SUMMARY = "summary",
   CONTENT = "content",
   WEBPAGE = "webpage",
}

function Feed:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self

   o:_init(o)
   o = o:load()

   return o
end

function Feed:_init(o)
   -- Call the superclass' init function to apply those values to the
   -- current object.
   -- getmetatable(o):_init(o)

   self.subscription_type = Feed.subscription_type
   self.url = o.url
   self.limit = o.limit
   self.download_full_article = o.download_full_article -- not implemented
   self.download_directory = o.download_directory
   self.include_images = o.enabled_filter -- not implemented
   self.filter_element = o.filter_element -- not implemented
   self.content_source = o.content_source
   -- self.feed isn't initialized here. Instead, it's initialized in the
   -- SubscriptionFactory.
end

function Feed:save()
   self.feed.xml = nil
   self.feed.entries = nil
   -- This is pulled from State:save(). I wanted to call this
   -- through the same getmetatable magic used in _init... but
   -- it "didn't work".
   if not self.id
   then
      self.id = self:generateUniqueId()
   end

   self.lua_settings:saveSetting(self.id, self)
   self.lua_settings:flush()
end

function Feed:sync()
   local feed, err = FeedFactory:make(self.url)

   if err
   then
      return false, err
   end

   local feed, err = feed:fetch()

   if err
   then
      return false, err
   end

   self.feed = feed
   self:onSuccessfulSync()

   return true
end

function Feed:isUrlValid(url)
   if not url or
      not type(url) == "string"
   then
      return false
   end

   local parsed_url = socket_url.parse(url)

   if parsed_url.host
   then
      return true
   else
      return false
   end
end

function Feed:getTitle()
   return self.feed.title
end

function Feed:getDescription()
   return self.feed:getDescription()
end

function Feed:setTitle(title)
   self.feed.title = title
end

function Feed:getAllEntries(limit)
   if not self.feed.entries
   then
      return false, GazetteMessages.ERROR_FEED_NOT_SYNCED
   end

   if limit == nil or
      type(limit) ~= "number" or
      (type(limit) == "number" and limit == -1)
   then
      return self.feed.entries
   else
      local limited_entries = {}
      local count = 0

      for _, entry in pairs(self.feed.entries) do
         table.insert(limited_entries, entry)
         count = count + 1
         if count >= limit
         then
            break
         end
      end
      return limited_entries
   end
end

function Feed:getNewEntries(limit)
   local results = Results.forFeed(self.id)
   -- Need to adjust this so results returns a list of all the results.
   -- each time we sync, there's gonna be a new sub sync result.
   local all_entries = self:getAllEntries(limit)
   local new_entries = {}

   if not results
   then
      return all_entries
   end

   for id, entry in pairs(all_entries) do
      if not results:hasEntry(entry)
      then
         table.insert(new_entries, entry)
      end
   end

   return new_entries
end

function Feed:setDescription(description)
   -- This is a strange place to assign the values.
   -- We're operating on the feed data outside of the object.
   -- Why not just move this logic into the feed object?
   if self.feed.subtitle
   then
      self.feed.subtitle = description
   elseif self.feed.description
   then
      self.feed.description = description
   end
end

function Feed:setDownloadDirectory(path)
   if not util.pathExists(path)
   then
      util.makePath(path)
   end
   self.download_directory = path
end

function Feed:getDownloadDirectory()
   if self.download_directory
   then
      if string.sub(self.download_directory, #self.download_directory) == '/'
      then
         return string.sub(self.download_directory, 0, #self.download_directory - 1)
      else
         return self.download_directory
      end
   else
      return DataStorage:getDataDir() .. "/news"
   end
end

function Feed:getContentSource()
   return self.content_source or Feed.CONTENT_SOURCE.CONTENT
end

return Feed
