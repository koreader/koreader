require("commonrequire")
local UIManager = require("ui/uimanager")
local HTTPClient = require("httpclient")
local DEBUG = require("dbg")
--DEBUG:turnOn()

-- set true to test httpclient
DUSE_TURBO_LIB = false

describe("HTTP client module #notest #nocov", function()
    local requests = 0
    local function response_callback(res)
        requests = requests - 1
        if requests == 0 then UIManager:quit() end
        assert(not res.error, "error occurs")
        assert(res.body)
    end
    local async_client = HTTPClient:new()
    it("should get response from async GET request", function()
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
