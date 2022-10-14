local EpubError = require("libs/gazette/epuberror")
local Item = require("libs/gazette/epub/package/item")
local util = require("util")

local XHtmlItem = Item:new {
    title = "Untitled Document",
    add_to_nav = true
}

XHtmlItem.SUPPORTED_FORMATS = {
    xhtml = true,
    html = true
}

function XHtmlItem:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    if not o.path
    then
        return false, EpubError.ITEM_MISSING_PATH
    end

    o.path = util.urlEncode(o.path)
    o.media_type = "application/xhtml+xml"
    o:generateId()

    return o
end

return XHtmlItem
