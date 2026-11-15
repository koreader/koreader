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
                "device_id",
            ],
            "optional_params" : [
                "metadata",
            ],
            "payload" : [
                "document",
                "metadata",
                "progress",
                "percentage",
                "device",
                "device_id",
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

describe("KOSync modules #notest", function()
    local logger, md5, client
    local username, password, doc, metadata, percentage, progress, device, device_id

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
        doc, metadata, percentage, progress, device, device_id =
            "41cce710f34e5ec21315e19c99821415", -- fast digest of the document
            { filename = "my_book.epub", title = "My Book", authors = "Test Author" }, -- document metadata
            0.356, -- percentage of the progress
            "69", -- page number or xpointer
            "my kpw", -- device name
            "test-device-id" -- device id
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
                metadata = metadata,
                progress = progress,
                percentage = percentage,
                device = device,
                device_id = device_id,
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

        c.update_progress = function(name, passwd, doc, metadata, prog, percent, device, device_id, cb) --luacheck: ignore
            cb(res.result, res.body)
        end

        c.get_progress = function(name, passwd, doc, cb) --luacheck: ignore
            cb(res.result, res.body)
        end
    end
end)

describe("KOSync custom server configuration", function()
    local KOSync, sync

    setup(function()
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        KOSync = dofile("plugins/kosync.koplugin/main.lua")
    end)

    before_each(function()
        sync = setmetatable({ settings = {}, path = "plugins/kosync.koplugin" }, { __index = KOSync })
    end)

    it("should accept valid custom server URLs", function()
        assert.is_true(sync:setCustomServer("https://sync.example.com"))
        assert.are.same("https://sync.example.com", sync.settings.custom_server)

        assert.is_true(sync:setCustomServer("http://sync.example.com:8080"))
        assert.are.same("http://sync.example.com:8080", sync.settings.custom_server)

        assert.is_true(sync:setCustomServer("http://192.168.1.100:8000"))
        assert.are.same("http://192.168.1.100:8000", sync.settings.custom_server)
    end)

    it("should prepend https:// if no scheme is specified for a valid host", function()
        assert.is_true(sync:setCustomServer("sync.example.com"))
        assert.are.same("https://sync.example.com", sync.settings.custom_server)
    end)

    it("should reset custom server to nil when given empty string, whitespace, or bare scheme", function()
        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer(""))
        assert.is_nil(sync.settings.custom_server)

        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer("   "))
        assert.is_nil(sync.settings.custom_server)

        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer("https://"))
        assert.is_nil(sync.settings.custom_server)

        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer("http://"))
        assert.is_nil(sync.settings.custom_server)

        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer("https:///"))
        assert.is_nil(sync.settings.custom_server)

        sync.settings.custom_server = "https://sync.example.com"
        assert.is_true(sync:setCustomServer(nil))
        assert.is_nil(sync.settings.custom_server)
    end)

    it("should reject invalid server addresses without host", function()
        sync.settings.custom_server = "https://sync.example.com"

        assert.is_false(sync:setCustomServer("http:///path"))
        assert.are.same("https://sync.example.com", sync.settings.custom_server)

        assert.is_false(sync:setCustomServer("bad :// url"))
        assert.are.same("https://sync.example.com", sync.settings.custom_server)

        assert.is_false(sync:setCustomServer("invalid url with spaces"))
        assert.are.same("https://sync.example.com", sync.settings.custom_server)
    end)
end)

describe("KOSyncClient initialization and fallback", function()
    local KOSyncClient

    setup(function()
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        KOSyncClient = require("KOSyncClient")
    end)

    it("should initialize safely without custom_url", function()
        local client = KOSyncClient:new{
            service_spec = "plugins/kosync.koplugin/api.json",
        }
        assert.is_truthy(client.client)
    end)

    it("should initialize safely with valid custom_url", function()
        local client = KOSyncClient:new{
            custom_url = "https://sync.example.com",
            service_spec = "plugins/kosync.koplugin/api.json",
        }
        assert.is_truthy(client.client)
    end)

    it("should fall back to default server and not crash on invalid custom_url", function()
        assert.has_no.errors(function()
            local client = KOSyncClient:new{
                custom_url = "https://",
                service_spec = "plugins/kosync.koplugin/api.json",
            }
            assert.is_truthy(client.client)
        end)

        assert.has_no.errors(function()
            local client = KOSyncClient:new{
                custom_url = "http://",
                service_spec = "plugins/kosync.koplugin/api.json",
            }
            assert.is_truthy(client.client)
        end)

        assert.has_no.errors(function()
            local client = KOSyncClient:new{
                custom_url = "http:///path",
                service_spec = "plugins/kosync.koplugin/api.json",
            }
            assert.is_truthy(client.client)
        end)
    end)

    it("should handle calls gracefully when uninitialized", function()
        local client = KOSyncClient:new()
        client.client = nil

        local ok, res = client:register("user", "pass")
        assert.is_false(ok)
        assert.is_truthy(res)

        ok, res = client:authorize("user", "pass")
        assert.is_false(ok)
        assert.is_truthy(res)

        local called_update = false
        client:update_progress("u", "p", "d", {}, "1", 0.1, "dev", "id", function(success)
            called_update = true
            assert.is_false(success)
        end)
        assert.is_true(called_update)

        local called_get = false
        client:get_progress("u", "p", "d", function(success)
            called_get = true
            assert.is_false(success)
        end)
        assert.is_true(called_get)
    end)
end)
