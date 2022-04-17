local http = require("socket.http")
local json = require("json")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

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
    local request = {
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
    local code, _, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    if code ~= 200 then
        logger.warn("ReadwiseClient: HTTP response code <> 200. Response status: ", status)
        error("ReadwiseClient: HTTP response code <> 200.")
    end

    local response = json.decode(sink[1])

    return response
end

function ReadwiseClient:createHighlights(booknotes)
    local highlights = {}
    for _, chapter in ipairs(booknotes) do
        for _, clipping in ipairs(chapter) do
            local highlight = {
                text = clipping.text,
                title = booknotes.title,
                author = booknotes.author ~= "" and booknotes.author or nil, -- optional author
                source_type = "koreader",
                category = "books",
                note = clipping.note,
                location = clipping.page,
                location_type = "page",
                highlighted_at = os.date("!%Y-%m-%dT%TZ", clipping.time),
            }
            table.insert(highlights, highlight)
        end
    end
    local result = self:_makeRequest("highlights", "POST", { highlights = highlights })
    logger.dbg("ReadwiseClient createHighlights result", result)
end

return ReadwiseClient
