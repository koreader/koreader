local FontRepo = {}

local function auth(url, key)
    if url and key then
        return url .. "&key=" .. key
    elseif url then
        return url
    end
end

function FontRepo:new(o)
    if not o.id or not o.url then
        return nil, "id and url are required"
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

-- download JSON encoded data from provider
-- @treturn array of fonts
function FontRepo:getFontTable()
    local ltn12 = require("ltn12")
    local https = require("ssl.https")
    local rapidjson = require("rapidjson")
    local socket = require("socket")
    local request, sink = {}, {}
    request.url = auth(self.url, self.key)
    request.method = "GET"
    request.sink = ltn12.sink.table(sink)
    https.TIMEOUT = 10
    local _, headers, status = socket.skip(1, https.request(request))
    if headers == nil then
        return {}, "Network is unreachable"
    elseif status ~= "HTTP/1.1 200 OK" then
        return {}, status
    end
    local t = rapidjson.decode(table.concat(sink))
    if not t then
        return {}, "Can't decode server response"
    end
    return t
end

return FontRepo
