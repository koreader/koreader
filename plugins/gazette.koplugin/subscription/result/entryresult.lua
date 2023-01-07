local GazetteMessages = require("gazettemessages")

local EntryResult = {
   id = nil,
   success = nil,
   error_message = nil,
   entry_title = nil,
   timestamp = nil,
}

function EntryResult:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   return o
end

function EntryResult:getId()
   return self.id
end

function EntryResult:setError(error_message)
   self.success = false
   self.error_message = error_message
   return self
end

function EntryResult:setSuccess()
   self.success = true
   return self
end

function EntryResult:isSuccessful()
   return self.success
end

function EntryResult:getStatus()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return GazetteMessages.RESULT_ERROR
   end
end

function EntryResult:getStatusMessage()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return self.error_message
   end
end

function EntryResult:getIdentifier()
   return self.id
end

return EntryResult
