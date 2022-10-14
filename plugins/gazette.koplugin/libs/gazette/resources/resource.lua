local HttpError = require("libs/http/httperror")
local RequestFactory = require("libs/http/requestfactory")

local Resource = {
   data = nil,
   filename = nil
}

function Resource:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   return o
end

function Resource:getData()
   return self.data
end

function Resource:fetchUrlContent(url)
   local request, err = RequestFactory:makeGetRequest(url, {})
   if not request
   then
      return false, err
   end

   local response, err = request:send()
   if err or not response.content
   then
      return false, HttpError:provideFromResponse(response)
   end

   if not response:isOk()
   then
      return false, HttpError:provideFromResponse(response)
   end

   return response.content
end

return Resource
