local UIManager = require("ui/uimanager")
local logger = require("logger")
local socketutil = require("socketutil")

local PROGRESS_TIMEOUTS = { 2, 5 }
local SYNC_TIMEOUTS = { 10, 45 }
local STATS_GIN_MIDDLEWARE = "Spore.Middleware.StatisticsGinClient"
local STATS_AUTH_MIDDLEWARE = "Spore.Middleware.StatisticsAuth"
local STATS_ASYNC_MIDDLEWARE = "Spore.Middleware.StatisticsAsyncHTTP"

local StatisticsAccountSyncClient = {
    service_spec = nil,
    custom_url = nil,
}

function StatisticsAccountSyncClient:new(o)
    if o == nil then o = {} end
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function StatisticsAccountSyncClient:init()
    local Spore = require("Spore")
    self.client = Spore.new_from_spec(self.service_spec, {
        base_url = self.custom_url,
    })

    package.loaded[STATS_GIN_MIDDLEWARE] = {}
    require(STATS_GIN_MIDDLEWARE).call = function(_, req)
        req.headers["accept"] = "application/vnd.koreader.v1+json"
        req.headers["x-client-version"] = "y-anna-1.0"
        req.headers["user-agent"] = "Mozilla/DONTLIKE/ANYTHING"
    end

    package.loaded[STATS_AUTH_MIDDLEWARE] = {}
    require(STATS_AUTH_MIDDLEWARE).call = function(args, req)
        req.headers["x-auth-user"] = args.username
        req.headers["x-auth-key"] = args.userkey
    end

    package.loaded[STATS_ASYNC_MIDDLEWARE] = {}
    require(STATS_ASYNC_MIDDLEWARE).call = function(args, req)
        if not UIManager.looper then return end
        req:finalize()
        local result
        require("httpclient"):new():request({
            url = req.url,
            method = req.method,
            body = req.env.spore.payload,
            on_headers = function(headers)
                for header, value in pairs(req.headers) do
                    if type(header) == "string" then
                        headers:add(header, value)
                    end
                end
            end,
        }, function(res)
            result = res
            result.status = res.code
            coroutine.resume(args.thread)
        end)
        return coroutine.create(function() coroutine.yield(result) end)
    end
end

function StatisticsAccountSyncClient:register(username, password)
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("StatisticsGinClient")
    socketutil:set_timeout(PROGRESS_TIMEOUTS[1], PROGRESS_TIMEOUTS[2])
    local ok, res = pcall(function()
        return self.client:register({
            username = username,
            password = password,
        })
    end)
    socketutil:reset_timeout()
    if ok then
        return res.status == 201, res.body
    else
        logger.warn("StatisticsAccountSyncClient:register failure:", res)
        return false, res.body
    end
end

function StatisticsAccountSyncClient:authorize(username, password)
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("StatisticsGinClient")
    self.client:enable("StatisticsAuth", {
        username = username,
        userkey = password,
    })
    socketutil:set_timeout(PROGRESS_TIMEOUTS[1], PROGRESS_TIMEOUTS[2])
    local ok, res = pcall(function()
        return self.client:authorize()
    end)
    socketutil:reset_timeout()
    if ok then
        return res.status == 200, res.body
    else
        logger.warn("StatisticsAccountSyncClient:authorize failure:", res)
        return false, res.body
    end
end

function StatisticsAccountSyncClient:sync_statistics(username, userkey, payload, callback)
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("StatisticsGinClient")
    self.client:enable("StatisticsAuth", {
        username = username,
        userkey = userkey,
    })

    socketutil:set_timeout(SYNC_TIMEOUTS[1], SYNC_TIMEOUTS[2])

    local co = coroutine.create(function()
        local ok, res = pcall(function()
            return self.client:sync_statistics(payload)
        end)
        if ok then
            callback(res.status == 200 or res.status == 202, res.body, res.status)
        else
            logger.warn("StatisticsAccountSyncClient:sync_statistics failure:", res)
            local error_body = type(res) == "table" and res.body or nil
            callback(false, error_body, nil)
        end
    end)
    self.client:enable("StatisticsAsyncHTTP", {thread = co})
    coroutine.resume(co)
    if UIManager.looper then UIManager:setInputTimeout() end
    socketutil:reset_timeout()
end

return StatisticsAccountSyncClient
