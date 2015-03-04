local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")

local HTTPClient = {
    headers = {},
    input_timeouts = 0,
    INPUT_TIMEOUT = 100*1000,
}

function HTTPClient:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function HTTPClient:addHeader(header, value)
    self.headers[header] = value
end

function HTTPClient:removeHeader(header)
    self.headers[header] = nil
end

function HTTPClient:request(request, response_callback, error_callback)
    request.on_headers = function(headers)
        for header, value in pairs(self.headers) do
            headers[header] = value
        end
    end
    request.connect_timeout = 10
    request.request_timeout = 20
    UIManager:initLooper()
    UIManager:handleTask(function()
        -- avoid endless waiting for input
        UIManager.INPUT_TIMEOUT = self.INPUT_TIMEOUT
        self.input_timeouts = self.input_timeouts + 1
        local turbo = require("turbo")
        local res = coroutine.yield(
            turbo.async.HTTPClient():fetch(request.url, request))
        -- reset INPUT_TIMEOUT to nil when all HTTP requests are fullfilled.
        self.input_timeouts = self.input_timeouts - 1
        UIManager.INPUT_TIMEOUT = self.input_timeouts > 0 and self.INPUT_TIMEOUT or nil
        if res.error and error_callback then
            error_callback(res)
        elseif response_callback then
            response_callback(res)
        end
    end)
end

return HTTPClient
