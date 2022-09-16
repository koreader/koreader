local http = require("socket.http")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local InternalDownloadBackend = {}
local max_redirects = 5 --prevent infinite redirects

function InternalDownloadBackend:getResponseAsString(url, redirectCount)
    if not redirectCount then
        redirectCount = 0
    elseif redirectCount == max_redirects then
        error("InternalDownloadBackend: reached max redirects:", redirectCount)
    end
    logger.dbg("InternalDownloadBackend: url:", url)
    local sink = {}
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local request = {
        url     = url,
        sink    = ltn12.sink.table(sink),
    }
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.dbg("InternalDownloadBackend: HTTP response code <> 200. Response status:", status or code)
        if code and code > 299 and code < 400 and headers and headers.location then -- handle 301, 302...
            local redirected_url = headers.location
            logger.dbg("InternalDownloadBackend: Redirecting to url:", redirected_url)
            return self:getResponseAsString(redirected_url, redirectCount + 1)
        else
            logger.dbg("InternalDownloadBackend: Unhandled response status:", status or code)
            logger.dbg("InternalDownloadBackend: Response headers:", headers)
            error("InternalDownloadBackend: Don't know how to handle HTTP response status:", status or code)
        end
    end
    return table.concat(sink)
end

function InternalDownloadBackend:download(url, path)
    local response = self:getResponseAsString(url)
    local file = io.open(path, 'w')
    if file then
        file:write(response)
        file:close()
    end
end

return InternalDownloadBackend
