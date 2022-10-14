local EpubError = require("libs/gazette/epuberror")
local md5 = require("ffi/sha2").md5

local Item = {
    id = nil,
    path = nil,
    content = nil,
    media_type = nil,
    properties = nil,
    add_to_nav = nil
}

Item.PROPERTY = {
    NAV = "nav"
}

Item.TYPE = "default"

function Item:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

function Item:generateId()
    self.id = "a" .. md5(self.path) -- IDs can't start with number
end

function Item:getManifestPart()
    if not self.path and
        not self.mimetype
    then
        return false, EpubError:provideFromItem(self)
    end

    self:generateId()

    if self.properties
    then
        return string.format(
            [[<item id="%s" href="%s" media-type="%s" properties="%s"/>]],
            self.id,
            self.path,
            self.media_type,
            self.properties
        )
    else
        return string.format(
            [[<item id="%s" href="%s" media-type="%s"/>]],
            self.id,
            self.path,
            self.media_type
        )
    end
end

-- located in a spine factory
function Item:getSpinePart()
    return string.format(
        [[<itemref idref="%s" />%s]],
        self.id,
        "\n"
    )
end
-- C-y ??
-- this should be located in Nav, or a NavFactorNavFactoryestuestest
function Item:getNavPart()
    return string.format(
        [[<li><a href="%s">%s</a></li>%s]],
        self.path,
        self.title,
        "\n"
    )
end

function Item:getContent()
    if type(self.content) == "string"
    then
        return self.content
    else
        return false
    end
end

return Item
