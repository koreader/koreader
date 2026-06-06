describe("WebDAV URL normalization", function()
    local WebDavApi, WebDav, socket_http
    local old_path = package.path

    setup(function()
        require("commonrequire")
        package.path = "plugins/cloudstorage.koplugin/providers/?.lua;" .. package.path
        WebDavApi = require("apps/cloudstorage/webdavapi")
        WebDav = require("webdav")
        socket_http = require("socket.http")
    end)

    teardown(function()
        package.path = old_path
    end)

    local function with_mock(target, field, replacement, callback)
        local old = target[field]
        target[field] = replacement
        local ok, err = pcall(callback)
        target[field] = old
        if not ok then
            error(err)
        end
    end

    describe("frontend WebDAV API", function()
        it("normalizes dav:// and davs:// in listFolder", function()
            local cases = {
                { input = "dav://example.com/dav", expected = "http://example.com/dav/" },
                { input = "davs://example.com/dav", expected = "https://example.com/dav/" },
                { input = "http://example.com/dav", expected = "http://example.com/dav/" },
                { input = "https://example.com/dav", expected = "https://example.com/dav/" },
            }

            for _, case in ipairs(cases) do
                local requested_url
                with_mock(socket_http, "request", function(request)
                    requested_url = request.url
                    return nil, "mock error to abort request"
                end, function()
                    WebDavApi:listFolder(case.input, "user", "pass", "", false)
                end)
                assert.equals(case.expected, requested_url)
            end
        end)
    end)

    describe("plugin WebDAV provider", function()
        it("normalizes dav:// and davs:// in listFolder", function()
            local cases = {
                { input = "dav://example.com/dav", expected = "http://example.com/dav/" },
                { input = "davs://example.com/dav", expected = "https://example.com/dav/" },
                { input = "http://example.com/dav", expected = "http://example.com/dav/" },
                { input = "https://example.com/dav", expected = "https://example.com/dav/" },
            }

            for _, case in ipairs(cases) do
                local requested_url
                with_mock(socket_http, "request", function(request)
                    requested_url = request.url
                    return nil, "mock error to abort request"
                end, function()
                    WebDav.base = {
                        address = case.input,
                        username = "user",
                        password = "pass",
                    }
                    WebDav.listFolder("", true)
                end)
                assert.equals(case.expected, requested_url)
            end
        end)

        it("handles invalid URL schemes without crashing", function()
            WebDav.base = {
                address = "htp://example.com/dav",
                username = "user",
                password = "pass",
            }
            local success, res = pcall(function()
                return WebDav.listFolder("", true)
            end)
            assert.is_true(success)
            assert.is_nil(res)
        end)
    end)
end)
