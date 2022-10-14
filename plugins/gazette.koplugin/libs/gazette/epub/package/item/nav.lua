local GazetteMessages = require("gazettemessages")
local Item = require("libs/gazette/epub/package/item")
local xml2lua = require("libs/xml2lua/xml2lua")

local Nav = Item:new{
    title = nil,
    items = nil,
}

function Nav:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    o.title = GazetteMessages.DEFAULT_NAV_TITLE
    o.path = "nav.xhtml"
    o.properties = Item.PROPERTY.NAV
    o.media_type = "application/xhtml+xml"
    o.items = {},
    o:generateId()

    return o
end

function Nav:setTitle(title)
    self.title = title
end

function Nav:addItem(item)
    -- insert item, yes, but reference it by it's id...
    table.insert(self.items, item)
end

function Nav:getContent()
    -- TODO: Add error catching/display
    local template, err = xml2lua.loadFile("plugins/gazette.koplugin/libs/gazette/epub/templates/nav.xhtml")
    local items_list = "\n"

    for _, item in ipairs(self.items) do
        local part = item:getNavPart()
        if part
        then
            items_list = items_list .. part
        end
    end

    template = string.format(
        template,
        self.title,
        items_list
    )

    return template
end

return Nav
