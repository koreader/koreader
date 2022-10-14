local RequestFactory = require("libs/http/requestfactory")
local FeedError = require("feed/feederror")

local Entry = {

}

function Entry:new(o)
   o = o or {}
   self.__index = self
   setmetatable(o, self)

   return o
end

function Entry:getTitle()
   return self.title
end

function Entry:getSummary()
   return self.description or self.summary
end

function Entry:getContent()
    -- Some feeds may have a content tag, tho it's not guaranteed. Atom feeds have the option to include one.
    -- RSS doesn't include any mention of one in its specification, but feeds include the tag anyways.
    -- Anywho, if the content tag doesn't exist, fallback getSummary(), since some feeds store the content within
    -- the description or summary tags.
    return self.content or self:getSummary()
end

function Entry:getPublished()
   return self.pubDate or self.published or self.updated
end

function Entry:getId()
    return self:getPermalink()
end

function Entry:getPermalink()
   -- ID must preceed link, since Atom entries have
   -- both id and link attributes.
   return self.id or self.link
end

function Entry:fetch()
   if self:getPermalink()
   then
      local request = RequestFactory:makeGetRequest(self:getPermalink(), {})
      local response = request:send()

      if response:canBeConsumed() and
          response:hasContent() and
          response:isOk()
      then
          self.content = response.content
          return true
      else
          return false, FeedError:provideFromResponse(response)
      end
   end
end

function Entry:getAuthor()
   return self.author
end

return Entry
