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

    -- raise error message when network is unavailable
    if headers == nil then
        error("Network is unreachable")
    end

    if status ~= "HTTP/1.1 200 OK" then
        logger.warn("translator HTTP status not okay:", status)
        return
    end
    return table.concat(sink)
end


function InternalDownloadBackend:download(link, path)
    logger.dbg("InternalDownloadBackend: News file will be stored to :", path)
    local parsed = socket_url.parse(link)
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
   httpRequest({ url = link, sink = ltn12.sink.file(io.open(path, 'w')), })
end



return InternalDownloadBackend
