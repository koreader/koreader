local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")

local InternalDownloadBackend = {}

function InternalDownloadBackend:getResponseAsString(url)
    local request, sink = {}, {}
    request['sink'] = ltn12.sink.table(sink)
    request['url'] = url
    local parsed = socket_url.parse(url)

    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    -- first argument returned by skip is code
    local _, headers, status = socket.skip(1, httpRequest(request))

    if status ~= "HTTP/1.1 200 OK" then
        logger.dbg("InternalDownloadBackend: HTTP response code <> 200. Response code: ", status)
        if status and string.sub(status, 1, 1) ~= "3" then -- handle 301, 302...
           if headers and headers["location"] then
              local redirected_url = headers["location"]
              logger.dbg("InternalDownloadBackend: Redirecting to url: ", redirected_url)
              return self:getResponseAsString(redirected_url)
           end
        else
           error("InternalDownloadBackend: Don't know how to handle HTTP status:", status)
        end
    end
    return table.concat(sink)
end

function InternalDownloadBackend:download(url, path)
   local response = self:getResponseAsString(url)
   local file = assert(io.open(path, 'w'))
   file:write(response)
   file:close()
end

return InternalDownloadBackend
