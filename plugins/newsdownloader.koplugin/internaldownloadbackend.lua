local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")

local InternalDownloadBackend = {}

local function processDownloadAndReturnSink(url)
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
        if status and string.sub(status, 1, 1) ~= "3" then -- handle 301, 302...
           if headers and headers["location"] then
            local redirected_url = headers["location"]
            logger.dbg("HTTP response code: ", status)
            logger.dbg("Redirecting to url: ", redirected_url)
            -- clean up stuff, and recursively recall your download function
            -- (you may want to add a counter, so you're not in an infinite loop
            -- if the remote server is misconfigured and keeps redirecting)
            return processDownloadAndReturnSink(redirected_url)
           end
        else
           logger.warn("translator HTTP status not okay:", status)
           return
        end
    end
    return sink
end

function InternalDownloadBackend:getResponseAsString(url)
    local sink = processDownloadAndReturnSink(url)
    return table.concat(sink)
end


function InternalDownloadBackend:download(url, path)
   local sink = processDownloadAndReturnSink(url)
   ltn12.sink.file(io.open(path, 'w'))
end



return InternalDownloadBackend
