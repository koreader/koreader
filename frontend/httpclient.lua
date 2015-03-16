local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")

local HTTPClient = {
    input_timeouts = 0,
    INPUT_TIMEOUT = 100*1000,
}

function HTTPClient:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function HTTPClient:request(request, response_callback)
    request.connect_timeout = 10
    request.request_timeout = 20
    UIManager:initLooper()
    UIManager:handleTask(function()
        -- avoid endless waiting for input
        UIManager.INPUT_TIMEOUT = self.INPUT_TIMEOUT
        self.input_timeouts = self.input_timeouts + 1
        local turbo = require("turbo")
        -- disable success and warning logs
        turbo.log.categories.success = false
        turbo.log.categories.warning = false
        local client = turbo.async.HTTPClient({verify_ca = "none"})
        local res = coroutine.yield(client:fetch(request.url, request))
        -- reset INPUT_TIMEOUT to nil when all HTTP requests are fullfilled.
        self.input_timeouts = self.input_timeouts - 1
        UIManager.INPUT_TIMEOUT = self.input_timeouts > 0 and self.INPUT_TIMEOUT or nil
        if response_callback then
            response_callback(res)
        end
    end)
end

return HTTPClient
