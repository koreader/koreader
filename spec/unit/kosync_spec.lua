local service = [[
{
    "base_url" : "https://sync.koreader.rocks:443/",
    "name" : "api",
    "methods" : {
        "register" : {
            "path" : "/users/create",
            "method" : "POST",
            "required_params" : [
                "username",
                "password",
            ],
            "payload" : [
                "username",
                "password",
            ],
            "expected_status" : [201, 402]
        },
        "authorize" : {
            "path" : "/users/auth",
            "method" : "GET",
            "expected_status" : [200, 401]
        },
        "update_progress" : {
            "path" : "/syncs/progress",
            "method" : "PUT",
            "required_params" : [
                "document",
                "progress",
                "percentage",
                "device",
            ],
            "payload" : [
                "document",
                "progress",
                "percentage",
                "device",
            ],
            "expected_status" : [200, 202, 401]
        },
        "get_progress" : {
            "path" : "/syncs/progress/:document",
            "method" : "GET",
            "required_params" : [
                "document",
            ],
            "expected_status" : [200, 401]
        },
    }
}
]]

describe("KOSync modules #notest #nocov", function()
    local logger, md5, client
    local username, password, doc, percentage, progress, device

    setup(function()
        require("commonrequire")
        logger = require("logger")
        md5 = require("ffi/MD5")
        local Spore = require("Spore")
        client = Spore.new_from_string(service)
        package.loaded['Spore.Middleware.GinClient'] = {}
        require('Spore.Middleware.GinClient').call = function(self, req)
            req.headers['accept'] = "application/vnd.koreader.v1+json"
        end
        package.loaded['Spore.Middleware.KOSyncAuth'] = {}
        require('Spore.Middleware.KOSyncAuth').call = function(args, req)
            req.headers['x-auth-user'] = args.username
            req.headers['x-auth-key'] = args.userkey
        end
        -- password should be hashed before submitting to server
        username, password = "koreader", md5.sum("koreader")
        -- fake progress data
        doc, percentage, progress, device =
            "41cce710f34e5ec21315e19c99821415", -- fast digest of the document
            0.356, -- percentage of the progress
            "69", -- page number or xpointer
            "my kpw" -- device name
    end)

    it("should create new user", function()
        client:reset_middlewares()
        client:enable('Format.JSON')
        client:enable("GinClient")
        local ok, res = pcall(function()
            return client:register({
                username = username,
                password = password,
            })
        end)
        if ok then
            if res.status == 200 then
                logger.dbg("register successful to ", res.body.username)
            elseif res.status == 402 then
                logger.dbg("register unsuccessful: ", res.body.message)
            end
        else
            logger.dbg("Please retry later", res)
        end
    end)

    it("should authorize user", function()
        client:reset_middlewares()
        client:enable('Format.JSON')
        client:enable("GinClient")
        client:enable("KOSyncAuth", {
            username = username,
            userkey = password,
        })
        local ok, res = pcall(function()
            return client:authorize()
        end)
        if ok then
            if res.status == 200 then
                assert.are.same("OK", res.body.authorized)
            else
                logger.dbg(res.body)
            end
        else
            logger.dbg("Please retry later", res)
        end
    end)

    it("should update progress", function()
        client:reset_middlewares()
        client:enable('Format.JSON')
        client:enable("GinClient")
        client:enable("KOSyncAuth", {
            username = username,
            userkey = password,
        })
        local ok, res = pcall(function()
            return client:update_progress({
                document = doc,
                progress = progress,
                percentage = percentage,
                device = device,
            })
        end)
        if ok then
            if res.status == 200 then
                local result = res.body
                assert.are.same(progress, result.progress)
                assert.are.same(percentage, result.percentage)
                assert.are.same(device, result.device)
            else
                logger.dbg(res.body.message)
            end
        else
            logger.dbg("Please retry later", res)
        end
    end)

    it("should get progress", function()
        client:reset_middlewares()
        client:enable('Format.JSON')
        client:enable("GinClient")
        client:enable("KOSyncAuth", {
            username = username,
            userkey = password,
        })
        local ok, res = pcall(function()
            return client:get_progress({
                document = doc,
            })
        end)
        if ok then
            if res.status == 200 then
                local result = res.body
                assert.are.same(progress, result.progress)
                assert.are.same(percentage, result.percentage)
                assert.are.same(device, result.device)
            else
                logger.dbg(res.body.message)
            end
        else
            logger.dbg("Please retry later", res)
        end
    end)

    -- The response of mockKOSyncClient
    local res = {
        result = false,
        body = {}
    }

    --- @todo Test kosync module
    local function mockKOSyncClient() --luacheck: ignore
        package.loaded["KOSyncClient"] = nil
        local c = require("KOSyncClient")
        c.new = function(o)
            o = o or {}
            setmetatable(o, self) --luacheck: ignore
            self.__index = self --luacheck: ignore
            return o
        end

        c.init = function() end

        c.register = function(name, passwd)
            return res.result, res.body
        end

        c.authorize = function(name, passwd)
            return res.result, res.body
        end

        c.update_progress = function(name, passwd, doc, prog, percent, device, device_id, cb) --luacheck: ignore
            cb(res.result, res.body)
        end

        c.get_progress = function(name, passwd, doc, cb) --luacheck: ignore
            cb(res.result, res.body)
        end
    end
end)
