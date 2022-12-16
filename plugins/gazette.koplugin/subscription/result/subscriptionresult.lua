local md5 = require("ffi/sha2").md5
local util = require("frontend/util")

local State = require("subscription/state")

local SubscriptionResult = State:new{
   STATE_FILE = "gazette_results.lua",
   ID_PREFIX = "result_",
   subscription_id = nil,
   results = nil,
   timestamp = nil
}

function SubscriptionResult:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self

   o = o:load()

   return o
end

function SubscriptionResult:add(result)
   local hashed_url = md5(result:getId())
   self.results[hashed_url] = result
end

function SubscriptionResult:initializeResults()
    local ResultFactory = require("subscription/result/resultfactory")

   if self.results == nil or
      type(self.results) ~= "table" then
      -- Initialize results anew.
      self.results = {}
      return false
   end

   local initialized_results = {}

   for id, data in pairs(self.results) do
      local result = ResultFactory:makeEntryResult(data)
      initialized_results[id] = result
   end

   self.results = initialized_results

   return true
end

function SubscriptionResult:hasEntry(entry)
   local hashed_url = md5(entry:getId())
   if self.results[hashed_url] then
      return true
   else
      return false
   end
end

function SubscriptionResult:getEntryResults()
   return self.results
end

function SubscriptionResult:totalSuccesses()
   local successes = 0
   for _, result in pairs(self.results) do
      if result:isSuccessful() then
         successes = successes + 1
      end
   end
   return successes
end

function SubscriptionResult:getResultCount()
   local count = 0
   for _,_ in pairs(self.results) do
      count = count + 1
   end
   return count
end

function SubscriptionResult:getOverviewMessage()
    return ("%s • %s/%s"):format(
        util.secondsToDate(tonumber(self.timestamp)),
        self:getResultCount(),
        self:totalSuccesses())
end

function SubscriptionResult:initializeSubscription()
    local subscription = Subscription:new{
        id = self.id
    }

    if not self.subscription and
        subscription then
        self.subscription = subscription
        return true
    elseif self.subscription ~= nil then
        return true
    else
        return false
    end
end

function SubscriptionResult:getSubscriptionTitle()
    if self:initializeSubscription() then
        return self.subscription:getTitle()
    else
        return "No title"
    end
end

function SubscriptionResult:getSubscriptionDescription()
    if self:initializeSubscription() then
        return self.subscription:getDescription()
    else
        return "No description"
    end
end

return SubscriptionResult
