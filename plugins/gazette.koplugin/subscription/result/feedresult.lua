local GazetteMessages = require("gazettemessages")

local FeedResult = {
   id = nil,
   success = nil,
   error_message = nil,
   entry_title = nil,
   timestamp = nil,
}

function FeedResult:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   return o
end

function FeedResult:getId()
   return self.id
end

function FeedResult:setError(error_message)
   self.success = false
   self.error_message = error_message
   return self
end

function FeedResult:setSuccess()
   self.success = true
   return self
end

function FeedResult:isSuccessful()
   return self.success
end

function FeedResult:getStatus()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return GazetteMessages.RESULT_ERROR
   end
end

function FeedResult:getStatusMessage()
   if self:isSuccessful()
   then
      return GazetteMessages.RESULT_SUCCESS
   else
      return self.error_message
   end
end

function FeedResult:getIdentifier()
   return self.id
end

return FeedResult
