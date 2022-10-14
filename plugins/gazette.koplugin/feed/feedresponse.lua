local Response = require("libs/http/response")

local FeedResponse = Response:new {

}

function FeedResponse:isXml()
    if self["content-type"] and
        self["content-type"] == "application/xml"
    then
        return true
    else
        return false
    end
end

return FeedResponse
