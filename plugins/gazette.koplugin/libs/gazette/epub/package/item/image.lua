local Item = require("libs/gazette/epub/package/item")
local EpubError = require("libs/gazette/epuberror")
local util = require("util")

local Image = Item:new {
   format = nil,
   add_to_nav = false,
}

Image.SUPPORTED_FORMATS = {
   jpeg = "image/jpeg",
   jpg = "image/jpeg",
   png = "image/png",
   gif = "image/gif",
   svg = "image/svg+xml"
}

function Image:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   if not o.path
   then
      return false, EpubError.ITEM_MISSING_PATH
   end

   -- Change "format" to "fileType" or "extension"
   local format = o:isFormatSupported(o.path)
   if not format
   then
      return false, EpubError.IMAGE_UNSUPPORTED_FORMAT
   end

   o.media_type = format
   o:generateId()
   o.path = o.path

   return o
end

function Image:fetchContent(data_source)

end

function Image:isFormatSupported(path)
   -- path = path and string.lower(path) or ""
   -- local extension = string.match(path, "[^.]+$")
   local extension = util.getFileNameSuffix(path)
   return Image.SUPPORTED_FORMATS[extension] and
       Image.SUPPORTED_FORMATS[extension]  or
       false
end

return Image
