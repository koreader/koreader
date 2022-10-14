local md5 = require("ffi/sha2").md5

local State = require("subscription/state")
local ResultFactory = require("subscription/result/resultfactory")

local SubscriptionSyncResult = State:new{
   STATE_FILE = "gazette_results.lua",
   ID_PREFIX = "result_",
   subscription_id = nil,
   results = nil,
   timestamp = nil
}

function SubscriptionSyncResult:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self

   o:_init(o)
   o = o:load()

   return o
end

function SubscriptionSyncResult:_init(o)
   self.results = o.results
   self.id = o.id
   self.subscription_id = o.subscription_id
   self.timestamp = o.timestamp
end

function SubscriptionSyncResult:add(result)
   local hashed_url = md5(result:getId())
   self.results[hashed_url] = result
end

function SubscriptionSyncResult:initializeResults()
   if self.results == nil or
      type(self.results) ~= "table"
   then
      -- Initialize results anew.
      self.results = {}
      return false
   end

   local initialized_results = {}

   for id, data in pairs(self.results) do
      local result = ResultFactory:makeResult(data)
      initialized_results[id] = result
   end

   self.results = initialized_results

   return true
end

function SubscriptionSyncResult:hasEntry(entry)
   local hashed_url = md5(entry:getId())
   if self.results[hashed_url]
   then
      return true
   else
      return false
   end
end

function SubscriptionSyncResult:getEntryResults()
   return self.results
end

function SubscriptionSyncResult:totalSuccesses()
   local successes = 0
   for _, result in pairs(self.results) do
      if result:isSuccessful()
      then
         successes = successes + 1
      end
   end
   return successes
end

function SubscriptionSyncResult:getResultCount()
   local count = 0
   for _,_ in pairs(self.results) do
      count = count + 1
   end
   return count
end

function SubscriptionSyncResult:getOverviewMessage()
   return ("%s/%s"):format(self:totalSuccesses(), self:getResultCount())
end

function SubscriptionSyncResult:initializeSubscription()
   local subscription = Subscription:new({id = self.id})
   if not self.subscription and
      subscription
   then
      self.subscription = subscription
      return true
   elseif self.subscription ~= nil
   then
      return true
   else
      return false
   end
end

function SubscriptionSyncResult:getSubscriptionTitle()
   if self:initializeSubscription()
   then
      return self.subscription:getTitle()
   else
      return "No"
   end
end

function SubscriptionSyncResult:getSubscriptionDescription()
   if self:initializeSubscription()
   then
      return self.subscription:getDescription()
   else
      return "No"
   end
end

return SubscriptionSyncResult
