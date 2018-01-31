local http = require("socket.http")
local https = require("ssl.https")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket_url = require("socket.url")

local InternalDownloadBackend = {}

function InternalDownloadBackend:getResponseAsString(url)
    local resp_lines = {}
    local parsed = socket_url.parse(url)
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    httpRequest({ url = url, sink = ltn12.sink.table(resp_lines), })
    return table.concat(resp_lines)
end

function InternalDownloadBackend:download(link, path)
    logger.dbg("InternalDownloadBackend: News file will be stored to :", path)
    local parsed = socket_url.parse(link)
    local httpRequest = parsed.scheme == 'http' and http.request or https.request
    httpRequest({ url = link, sink = ltn12.sink.file(io.open(path, "w")), })
end

return InternalDownloadBackend
