local http = require("socket.http")
local json = require("json")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local logger = require("logger") -- TODO remove

local ReadwiseClient =  {
    auth_token = ""
}

function ReadwiseClient:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)
    return o
end

function ReadwiseClient:_makeRequest(endpoint, method, request_body)
    local sink = {}
    local request_body_json = json.encode(request_body)
    local source = ltn12.source.string(request_body_json)
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    http.request{
        url     = "https://readwise.io/api/v2/" .. endpoint,
        method  = method,
        sink    = ltn12.sink.table(sink),
        source  = source,
        headers = {
            ["Content-Length"] = #request_body_json,
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Token " .. self.auth_token
        },
    }
    socketutil:reset_timeout()

    if not sink[1] then
        error("No response from Readwise Server")
    end

    local response = json.decode(sink[1])

    -- TODO check response code

    if response.error then
        error(response.error)
    end

    return response
end

function ReadwiseClient:ping()
    local sink = {}

    local highlights = self:_makeRequest("highlights?page_size=1", "GET")

    return highlights
end

function ReadwiseClient:createHighlights(booknotes)
    local highlights = {}
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = {
                text = clipping.text,
                title = booknotes.title,
                author = booknotes.author,
                source_type = "koreader",
                category = "books",
                note = clipping.note,
                location = clipping.page,
                location_type = "page",
                highlighted_at = os.date("!%Y-%m-%dT%TZ", clipping.time), -- TODO: check timezone
            }
            table.insert(highlights, highlight)
        end
    end
    logger.dbg("request", highlights) -- TODO remove
    local result = self:_makeRequest("highlights", "POST", { highlights = highlights })
    logger.dbg("result", result) -- TODO remove
end

return ReadwiseClient
