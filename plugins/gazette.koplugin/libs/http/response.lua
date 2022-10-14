local socketutil = require("socketutil")
local socket_url = require("socket.url")

local Response = {
    code = nil,
    headers = nil,
    status = nil,
    url = nil,
    content = nil,
}

function Response:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    if o:hasHeaders()
    then
        o:setUrlFromHeaders()
    end

    if not o:isHostKnown()
    then
        o.code = 404
    end

    if o:isXml() and
        o:hasContent()
    then
        o.content = o:decodeXml(o.content)
    end

    return o
end

function Response:canBeConsumed()
    if self:hasCompleted() and
        self:hasHeaders()
    then
        return true
    else
        return false
    end
end

function Response:hasRedirected()
    if type(self.code) == "number" and
        self.code > 299 and
        self.code < 400
    then
        return true
    else
        return false
    end
end

function Response:isOk()
    if type(self.code) == "number" and
        self.code == 200
    then
        return true
    else
        return false
    end
end

function Response:hasCompleted()
    if not self.code or
        self.code == socketutil.TIMEOUT_CODE or
        self.code == socketutil.SSL_HANDSHAKE_CODE or
        self.code == socketutil.SINK_TIMEOUT_CODE
    then
        return false
    else
        return true
    end
end

function Response:hasHeaders()
    if self.headers == nil or
        not self.headers["content-type"]
    then
        return false
    else
        return true
    end
end

function Response:hasContent()
    if self.content == nil or
       not type(self.content) == "string"
    -- tonumber(self.headers["content-length"]) ~= #self.content)
    -- It would be ideal to check the content's length, but not all
    -- requests supply that value.
    then
        return false
    else
        return true
    end
end

function Response:isHostKnown()
    if self.code == "host or service not provided, or not known"
    then
        return false
    else
        return true
    end
end

function Response:isXml()
    if self:hasHeaders() and
        string.match(self.headers["content-type"], "(.*)xml(.*)")
    then
        return true
    else
        return false
    end
end

function Response:setUrlFromHeaders()
    local url = self.headers.location

    if url
    then
        local parsed_url = socket_url.parse(url)
        self.url = socket_url.build(parsed_url)
    end
end

function Response:decodeXml(xml_to_decode)
    local xml2lua = require("../libs/xml2lua/xml2lua")
    local handler = require("../libs/xml2lua/xmlhandler.tree"):new()
    local parser = xml2lua.parser(handler)

    local ok, error_message = pcall(function()
            parser:parse(xml_to_decode)
    end)
    if not ok then
        -- when this method returns, the response's content attribute
        -- will be set to nil, meaning the response will be considered
        -- without content.
        return nil
    end
    return handler.root
end

return Response
