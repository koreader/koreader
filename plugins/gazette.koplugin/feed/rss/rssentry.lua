local Entry = require("feed/entry")

local RssEntry = Entry:new {
    title = nil,
    description = nil,
    content = nil,
    author = nil,
    pubDate = nil,
    link = nil
}

function RssEntry:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

return RssEntry
