local Resource = require("libs/gazette/resources/resource")
local Element = require("libs/gazette/resources/htmldocument/element")
local util = require("util")

local HtmlDocument = Resource:new{
   url = nil,
   html = nil,
   filename = nil,
   title = nil,
}

function HtmlDocument:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   if not o.url
      and not o.html
   then
      return false
   end
   
   if not o.html
   then
      local content, err = o:fetchUrlContent(o.url)
      if err
      then
         return false, err
      else
         o.html = content
      end
   end   

   o.title = o.title or o:findTitle()
   
   if not o.filename
   then
      local _, filename = util.splitFilePathName(o.url or o.title)
      -- Some URLs will have a suffix (".html"), some won't.
      -- So the URL gets split to its pure filename and the suffix
      -- is manually appended.
      local pure_filename, suffix = util.splitFileNameSuffix(filename)
      local safe_filename = util.getSafeFilename(pure_filename)      
      o.filename = safe_filename .. ".html"
   end
   
   return o
end

function HtmlDocument:getData()
   return self.html
end

function HtmlDocument:findImageElements()
   return self:extractElements("img")
end

function HtmlDocument:findTitle()
   return string.match(self.html,"<title>(.+)</title>")
end

function HtmlDocument:extractElements(tag)
   local elements = {}
   -- Build the element in two parts because the second part
   -- is generated based on the supplied tag. And it frigs with
   -- the first part because of the %s thing
   local element_to_match = "(<%s" .. string.format("*%s [^>]*>)", tag)   
   for element_html in string.gmatch(self.html, element_to_match) do
      local element = Element:new(element_html)
      table.insert(elements, element)
   end
   return elements
end

function HtmlDocument:modifyElements(tag, callback)
   local element_to_match = "(<%s" .. string.format("*%s [^>]*>)", tag)   
   self.html = string.gsub(self.html, element_to_match, callback)
end

return HtmlDocument
