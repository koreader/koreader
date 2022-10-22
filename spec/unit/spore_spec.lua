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

describe("Lua Spore modules #notest #nocov", function()
    local Spore, client
    setup(function()
        require("commonrequire")
        Spore = require("Spore")
        client = Spore.new_from_string(service)
        client:enable('Format.JSON')
    end)

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

describe("Lua Spore modules with async http request #notest #nocov", function()
    local client, UIManager

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        local HTTPClient = require("httpclient")
        local Spore = require("Spore")
        client = Spore.new_from_string(service)
        local async_http_client = HTTPClient:new()
        package.loaded['Spore.Middleware.AsyncHTTP'] = {}
        require('Spore.Middleware.AsyncHTTP').call = function(args, req)
            req:finalize()
            local result
            async_http_client:request({
                url = req.url,
                method = req.method,
                body = req.env.spore.payload,
                on_headers = function(headers)
                    for header, value in pairs(req.headers) do
                        if type(header) == 'string' then
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
                UIManager.INPUT_TIMEOUT = 100 -- no need in production
            end)
            return coroutine.create(function() coroutine.yield(result) end)
        end
    end)

    it("should complete GET request", function()
        UIManager:quit()
        local co = coroutine.create(function()
            local info = {user = 'john', age = '25'}
            local res = client:get_info(info)
            UIManager:quit()
            assert.are.same(res.body.args, info)
        end)
        client:reset_middlewares()
        client:enable("Format.JSON")
        client:enable("AsyncHTTP", {thread = co})
        coroutine.resume(co)
        UIManager:setRunForeverMode()
        UIManager:run()
    end)

    it("should complete POST request", function()
        UIManager:quit()
        local co = coroutine.create(function()
            local info = {user = 'sam', age = '26'}
            local res = client:post_info(info)
            UIManager:quit()
            assert.are.same(res.body.json, info)
        end)
        client:reset_middlewares()
        client:enable("Format.JSON")
        client:enable("AsyncHTTP", {thread = co})
        coroutine.resume(co)
        UIManager:setRunForeverMode()
        UIManager:run()
    end)
end)
