local Element = {
   html = nil
}

function Element:new(html)
   o = {}
   self.__index = self
   setmetatable(o, self)

   o.html = html
   
   return o
end

function Element:src()
   return self:attributeValue("src")
end

function Element:attributeValue(attribute)
   local attribute_to_match = string.format([[%s="([^"]*)"]], attribute)
   local value = self.html:match(attribute_to_match)
   if not value or value == ""
   then
      return false, string.format("Error: no %s value in this element", attribute)
   end
   return value
end

return Element
