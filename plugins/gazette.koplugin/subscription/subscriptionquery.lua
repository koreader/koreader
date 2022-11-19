local SubscriptionFactory = require("subscription/subscriptionfactory")
local State = require("subscription/state")

local SubscriptionQuery = State:new{
    lua_settings = nil
}

function SubscriptionQuery:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init()

    return o
end

function SubscriptionQuery:all()
    local initialized_subscriptions = {}

    if not self
    then
        self = SubscriptionQuery:new{}
    end

    for id, data in pairs(self.lua_settings.data) do
        local subscription, err = SubscriptionFactory:makeFeed(data)
        if subscription then
            initialized_subscriptions[id] = subscription
        end
    end

    return initialized_subscriptions
end

return SubscriptionQuery
