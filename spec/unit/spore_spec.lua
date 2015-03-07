package.path = "rocks/share/lua/5.1/?.lua;" .. package.path
package.cpath = "rocks/lib/lua/5.1/?.so;" .. package.cpath
require("commonrequire")
local UIManager = require("ui/uimanager")
local HTTPClient = require("httpclient")
local DEBUG = require("dbg")
--DEBUG:turnOn()

local service = [[
{
    "base_url" : "http://httpbin.org",
    "name" : "api",
    "methods" : {
        "get_info" : {
            "path" : "/get",
            "method" : "GET",
            "required_params" : [
                "user"
            ],
            "optional_params" : [
                "age"
            ],
        },
        "post_info" : {
            "path" : "/post",
            "method" : "POST",
            "required_params" : [
                "user"
            ],
            "optional_params" : [
                "age"
            ],
            "payload" : [
                "user",
                "age",
            ],
        },
    }
}
]]

describe("Lua Spore modules #nocov", function()
    local Spore = require("Spore")
    local client = Spore.new_from_string(service)
    client:enable('Format.JSON')
    it("should complete GET request", function()
        local info = {user = 'john', age = '25'}
        local res = client:get_info(info)
        assert.are.same(res.body.args, info)
    end)
    it("should complete POST request", function()
        local info = {user = 'sam', age = '26'}
        local res = client:post_info(info)
        assert.are.same(res.body.json, info)
    end)
end)

describe("Lua Spore modules with async request #nocov", function()
    local Spore = require("Spore")
    local client = Spore.new_from_string(service)
    client:enable("Format.JSON")
    package.loaded['Spore.Middleware.Async'] = {}
    local async_http_client = HTTPClient:new()
    it("should complete GET request", function()
        UIManager:quit()
        local co = coroutine.create(function()
            local info = {user = 'john', age = '25'}
            local res = client:get_info(info)
            UIManager:quit()
            assert.are.same(res.body.args, info)
        end)
        require('Spore.Middleware.Async').call = function(self, req)
            req:finalize()
            local result
            async_http_client:request({
                url = req.url,
                method = req.method,
            }, function(res)
                result = res
                coroutine.resume(co)
                UIManager.INPUT_TIMEOUT = 100 -- no need in production
            end)
            return coroutine.create(function() coroutine.yield(result) end)
        end
        client:enable("Async")
        coroutine.resume(co)
        UIManager.INPUT_TIMEOUT = 100
        UIManager:runForever()
    end)
    it("should complete POST request", function()
        UIManager:quit()
        local co = coroutine.create(function()
            local info = {user = 'sam', age = '26'}
            local res = client:post_info(info)
            UIManager:quit()
            assert.are.same(res.body.json, info)
        end)
        require('Spore.Middleware.Async').call = function(self, req)
            req:finalize()
            local result
            async_http_client:request({
                url = req.url,
                method = req.method,
            }, function(res)
                result = res
                coroutine.resume(co)
                UIManager.INPUT_TIMEOUT = 100 -- no need in production
            end)
            return coroutine.create(function() coroutine.yield(result) end)
        end
        client:enable("Async")
        coroutine.resume(co)
        UIManager.INPUT_TIMEOUT = 100
        UIManager:runForever()
    end)
end)
