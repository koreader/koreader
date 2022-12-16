local EntryResult = require("subscription/result/entryresult")
local SubscriptionResult = require("subscription/result/subscriptionresult")

local ResultFactory = {}

function ResultFactory:makeSubscriptionResult(data)
    local id
    local subscription_id

    if data.subscription_id then
        id = data.id
        subscription_id = data.subscription_id
    else
        -- Don't set ID, because it's probably a new result.
        id = nil
        subscription_id = data.subscription_id
    end

    local results = SubscriptionResult:new{
        id = id,
        subscription_id = subscription_id,
        results = data.results
    }

    results:initializeResults()

    return results
end

function ResultFactory:makeEntryResult(entry_or_data)
   local result
   if entry_or_data.getId and
      type(entry_or_data.getId) == "function" and
      type(entry_or_data.getTitle) == "function"
   then
      local entry = entry_or_data
      -- If the result's being made with this constructor, the context
      -- is the subscription builder. So the success and error message
      -- are added in after the result's been returned.
      result = EntryResult:new{
         id = entry:getId(),
         entry_title = entry:getTitle()
      }
   else
      local data = entry_or_data
      result = EntryResult:new{data}
   end
   return result
end

return ResultFactory
