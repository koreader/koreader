package.path = "rocks/share/lua/5.1/?.lua;" .. package.path
package.cpath = "rocks/lib/lua/5.1/?.so;" .. package.cpath
require("commonrequire")
local UIManager = require("ui/uimanager")
local HTTPClient = require("httpclient")
local DEBUG = require("dbg")
local md5 = require("MD5")
DEBUG:turnOn()

local service = [[
{
    "base_url" : "https://192.168.1.101:7200",
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
    local Spore = require("Spore")
    local client = Spore.new_from_string(service)
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
    local username, password = "koreader", md5:sum("koreader")
    -- fake progress data
    local doc, percentage, progress, device =
        "41cce710f34e5ec21315e19c99821415", -- fast digest of the document
        0.356, -- percentage of the progress
        "69", -- page number or xpointer
        "my kpw" -- device name
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
                DEBUG("register successful to ", res.body.username)
            elseif res.status == 402 then
                DEBUG("register unsuccessful: ", res.body.message)
            end
        else
            DEBUG("Please retry later", res)
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
                DEBUG(res.body)
            end
        else
            DEBUG("Please retry later", res)
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
                DEBUG(res.body.message)
            end
        else
            DEBUG("Please retry later", res)
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
                DEBUG(res.body.message)
            end
        else
            DEBUG("Please retry later", res)
        end
    end)
end)
