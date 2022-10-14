local Result = require("subscription/result/result")
local SubscriptionSyncResult = require("subscription/result/subscription_sync_result")

local ResultsFactory = {}

function ResultsFactory:makeResults(data)

   local id, subscription_id

   if data.subscription_id
   then
      id = data.id
      subscription_id = data.subscription_id
   else
      -- Don't set ID, because it's probably a new result.
      id = nil
      subscription_id = data.id
   end

   local results = SubscriptionSyncResult:new({
         id = id,
         subscription_id = subscription_id,
         results = data.results
   })

   results:initializeResults()

   return results
end

return ResultsFactory
