local Result = require("subscription/result/result")

local ResultFactory = {}

function ResultFactory:makeResult(entry_or_data)
   local result
   if entry_or_data.getId and
      type(entry_or_data.getId) == "function" and
      type(entry_or_data.getTitle) == "function"
   then
      local entry = entry_or_data
      -- If the result's being made with this constructor, the context
      -- is the subscription builder. So the success and error message
      -- are added in after the result's been returned.
      result = Result:new{
         id = entry:getId(),
         entry_title = entry:getTitle()
      }
   else
      local data = entry_or_data
      result = Result:new{
            id = data.id,
            error_message = data.error_message,
            success = data.success,
            entry_title = data.entry_title
      }
   end
   return result
end

return ResultFactory
