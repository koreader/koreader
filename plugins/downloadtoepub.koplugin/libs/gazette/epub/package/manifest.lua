local EpubError = require("libs/gazette/epuberror")
local xml2lua = require("libs/xml2lua/xml2lua")
local Nav = require("libs/gazette/epub/package/item/nav")

local Manifest = {
    items = nil,
    nav = nil,
}

function Manifest:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    o.items = {}
    local nav = Nav:new{}
    o:addItem(nav)

    return o
end

function Manifest:addItem(item)
    if item == nil
    then
        return false, EpubError.MANIFEST_ITEM_NIL
    end

    if not self:isItemIncluded(item)
    then
        table.insert(self.items, item)
        return true
    else
        return false, EpubError.MANIFEST_ITEM_ALREADY_EXISTS
    end
end

function Manifest:isItemIncluded(item)
    return self:findItemLocation(function(existing_item)
            return existing_item.id == item.id
    end)
end

function Manifest:findItemLocationByProperties(properties)
    return self:findItemLocation(function(existing_item)
            if existing_item.properties and
                existing_item.properties == properties
            then
                return true
            end
            return false
    end)
end

function Manifest:findItemLocation(predicate)
    for index, item in ipairs(self.items) do
        if predicate(item) == true
        then
            return index
        end
    end
    return false
end

function Manifest:build()
    local items_xml = "\n"
    for index, item in ipairs(self.items) do
        local part, err = item:getManifestPart()
        if not part
        then
            return false, EpubError.MANIFEST_BUILD_ERROR
        end
        items_xml = items_xml .. part .. "\n"
    end
    return items_xml
end

return Manifest
