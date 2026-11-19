local EpubError = require("libs/gazette/epuberror")
local XHtmlItem = require("libs/gazette/epub/package/item/xhtmlitem")
local Image = require("libs/gazette/epub/package/item/image")
local util = require("util")

local ItemFactory = {

}

ItemFactory.ITEM_TYPES = {
    xhtml = XHtmlItem.SUPPORTED_FORMATS,
    image = Image.SUPPORTED_FORMATS
}

ItemFactory.ITEM_CONSTRUCTORS = {
    xhtml = function(path, content)
        return XHtmlItem:new{
            path = path,
            content = content,
        }
    end,
    image = function(path, content)
        return Image:new{
            path = path,
            content = content
        }
    end
}

function ItemFactory:makeItemFromResource(resource)
   local title = resource.title
   local path = resource.filename
   local content = resource:getData()
   
   local item, item_type = self:makeItem(path, content)

   if item_type == "xhtml" and
      title
   then
      item.title = title
   end
   
   return item
end

function ItemFactory:makeItem(path, content)
    local suffix = util.getFileNameSuffix(
        string.lower(path)
    )

    local matched_type = ItemFactory:getItemTypeFromFileNameSuffix(suffix)
    if not matched_type
    then
        return false, EpubError.ITEMFACTORY_UNSUPPORTED_TYPE
    end

    local item_constructor = ItemFactory.ITEM_CONSTRUCTORS[matched_type]
    if not item_constructor
    then
        return false, EpubError.ITEMFACTORY_NONEXISTENT_CONSTRUCTOR
    end

    return item_constructor(path, content), matched_type
end

function ItemFactory:getItemTypeFromFileNameSuffix(suffix)
    local matched_item_type = nil
    for item_type, supported_formats in pairs(ItemFactory.ITEM_TYPES) do
        if supported_formats[suffix]
        then
            matched_item_type = item_type
            break
        end
    end
    return matched_item_type
end

return ItemFactory
