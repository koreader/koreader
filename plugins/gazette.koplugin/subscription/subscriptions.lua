local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")

local SubscriptionFactory = require("subscription/subscriptionfactory")
local SubscriptionBuilder = require("views/subscription_builder")
local State = require("subscription/state")
local ResultsFactory = require("subscription/result/resultsfactory")

local Subscriptions = State:new{
   lua_settings = nil
}

function Subscriptions:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   o:init()
   return o
end

function Subscriptions:all()
   local initialized_subscriptions = {}

   if not self
   then
      self = Subscriptions:new{}
   end

   for id, data in pairs(self.lua_settings.data) do
      if data.subscription_type and
         data.subscription_type == "feed"
      then
         local subscription = SubscriptionFactory:makeFeed(data)
         initialized_subscriptions[id] = subscription
      end
   end

   return initialized_subscriptions
end

function Subscriptions:sync(progress_callback, finished_callback)
   local initialized_subscriptions = Subscriptions.all()
   local sync_results = {}


   local timestamp = os.date()

   for id, subscription in pairs(initialized_subscriptions) do
      subscription:sync()

      local subscription_results = ResultsFactory:makeResults(subscription)
      subscription_results.timestamp = timestamp

      for _, entry in pairs(subscription:getNewEntries(subscription.limit)) do
         progress_callback(subscription:getTitle() .. ": " .. entry:getTitle())
         local entry_result = SubscriptionBuilder:buildSingleEntry(subscription, entry)
         subscription_results:add(entry_result)
      end

      subscription_results:save()
      table.insert(sync_results, subscription_results)
   end

   finished_callback(sync_results)
end

return Subscriptions
