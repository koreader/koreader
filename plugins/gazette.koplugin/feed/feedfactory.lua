local Feed = require("feed/feed")
local RssFeed = require("feed/rss/rssfeed")
local AtomFeed = require("feed/atom/atomfeed")
local FeedError = require("feed/feederror")

local FeedFactory = {

}

function FeedFactory:make(url)
    local feed = Feed:new{
        url = url
    }

    local ok, err = feed:fetch()
    if not ok then
        return false, err
    end

    if is_atom(feed.xml) then
        return AtomFeed:new(feed)
    elseif is_rss(feed.xml) then
        return RssFeed:new(feed)
    elseif is_rdf(feed.xml) then
        -- Eventually add this
    else
        return false, FeedError.FEED_NOT_SUPPORTED_SYNDICATION_FORMAT
    end
end

function is_rss(document)
    return document.rss and
        document.rss.channel and
        document.rss.channel.title and
        document.rss.channel.item and
        document.rss.channel.item[1] and
        document.rss.channel.item[1].title and
        document.rss.channel.item[1].link
end

function is_atom(document)
    return document.feed and
        document.feed.title and
        document.feed.entry[1] and
        document.feed.entry[1].title and
        document.feed.entry[1].link
end

function is_rdf(document)
    return document["rdf:RDF"] and
        document["rdf:RDF"].channel and
        document["rdf:RDF"].channel.title
end

return FeedFactory
