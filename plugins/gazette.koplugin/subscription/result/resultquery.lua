local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")

local State = require("subscription/state")
local SubscriptionSyncResult = require("subscription/result/subscription_sync_result")
local ResultsFactory = require("subscription/result/resultsfactory")

local ResultQuery = State:new{
   lua_settings = nil,
   STATE_FILE = SubscriptionSyncResult.STATE_FILE,
}

function ResultQuery:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   o:init()
   return o
end

function ResultQuery:all()
   local initialized_results = {}

   -- if not self
   -- then
   --    self = ResultQuery:new{}
   -- end

   for id, data in pairs(self.lua_settings.data) do
      local results = ResultsFactory:makeResults(data)
      initialized_results[id] = results
   end

   return initialized_results
end

function ResultQuery:forFeed(id)
   local results = self:all()

   local collected_results = {}

   for _, subscription_sync_results in pairs(results) do
      if subscription_sync_results.subscription_id == id then
         table.insert(collected_results, subscription_sync_results)
      end
   end

   collected_results.hasEntry = function(self, entry)
      local has_entry = false
      for _, results in ipairs(collected_results) do
         if results:hasEntry(entry) then
            has_entry = true
            ::continue::
         end
      end
      return has_entry
   end

   return collected_results
end

function ResultQuery:deleteForSubscription(subscription_id)
   local results = self:forFeed(subscription_id)

   for _, subscription_sync_results in ipairs(results) do
      subscription_sync_results:delete()
   end
end

return ResultQuery
