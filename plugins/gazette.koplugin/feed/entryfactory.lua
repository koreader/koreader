local Entry = require("feed/entry")
local AtomEntry = require("feed/atom/atomentry")
local RssEntry = require("feed/rss/rssentry")

local EntryFactory = {

}

function EntryFactory:makeAtom(entryAsXml)
    local authors = nil

    if entryAsXml.author and #entryAsXml.author > 0
    then
        authors = ""
        for index, author in ipairs(entryAsXml.author) do
            authors = authors .. author.name
            if index ~= #entryAsXml.author
            then
                authors = authors .. ", "
            end
        end
    end

    return AtomEntry:new{
        id = entryAsXml.id,
        updated = entryAsXml.updated,
        link = (entryAsXml.link ~= nil and entryAsXml.link._attr ~= nil)
            and {
                rel = entryAsXml.link._attr.rel,
                href = entryAsXml.link._attr.href,
            } or nil,
        content = entryAsXml.content or entryAsXml["content:encoded"],
        summary = entryAsXml.summary,
        author = authors,
        title = entryAsXml.title,
        published = entryAsXml.published,
    }
end

function EntryFactory:makeRss(entryAsXml)
    return RssEntry:new{
        title = entryAsXml.title,
        description = entryAsXml.description,
        content = entryAsXml.content or entryAsXml["content:encoded"],
        author = entryAsXml.author,
        pubDate = entryAsXml.pubDate,
        link = entryAsXml.link,
    }
end

return EntryFactory
