local UIManager = require("ui/uimanager")

local HTTPClient = {
    input_timeouts = 0,
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
    UIManager.looper:add_callback(function()
        -- avoid endless waiting for input
        UIManager:setInputTimeout()
        self.input_timeouts = self.input_timeouts + 1
        local turbo = require("turbo")
        -- disable success and warning logs
        turbo.log.categories.success = false
        turbo.log.categories.warning = false
        local client = turbo.async.HTTPClient({verify_ca = false})
        local res = coroutine.yield(client:fetch(request.url, request))
        self.input_timeouts = self.input_timeouts - 1
        -- reset INPUT_TIMEOUT to nil when all HTTP requests are fulfilled.
        if self.input_timeouts == 0 then UIManager:resetInputTimeout() end
        if response_callback then
            response_callback(res)
        end
    end)
end

return HTTPClient
