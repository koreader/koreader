local ResourceIterator = {

}

function ResourceIterator:new(webpage)
   local i = 0
   local item_count = #webpage.items
   return function()
      i = i + 1
      if i <= item_count
      then
         return webpage.items[i]
      end
   end
end

return ResourceIterator
