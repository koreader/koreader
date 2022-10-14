local xml2lua = require("libs/xml2lua/xml2lua")
local Item = require("libs/gazette/epub/package/item")
local Manifest = require("libs/gazette/epub/package/manifest")
local Spine = require("libs/gazette/epub/package/spine")

local Package = {
   title = nil,
   author = nil,
   language = "en",
   modified = nil,
   manifest = nil,
   spine = nil,
}

function Package:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   o.manifest = Manifest:new{}
   o.spine = Spine:new{}
   o.modified = os.date("%Y-%m-%dT%H:%M:%SZ")
   o:setTitle("Default title")

   return o
end

function Package:setTitle(title)
   self.title = title
end

function Package:setAuthor(author)
    self.author = author
end

function Package:addItem(item)
   local ok, err = self.manifest:addItem(item)
   if ok and
      item ~= nil
   then
      self.spine:addItem(item)
      self:addItemToNav(item)
   end
end

function Package:addItemToNav(item)
   if not item or
      item.property == Item.PROPERTY.NAV or
      item.add_to_nav == false
   then
      return false
   end
   local nav = self:getNav()
   -- Nav doesn't check to see if content already contained in nav,
   -- since it's entirely possible the same content could be linked twice.
   -- Why? I dunno, but it's possible.
   table.insert(nav.items, item)
   return true
end

function Package:getNav()
   local nav_index = self.manifest:findItemLocation(function(item)
         return item.properties == Item.PROPERTY.NAV
   end)
   return self.manifest.items[nav_index]
end

function Package:updateNav(item)
   local nav_index = self.manifest:findItemLocation(function(item)
         return item.properties == Item.PROPERTY.NAV
   end)
   self.manifest.items[nav_index] = item
   return true
end

function Package:getManifestItems()
   return self.manifest.items
end

function Package:addToNav()

end

function Package:getPackageXml()
   -- TODO: Add error catching/display
   local template, err = xml2lua.loadFile("plugins/gazette.koplugin/libs/gazette/epub/templates/package.xml")
   local manifest, err = self.manifest:build()
   local spine, err = self.spine:build()
   return string.format(
      template,
      self.title,
      self.author,
      self.language,
      self.modified,
      manifest,
      spine
   )
end

return Package

-- All items are in manifest
-- but not all items in manifest are in spine (i.e.: styles, scripts!)

--self.template["package"]["manifest"] = self.manifest:build()
--table.insert(self.template["package"]["manifest"], self.manifest:build())
-- self.template["package"]["manifest"][1] = { item = {name="hi"}}
-- require("logger").dbg(self.template)
-- local xml = xml2lua.toXml(self.template)
-- print(xml)

-- require("logger").dbg(templae)
--xml2lua.printable(template)
--return xml2lua.toXml(template)
-- function Package:addItemToManifest(item)

--     -- table.insert(self.template["package"]["manifest"],
--     --     -- Get the manifest from Manifest object?
--     -- )

--     self.template["package"]["manifest"][1] = {
--         item = {
--             {_attr={type="natural"}, name="Manoel", city="Palmas-TO"}
--         }
--     }
--     xml2lua.printable(self.template)
--     --{_attr={type="natural"}, name="Manoel", city="Palmas-TO"},
--     --require("logger").dbg(self.template["package"]["manifest"])
-- end

-- C-S-_ is undo?

-- function Package:initializeFromTemplateFile(template_file)
--     local handler = require("libs/xml2lua/xmlhandler.tree"):new()
--     local parser = xml2lua.parser(handler)
--     local ok, err = pcall(function()
--             parser:parse(xml2lua.loadFile(template_file))
--     end)

--     if not ok
--     then
--         return false, err
--     end

--     self.template = handler.root

--     return true
-- end

-- local ok, err = o:initializeFromTemplateFile("plugins/gazette.koplugin/libs/gazette/epub/templates/package.xml")

-- if not ok
-- then
--     return "error" -- Package error...
-- end

--self.template["package"]["metadata"]["dc:title"][1] = title
