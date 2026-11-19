local Resource = require("libs/gazette/resources/resource")
local HtmlDocument = require("libs/gazette/resources/htmldocument")
local Image = require("libs/gazette/resources/image")
local ItemFactory = require("libs/gazette/factories/itemfactory")
local RequestFactory = require("libs/http/requestfactory")
local util = require("util")
local socket_url = require("socket.url")

local WebPage = Resource:extend {
   url = nil,
   base_url = nil,
   title = nil,
   items = nil,
   resources = nil,
}

function WebPage:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   if not o.url
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

   o.base_url = socket_url.parse(o.url)
   o.resources = {}
   o.items = {}

   return o
end

function WebPage:build()
   self:createResources()
   self:createItems()
end

function WebPage:createResources()
   local html_document = HtmlDocument:new{
      url = self.url or nil,
      html = self.html or nil,
      title = self.title or nil
   }
   table.insert(self.resources, html_document)

   local images = self:downloadImages(
      html_document:findImageElements()
   )
   html_document:modifyElements("img", function(element)
         local image = images[element]
         if not image
         then
            return element
         end
         -- local path = string.format("%s/%s", html_document.filename, image.filename)
         return string.format([[<img src="%s"/>]], image.filename)
   end)
   for _, image in pairs(images) do
      table.insert(self.resources, image)
   end
end

function WebPage:createItems()
   for _, resource in ipairs(self.resources) do
      local item, err = ItemFactory:makeItemFromResource(resource)
      if err
      then
         goto continue
      end
      table.insert(self.items, item)
      ::continue::
   end
end

function WebPage:downloadImages(image_elements)
   local image_items = {}
   for _, element in ipairs(image_elements) do
      local src = element:src()
      if not src
      then
         goto continue
      end

      local url = socket_url.absolute(self.base_url, src)
      local image, err = Image:new{
         url = url
      }
      if image
      then
         image_items[element.html] = image
      end
      ::continue::
   end
   return image_items
end

return WebPage
