local logger = require("logger")
local http = require("socket.http")
local socketutil = require("socketutil")
local socket_url = require("socket.url")
local socket = require("socket")
local ltn12 = require("ltn12")

local NewsHelpers = {
}

local max_redirects = 5; --prevent infinite redirects

-- Get URL content
function NewsHelpers:getUrlContent(url, timeout, maxtime, redirectCount)
    logger.dbg("getUrlContent(", url, ",", timeout, ",", maxtime, ",", redirectCount, ")")
    if not redirectCount then
        redirectCount = 0
    elseif redirectCount == max_redirects then
        error("EpubDownloadBackend: reached max redirects: ", redirectCount)
    end

    if not timeout then timeout = 10 end
    logger.dbg("timeout:", timeout)

    local sink = {}
    local parsed = socket_url.parse(url)
    socketutil:set_timeout(timeout, maxtime or 30)
    local request = {
        url     = url,
        method  = "GET",
        sink    = maxtime and socketutil.table_sink(sink) or ltn12.sink.table(sink),
    }
    logger.dbg("request:", request)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    logger.dbg("After http.request")
    local content = table.concat(sink) -- empty or content accumulated till now
    logger.dbg("type(code):", type(code))
    logger.dbg("code:", code)
    logger.dbg("headers:", headers)
    logger.dbg("status:", status)
    logger.dbg("#content:", #content)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        logger.warn("request interrupted:", code)
        return false, code
    end
    if headers == nil then
        logger.warn("No HTTP headers:", code, status)
        return false, "Network or remote server unavailable"
    end
    if not code or string.sub(code, 1, 1) ~= "2" then -- all 200..299 HTTP codes are OK
        if code and code > 299 and code < 400  and headers and headers.location then -- handle 301, 302...
            local redirected_url = headers.location
            local parsed_redirect_location = socket_url.parse(redirected_url)
            if not parsed_redirect_location.host then
                parsed_redirect_location.host = parsed.host
                parsed_redirect_location.scheme = parsed.scheme
                redirected_url = socket_url.build(parsed_redirect_location)
            end
            logger.dbg("getUrlContent: Redirecting to url: ", redirected_url)
            return self:getUrlContent(redirected_url, timeout, maxtime, redirectCount + 1)
        else
            --            error("EpubDownloadBackend: Don't know how to handle HTTP response status: " .. status)
            --            error("EpubDownloadBackend: Don't know how to handle HTTP response status.")
            logger.warn("HTTP status not okay:", code, status)
            return false, status
        end
    end
    if headers and headers["content-length"] then
        -- Check we really got the announced content size
        local content_length = tonumber(headers["content-length"])
        if #content ~= content_length then
            return false, "Incomplete content received"
        end
    end
    logger.dbg("Returning content ok")
    return true, content
end

function NewsHelpers:loadPage(url)
    logger.dbg("Load page: ", url)
    local success, content
--[[    if self.trap_widget then -- if previously set with EpubDownloadBackend:setTrapWidget()
        local Trapper = require("ui/trapper")
        local timeout, maxtime = 30, 60
        -- We use dismissableRunInSubprocess with complex return values:
        completed, success, content = Trapper:dismissableRunInSubprocess(function()
            return NewsHelpers:getUrlContent(url, timeout, maxtime)
        end, self.trap_widget)
        if not completed then
            error(self.dismissed_error_code) -- "Interrupted by user"
        end
    else]]--
    local timeout, maxtime = 10, 60
    success, content = NewsHelpers:getUrlContent(url, timeout, maxtime)
--    end
    logger.dbg("success:", success, "type(content):", type(content), "content:", content:sub(1, 500), "...")
    if not success then
        error(content)
    else
        return content
    end
end

function NewsHelpers:deserializeXMLString(xml_str)
    -- uses LuaXML https://github.com/manoelcampos/LuaXML
    -- The MIT License (MIT)
    -- Copyright (c) 2016 Manoel Campos da Silva Filho
    -- see: koreader/plugins/newsdownloader.koplugin/lib/LICENSE_LuaXML
    local treehdl = require("lib/handler")
    local libxml = require("lib/xml")
    -- Instantiate the object that parses the XML file as a Lua table.
    local xmlhandler = treehdl.simpleTreeHandler()
    -- Instantiate the object that parses the XML to a Lua table.
    local ok = pcall(function()
            libxml.xmlParser(xmlhandler):parse(xml_str)
    end)
    if not ok then return end
    return xmlhandler.root
end

return NewsHelpers
