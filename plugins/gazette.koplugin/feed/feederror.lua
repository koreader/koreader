local HttpError = require("libs/http/httperror")
local _ = require("gettext")
local T = require("ffi/util").template

local FeedError = HttpError:new{

}

FeedError.FEED_NONSPECIFIC_ERROR = _("There was an error. That's all I know.")
FeedError.FEED_HAS_NO_CONTENT = _("The feed didn't return any content.")
FeedError.RESPONSE_NOT_XML = _("Feed is not an XML document.")
FeedError.FEED_NOT_SUPPORTED_SYNDICATION_FORMAT = _("URL is not a supported syndication format.")

function FeedError:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

function FeedError:provideFromFeed(feed)
    if feed.xml == nil
    then
        return FeedError.FEED_HAS_NO_CONTENT
    end
    return FeedError.FEED_NONSPECIFIC_ERROR
end

function FeedError:provideFromResponse(response)

    if response:isOk() and
        response:hasHeaders() and
        not response:isXml()
    then
        return FeedError.RESPONSE_NOT_XML
    end

    return getmetatable(self).__index:provideFromResponse(response)
end

return FeedError
