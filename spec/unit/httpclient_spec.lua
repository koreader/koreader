require("commonrequire")
local UIManager = require("ui/uimanager")
local HTTPClient = require("httpclient")
local DEBUG = require("dbg")
--DEBUG:turnOn()

describe("HTTP client module", function()
    local requests = 0
    local function response_callback(res)
        requests = requests - 1
        if requests == 0 then UIManager:quit() end
        assert(res.body)
    end
    local function error_callback(res)
        requests = requests - 1
        if requests == 0 then UIManager:quit() end
        assert(false, "error occurs")
    end
    local async_client = HTTPClient:new()
    it("should get response from async GET request", function()
        UIManager:quit()
        local urls = {
            "http://www.example.com",
            "http://www.example.org",
            "https://www.example.com",
            "https://www.example.org",
        }
        requests = #urls
        for _, url in ipairs(urls) do
            async_client:request({
                url = url,
            }, response_callback, error_callback)
        end
        UIManager:runForever()
    end)
end)
