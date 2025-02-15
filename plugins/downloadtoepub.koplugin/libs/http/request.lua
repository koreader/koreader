local http = require("socket.http")
local socketutil = require("socketutil")
local socket = require("socket")
local ltn12 = require("ltn12")
local logger = require("logger")

local ResponseFactory = require("libs/http/responsefactory")

local DEFAULT_TIMEOUT = 30
local DEFAULT_MAXTIME = 30
local DEFAULT_REDIRECTS = 5

local Request = {
    url = nil,
    method = nil,
    maxtime = DEFAULT_MAXTIME,
    timeout = DEFAULT_TIMEOUT,
    redirects = DEFAULT_REDIRECTS,
    sink = {},
}

Request.method = {
    get = "GET",
    post = "POST",
}

Request.scheme = {
    http = "HTTP",
    https = "HTTPS"
}

Request.default = {
    timeout = DEFAULT_TIMEOUT,
    maxtime = DEFAULT_MAXTIME,
    redirects = DEFAULT_REDIRECTS,
}

function Request:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    return o
end

function Request:send()
    self.sink = {}
    socketutil:set_timeout(self.timeout, self.maxtime)
    local code, headers, status = socket.skip(1, http.request({
                url = self.url,
                method = self.method,
                sink = self.maxtime and socketutil.table_sink(self.sink) or ltn12.sink.table(self.sink)
    }))
    local content = table.concat(self.sink)
    socketutil:reset_timeout()
    return ResponseFactory:make(code, headers, status, content)
end

return Request
