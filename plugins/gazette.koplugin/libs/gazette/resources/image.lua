local util = require("util")
local Resource = require("libs/gazette/resources/resource")

local Image = Resource:new{
   filename = nil,
   url = nil,
   payload = nil
}

function Image:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   if not o.url
   then
      return false
   end

   if not o.payload
   then
      local payload, err = o:fetchUrlContent(o.url)
      if err
      then
	 return false, err
      else
	 o.payload = payload
      end
   end

   if not o.filename
   then
      o.filename = o:filenameFromUrl(o.url)
   end

   return o
end

function Image:getData()
   return self.payload
end

function Image:filenameFromUrl(url)
   local _, filename = util.splitFilePathName(url)
   local safe_filename = util.getSafeFilename(filename)
   return safe_filename
end

return Image

--  string.match(o.url, "((data:image/[a-z]+;base64,)(%w+))")
