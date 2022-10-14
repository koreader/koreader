local GazetteMessages = require("gazettemessages")

local Result = {
   id = nil,
   success = nil,
   error_message = nil,
   entry_title = nil,
   timestamp = nil,
}

function Result:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   return o
end

function Result:getId()
   return self.id
end

function Result:setError(error_message)
   self.success = false
   self.error_message = error_message
   return self
end

function Result:setSuccess()
   self.success = true
   return self
end

function Result:isSuccessful()
   return self.success
end

function Result:getStatus()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return GazetteMessages.RESULT_ERROR
   end
end

function Result:getStatusMessage()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return self.error_message
   end
end

function Result:getIdentifier()
   return self.id
end

return Result
