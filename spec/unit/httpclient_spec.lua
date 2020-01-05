-- set true to test httpclient
DUSE_TURBO_LIB = false --luacheck: ignore

describe("HTTP client module #notest #nocov", function()
    local UIManager
    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
    end)

    local requests = 0
    local function response_callback(res)
        requests = requests - 1
        if requests == 0 then UIManager:quit() end
        assert(not res.error, "error occurs")
        assert(res.body)
    end

    it("should get response from async GET request", function()
        local HTTPClient = require("httpclient")
        local async_client = HTTPClient:new()
        UIManager:quit()
        local urls = {
            "http://www.example.com",
            "http://www.example.org",
            "http://www.example.net",
            "https://www.example.com",
            "https://www.example.org",
        }
        requests = #urls
        for _, url in ipairs(urls) do
            async_client:request({
                url = url,
            }, response_callback)
        end
        UIManager:runForever()
    end)
end)
