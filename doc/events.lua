-- You can call me with something like `ldoc --filter events.filter .`
return {
   filter = function (t)
      for _, mod in ipairs(t) do
         for _, item in ipairs(mod.items) do
            if item.type == 'event' then
               print(mod.name,item.name,mod.file,item.lineno)
            end
         end
      end
   end
}
