local SubscriptionQuery = require("subscription/subscriptionquery")
local SubscriptionFactory = require("subscription/subscriptionfactory")
local SubscriptionBuilder = require("views/subscription_builder")
local SubscriptionSyncResult = require("subscription/result/subscriptionresult")

local SubscriptionUpdater = {}

function SubscriptionUpdater:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function SubscriptionUpdater:download(progress_callback, finished_callback, subscription)
    local initialized_subscriptions
    if subscription then
        initialized_subscriptions = {subscription}
    else
        initialized_subscriptions = SubscriptionQuery:new{}:all()
    end

    local sync_results = {}
    local timestamp = os.time()

    for id, subscription in pairs(initialized_subscriptions) do
        subscription:sync()

        local subscription_results = SubscriptionSyncResult:new{
            subscription_id = subscription.id,
            results = {}
        }
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

return SubscriptionUpdater
