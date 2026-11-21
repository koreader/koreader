local UIManager = require("ui/uimanager")
local logger = require("logger")
local socketutil = require("socketutil")

-- Push/Pull
local PROGRESS_TIMEOUTS = { 2,  5 }
-- Login/Register
local AUTH_TIMEOUTS     = { 5, 10 }

local KOSyncClient = {
    service_spec = nil,
    custom_url = nil,
}

function KOSyncClient:new(o)
    if o == nil then o = {} end
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function KOSyncClient:init()
    local Spore = require("Spore")
    local custom_url = self.custom_url
    if custom_url then
        local socket_url = require("socket.url")
        local parsed = socket_url.parse(custom_url)
        if not parsed or not parsed.host or parsed.host == "" or not parsed.host:match("^[%w%.%_%-%[%]]+$") then
            logger.warn("KOSyncClient: invalid custom_url, falling back to default:", custom_url)
            custom_url = nil
        end
    end
    local ok, client = pcall(Spore.new_from_spec, self.service_spec, {
        base_url = custom_url,
    })
    if not ok then
        logger.warn("KOSyncClient: failed to initialize with custom_url, falling back to default server:", custom_url, client)
        ok, client = pcall(Spore.new_from_spec, self.service_spec)
    end
    if ok then
        self.client = client
    else
        logger.err("KOSyncClient: failed to initialize Spore client:", client)
        return
    end
    package.loaded["Spore.Middleware.GinClient"] = {}
    require("Spore.Middleware.GinClient").call = function(_, req)
        req.headers["accept"] = "application/vnd.koreader.v1+json"
    end
    package.loaded["Spore.Middleware.KOSyncAuth"] = {}
    require("Spore.Middleware.KOSyncAuth").call = function(args, req)
        req.headers["x-auth-user"] = args.username
        req.headers["x-auth-key"] = args.userkey
    end
    package.loaded["Spore.Middleware.AsyncHTTP"] = {}
    require("Spore.Middleware.AsyncHTTP").call = function(args, req)
        -- disable async http if Turbo looper is missing
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
            -- Turbo HTTP client uses code instead of status
            -- change to status so that Spore can understand
            result.status = res.code
            coroutine.resume(args.thread)
        end)
        return coroutine.create(function() coroutine.yield(result) end)
    end
end

function KOSyncClient:register(username, password)
    if not self.client then
        return false, { message = "KOSync client not initialized" }
    end
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("GinClient")
    socketutil:set_timeout(AUTH_TIMEOUTS[1], AUTH_TIMEOUTS[2])
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
        logger.dbg("KOSyncClient:register failure:", res)
        return false, res.body
    end
end

function KOSyncClient:authorize(username, password)
    if not self.client then
        return false, { message = "KOSync client not initialized" }
    end
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("GinClient")
    self.client:enable("KOSyncAuth", {
        username = username,
        userkey = password,
    })
    socketutil:set_timeout(AUTH_TIMEOUTS[1], AUTH_TIMEOUTS[2])
    local ok, res = pcall(function()
        return self.client:authorize()
    end)
    socketutil:reset_timeout()
    if ok then
        return res.status == 200, res.body
    else
        logger.dbg("KOSyncClient:authorize failure:", res)
        return false, res.body
    end
end

function KOSyncClient:update_progress(
        username,
        password,
        document,
        metadata,
        progress,
        percentage,
        device,
        device_id,
        callback)
    if not self.client then
        if callback then callback(false, nil, nil) end
        return
    end
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("GinClient")
    self.client:enable("KOSyncAuth", {
        username = username,
        userkey = password,
    })
    -- Set *very* tight timeouts to avoid blocking for too long...
    socketutil:set_timeout(PROGRESS_TIMEOUTS[1], PROGRESS_TIMEOUTS[2])
    local co = coroutine.create(function()
        local ok, res = pcall(function()
            return self.client:update_progress({
                document = document,
                metadata = metadata,
                progress = tostring(progress),
                percentage = percentage,
                device = device,
                device_id = device_id,
            })
        end)
        if ok then
            callback(res.status == 200, res.status, res.body)
        else
            logger.dbg("KOSyncClient:update_progress failure:", res)
            callback(false, nil, nil)
        end
    end)
    self.client:enable("AsyncHTTP", {thread = co})
    coroutine.resume(co)
    if UIManager.looper then UIManager:setInputTimeout() end
    socketutil:reset_timeout()
end

function KOSyncClient:get_progress(
        username,
        password,
        document,
        callback)
    if not self.client then
        if callback then callback(false, nil) end
        return
    end
    self.client:reset_middlewares()
    self.client:enable("Format.JSON")
    self.client:enable("GinClient")
    self.client:enable("KOSyncAuth", {
        username = username,
        userkey = password,
    })
    socketutil:set_timeout(PROGRESS_TIMEOUTS[1], PROGRESS_TIMEOUTS[2])
    local co = coroutine.create(function()
        local ok, res = pcall(function()
            return self.client:get_progress({
                document = document,
            })
        end)
        if ok then
            callback(res.status == 200, res.body)
        else
            logger.dbg("KOSyncClient:get_progress failure:", res)
            callback(false, res.body)
        end
    end)
    self.client:enable("AsyncHTTP", {thread = co})
    coroutine.resume(co)
    if UIManager.looper then UIManager:setInputTimeout() end
    socketutil:reset_timeout()
end

return KOSyncClient
