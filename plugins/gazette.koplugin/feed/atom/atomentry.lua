local Entry = require("feed/entry")

local AtomEntry = Entry:new {
    id = nil,
    updated = nil,
    link = {
        rel = nil,
        href = nil
    },
    summary = nil,
    content = nil,
    authors = {
        name = nil
    },
    title = nil,
    published = nil
}

function AtomEntry:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

return AtomEntry
