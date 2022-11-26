local Subscription = require("subscription/subscription")
local FeedSubscription = require("subscription/type/feed")
local Feed = require("feed/feed")

local SubscriptionFactory = {

}

SubscriptionFactory.SUBSCRIPTION_TYPES = {
   feed = "feed"
}

function SubscriptionFactory:makeFeed(configuration)
    local subscription = FeedSubscription:new(configuration)

    if is_feed(subscription) then
        return FeedSubscription:new(configuration)
    else
        return false, "Subscription not found or type not supported"
    end
end

function is_feed(subscription)
    if (subscription.feed and subscription.url) or
        (subscription.url and (subscription.subscription_type == SubscriptionFactory.SUBSCRIPTION_TYPES.feed)) then
        return true
    end

end

return SubscriptionFactory
