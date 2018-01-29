local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require('socket')
local socket_url = require("socket.url")

local InternalDownloadBackend = {}
local max_redirects = 10;

function InternalDownloadBackend:getResponseAsString(url, redirectCount)
    if not redirectCount then
        redirectCount = 0
    elseif redirectCount == max_redirects then
        logger.warn("InternalDownloadBackend: reached max redirects: ", redirectCount)
    end
    logger.dbg("InternalDownloadBackend: url :", url)
    local request, sink = {}, {}
    request['sink'] = ltn12.sink.table(sink)
    request['url'] = url
    local parsed = socket_url.parse(url)

    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, httpRequest(request))

    if status ~= "HTTP/1.1 200 OK" then
        logger.dbg("InternalDownloadBackend: HTTP response code <> 200. Response code: ", status)
        if status and string.sub(string.sub(status, 10), 1,1) == "3" and headers and headers["location"] then -- handle 301, 302...
           local redirected_url = headers["location"]
           logger.dbg("InternalDownloadBackend: Redirecting to url: ", redirected_url)
           return self:getResponseAsString(redirected_url, redirectCount + 1)
        else
           logger.warn("InternalDownloadBackend: Don't know how to handle HTTP status: ", status)
        end
    end
    return table.concat(sink)
end

function InternalDownloadBackend:download(url, path)
   local response = self:getResponseAsString(url)
   local file = io.open(path, 'w')
   file:write(response)
   file:close()
end

return InternalDownloadBackend
