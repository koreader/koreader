describe("Calibre-Web", function()
    local CalibreWebClient
    local lfs, util
    local orig_path
    local tmp_root

    setup(function()
        orig_path = package.path
        package.path = "plugins/opds.koplugin/?.lua;" .. package.path
        require("commonrequire")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
        CalibreWebClient = require("calibrewebclient")
        tmp_root = os.getenv("TMPDIR") or "/tmp"
        tmp_root = tmp_root .. "/calibreweb_spec_" .. tostring(os.time()) .. "_" .. tostring(math.random(1e6))
        lfs.mkdir(tmp_root)
    end)

    teardown(function()
        package.path = orig_path
        os.execute("rm -rf '" .. tmp_root .. "'")
    end)

    local function makeDir(name)
        local dir = tmp_root .. "/" .. name
        os.execute("rm -rf '" .. dir .. "'")
        util.makePath(dir)
        return dir
    end

    local function writeFile(path, content)
        local f = assert(io.open(path, "wb"))
        f:write(content)
        f:close()
    end

    local function readFile(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return content
    end

    -- Fake transport: `routes["GET /path"] = function(req, body) return code, headers, body end`
    local function fakeServer(routes)
        local server = { requests = {}, posts = 0 }
        server.request = function(_, req)
            local key = (req.method or "GET") .. " " .. req.url
            local body_chunks, max_chunk = {}, 0
            if req.source then
                server.posts = server.posts + 1
                while true do
                    local chunk, err = req.source()
                    if err then return err end
                    if not chunk then break end
                    max_chunk = math.max(max_chunk, #chunk)
                    table.insert(body_chunks, chunk)
                end
            end
            local recorded = {
                method = req.method or "GET", url = req.url, headers = req.headers,
                username = req.username, password = req.password, follow_redirects = req.follow_redirects,
                body = table.concat(body_chunks), max_chunk = max_chunk,
            }
            table.insert(server.requests, recorded)
            local handler = routes[key]
            if not handler then return 404, {}, "HTTP 404" end
            local code, headers, body = handler(recorded)
            if type(code) == "string" then return code end -- network error
            if body and req.sink then
                for i = 1, #body, 7 do
                    local ok, err = req.sink(body:sub(i, i + 6))
                    if not ok then return err end
                end
                req.sink(nil)
            end
            return code, headers or {}, "HTTP " .. code
        end
        return server
    end

    local function newClient(routes, base_url)
        local server = fakeServer(routes)
        local client = CalibreWebClient:new{
            base_url = base_url or "http://nas.local:8083",
            username = "reader",
            password = "secret",
            http_client = server,
        }
        return client, server
    end

    local function entryXml(uuid, id, title, author, formats, extra_links)
        local links = {}
        for _, f in ipairs(formats) do
            table.insert(links, string.format(
                '<link rel="http://opds-spec.org/acquisition" href="%s/opds/download/%d/%s/" length="%d" title="%s" type="application/epub+zip"/>',
                f.prefix or "", id, f.name:lower(), f.length or 10, f.name))
        end
        return string.format([[
  <entry>
    <title>%s</title>
    <id>urn:uuid:%s</id>
    <updated>2024-01-01T00:00:00+00:00</updated>
    <author><name>%s</name></author>
    <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>Text</p></div></content>
    %s%s
  </entry>]], title, uuid, author, table.concat(links), extra_links or "")
    end

    local function feedXml(entries, next_href)
        return [[<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:uuid:2853dacf-ed79-42f5-8e8a-a7bb3d1ae6a2</id>
  <title>Calibre-Web</title>
  <author><name>Calibre-Web</name><uri>https://github.com/janeczku/calibre-web</uri></author>
  ]] .. (next_href and ('<link rel="next" href="' .. next_href .. '" type="application/atom+xml"/>') or "")
        .. table.concat(entries) .. "\n</feed>"
    end

    local atom = { ["content-type"] = "application/atom+xml; charset=utf-8" }

    describe("URL normalization", function()
        it("should canonicalize server URLs and keep reverse proxy sub-paths", function()
            local n = CalibreWebClient.normalizeBaseUrl
            assert.are.same("http://192.168.1.105:8083", n("192.168.1.105:8083"))
            assert.are.same("http://192.168.1.105:8083", n(" http://192.168.1.105:8083/ "))
            assert.are.same("https://books.example.test", n("HTTPS://Books.Example.test:443/"))
            assert.are.same("http://nas.local/calibre", n("http://nas.local:80/calibre/"))
            assert.are.same("https://nas.local/calibre", n("https://nas.local/calibre/opds"))
            assert.are.same("http://nas.local:8083", n("http://nas.local:8083/login?next=/"))
        end)

        it("should reject invalid URLs", function()
            local n = CalibreWebClient.normalizeBaseUrl
            assert.is_nil(n(""))
            assert.is_nil(n("ftp://nas.local"))
            assert.is_nil(n("javascript:alert(1)"))
            assert.is_nil(n("http://user:pass@nas.local"))
            assert.is_nil(n("http://nas.local:99999"))
            assert.is_nil(n("http:///path"))
        end)

        it("should keep accounts on different servers or users apart", function()
            local a = CalibreWebClient.accountKey("http://nas.local:8083", "Reader")
            assert.are.same(a, CalibreWebClient.accountKey("http://nas.local:8083", "reader"))
            assert.are_not.same(a, CalibreWebClient.accountKey("http://nas.local:8084", "reader"))
            assert.are_not.same(a, CalibreWebClient.accountKey("http://nas.local:8083", "other"))
        end)

        it("should scope links to the configured base path", function()
            assert.is_true(CalibreWebClient.isWithinBase("http://nas.local/calibre", "http://nas.local/calibre/opds/download/1/epub/"))
            assert.is_false(CalibreWebClient.isWithinBase("http://nas.local/calibre", "http://nas.local/calibre2/x"))
            assert.is_false(CalibreWebClient.isWithinBase("http://nas.local/calibre", "http://evil.test/calibre/x"))
            assert.is_false(CalibreWebClient.isWithinBase("https://nas.local", "http://nas.local/x"))
            assert.is_true(CalibreWebClient.isWithinBase("http://nas.local:80", "http://nas.local/x"))
        end)
    end)

    describe("certificate host verification", function()
        local function cert(dns, cn, ips)
            return {
                extensions = function() return { ["2.5.29.17"] = { dNSName = dns, iPAddress = ips } } end,
                subject = function() return { { oid = "2.5.4.3", value = cn } } end,
            }
        end

        it("should match subjectAltName entries, including single-label wildcards", function()
            assert.is_true(CalibreWebClient.certificateMatchesHost(cert({ "books.example.test" }), "Books.Example.test"))
            assert.is_true(CalibreWebClient.certificateMatchesHost(cert({ "*.example.test" }), "books.example.test"))
            assert.is_false(CalibreWebClient.certificateMatchesHost(cert({ "*.example.test" }), "a.b.example.test"))
            assert.is_false(CalibreWebClient.certificateMatchesHost(cert({ "other.test" }, "books.example.test"), "books.example.test"))
        end)

        it("should match IP addresses only against IP SANs", function()
            assert.is_true(CalibreWebClient.certificateMatchesHost(cert(nil, "x", { "192.168.1.105" }), "192.168.1.105"))
            assert.is_false(CalibreWebClient.certificateMatchesHost(cert({ "192.168.1.105" }, "192.168.1.105"), "192.168.1.105"))
        end)

        it("should fall back to the common name without DNS SANs", function()
            assert.is_true(CalibreWebClient.certificateMatchesHost(cert(nil, "books.example.test"), "books.example.test"))
        end)
    end)

    describe("server addresses", function()
        it("should store links relative to the server and resolve them through any address", function()
            local lan = CalibreWebClient:new{ base_url = "http://192.168.1.105:8083", http_client = {} }
            local vpn = CalibreWebClient:new{ base_url = "https://nas.tail.ts.net/calibre", http_client = {} }
            assert.are.same("/opds/download/1/epub/", lan:relativeHref("http://192.168.1.105:8083/opds/download/1/epub/"))
            assert.are.same("/opds/cover/1?x=1", vpn:relativeHref("https://nas.tail.ts.net/calibre/opds/cover/1?x=1"))
            assert.are.same("https://nas.tail.ts.net/calibre/opds/download/1/epub/", vpn:resolveHref("/opds/download/1/epub/"))
            -- absolute links cached by an older version are re-based onto the active address
            vpn.alt_bases = { "http://192.168.1.105:8083" }
            assert.are.same("https://nas.tail.ts.net/calibre/opds/download/1/epub/",
                vpn:resolveHref("http://192.168.1.105:8083/opds/download/1/epub/"))
            -- unknown hosts stay foreign
            assert.are.same("http://evil.test/x", vpn:resolveHref("http://evil.test/x"))
        end)
    end)

    describe("catalog", function()
        it("should follow pagination, deduplicate and record completeness", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({
                        entryXml("u-1", 1, "First", "Ann", { { name = "EPUB" }, { name = "PDF" } }),
                        entryXml("u-2", 2, "Second", "Bob", { { name = "EPUB" } }),
                    }, "/opds/books/letter/00?offset=2")
                end,
                ["GET http://nas.local:8083/opds/books/letter/00?offset=2"] = function()
                    return 200, atom, feedXml({
                        entryXml("u-2", 2, "Second", "Bob", { { name = "EPUB" } }),
                        entryXml("u-3", 3, "Third &amp; Last", "Cy", { { name = "MOBI" } }),
                    })
                end,
            }
            local snapshot = client:fetchCatalog()
            assert.is_true(snapshot.complete)
            assert.are.same(3, snapshot.count)
            assert.are.same(2, snapshot.pages)
            local first = snapshot.books["u-1"]
            assert.are.same("First", first.title)
            assert.are.same({ "Ann" }, first.authors)
            assert.are.same(1, first.id)
            assert.are.same("/opds/download/1/epub/", first.formats.EPUB.href)
            assert.is_not_nil(first.formats.PDF)
            assert.are.same("Third & Last", snapshot.books["u-3"].title)
            assert.are.same("reader", server.requests[1].username)
            assert.are.same("secret", server.requests[1].password)
        end)

        it("should keep reverse proxy sub-paths in requests and links", function()
            local client = newClient({
                ["GET https://nas.local/calibre/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({
                        entryXml("u-1", 1, "First", "Ann", { { name = "EPUB", prefix = "/calibre" } }),
                    })
                end,
            }, "https://nas.local/calibre")
            local snapshot = client:fetchCatalog()
            assert.is_true(snapshot.complete)
            assert.are.same("/opds/download/1/epub/", snapshot.books["u-1"].formats.EPUB.href)
        end)

        it("should ignore acquisition links pointing outside the server", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({
                        entryXml("u-1", 1, "First", "Ann", { { name = "EPUB", prefix = "http://evil.test" } }),
                    })
                end,
            }
            local snapshot = client:fetchCatalog()
            local book = snapshot.books["u-1"]
            assert.is_nil(book.formats.EPUB)
            assert.is_true(book.foreign_links)
        end)

        it("should detect pagination cycles", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({ entryXml("u-1", 1, "A", "B", { { name = "EPUB" } }) },
                        "/opds/books/letter/00")
                end,
            }
            local snapshot = client:fetchCatalog()
            assert.is_false(snapshot.complete)
            assert.are.same("cycle", snapshot.error)
        end)

        it("should report a page failure as incomplete", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({ entryXml("u-1", 1, "A", "B", { { name = "EPUB" } }) },
                        "/opds/books/letter/00?offset=1")
                end,
                ["GET http://nas.local:8083/opds/books/letter/00?offset=1"] = function()
                    return 500, {}, "boom"
                end,
            }
            local snapshot = client:fetchCatalog()
            assert.is_false(snapshot.complete)
            assert.are.same("http", snapshot.error)
            assert.are.same(1, snapshot.count)
        end)

        it("should support cancellation", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({ entryXml("u-1", 1, "A", "B", { { name = "EPUB" } }) },
                        "/opds/books/letter/00?offset=1")
                end,
            }
            local snapshot = client:fetchCatalog(function() return false end)
            assert.is_false(snapshot.complete)
            assert.are.same("cancelled", snapshot.error)
        end)

        it("should recognize authentication failures and login pages", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds"] = function()
                    return 401, {}, ""
                end,
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, { ["content-type"] = "text/html" }, "<html><form><input name=\"password\"></form></html>"
                end,
            }
            assert.are.same("auth", client:checkConnection().error)
            assert.are.same("html", client:fetchCatalog().error)
        end)

        it("should escape the Basic auth password for LuaSocket", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/opds"] = function() return 200, atom, feedXml({}) end,
            }
            client.password = "ab%41 cd"
            client:checkConnection()
            assert.are.same("ab%41 cd", require("socket.url").unescape(server.requests[1].password))
        end)

        it("should identify a Calibre-Web server", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds"] = function()
                    return 200, atom, feedXml({})
                end,
            }
            local result = client:checkConnection()
            assert.is_true(result.ok)
            assert.is_true(result.is_calibre_web)
        end)

        it("should refuse HTTPS without a CA bundle instead of skipping verification", function()
            local client = CalibreWebClient:new{
                base_url = "https://nas.local",
                ca_bundle = tmp_root .. "/missing.crt",
            }
            assert.is_true(client.no_ca_bundle)
            assert.are.same("tls_unavailable", client:checkConnection().error)
        end)
    end)

    describe("covers and metadata", function()
        it("should parse the publication year and ignore Calibre's undefined date", function()
            assert.are.same(1999, CalibreWebClient.parseYear("1999-05-01T00:00:00+00:00"))
            assert.is_nil(CalibreWebClient.parseYear("0101-01-01T00:00:00+00:00"))
            assert.is_nil(CalibreWebClient.parseYear(nil))
        end)

        it("should read the year and prefer the thumbnail cover link", function()
            local client = newClient{
                ["GET http://nas.local:8083/opds/books/letter/00"] = function()
                    return 200, atom, feedXml({
                        entryXml("u-1", 1, "First", "Ann", { { name = "EPUB" } },
                            '<published>1987-03-04T00:00:00+00:00</published>'
                            .. '<link type="image/jpeg" href="/opds/cover/1" rel="http://opds-spec.org/image"/>'
                            .. '<link type="image/jpeg" href="/opds/cover_240_240/1" rel="http://opds-spec.org/image/thumbnail"/>'),
                    })
                end,
            }
            local book = client:fetchCatalog().books["u-1"]
            assert.are.same(1987, book.year)
            assert.are.same("/opds/cover_240_240/1", book.cover_href)
        end)

        it("should only cache real images from the server", function()
            local dir = makeDir("covers")
            local jpeg = "\255\216\255\224" .. string.rep("x", 50)
            local client, server = newClient{
                ["GET http://nas.local:8083/opds/cover/1"] = function() return 200, {}, jpeg end,
                ["GET http://nas.local:8083/opds/cover/2"] = function() return 200, {}, "<html>login</html>" end,
                ["GET http://nas.local:8083/opds/cover/3"] = function() return 200, {}, string.rep("y", 100) end,
            }
            assert.is_true(client:fetchCover("http://nas.local:8083/opds/cover/1", dir .. "/1.img"))
            assert.are.same(jpeg, readFile(dir .. "/1.img"))
            assert.are.same("reader", server.requests[1].username)
            assert.are.same("not_image", select(2, client:fetchCover("http://nas.local:8083/opds/cover/2", dir .. "/2.img")))
            assert.is_nil(readFile(dir .. "/2.img"))
            client.max_cover_size = 10
            assert.are.same("too_large", select(2, client:fetchCover("http://nas.local:8083/opds/cover/3", dir .. "/3.img")))
            assert.are.same("foreign_link", select(2, client:fetchCover("http://evil.test/c.jpg", dir .. "/4.img")))
        end)
    end)

    describe("login", function()
        local login_page = [[<html><form method="POST" action="/login">
            <input type="hidden" name="csrf_token" value="tok&amp;en"/>
            <input type="text" name="username"><input type="password" name="password"></form></html>]]
        local index_page = [[<html><meta name="csrf-token" content="fresh-token"></html>]]

        it("should post the CSRF token and credentials once, without Basic auth", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/login"] = function() return 200, { ["content-type"] = "text/html" }, login_page end,
                ["POST http://nas.local:8083/login"] = function() return 302, { location = "/" } end,
                ["GET http://nas.local:8083/"] = function() return 200, { ["content-type"] = "text/html" }, index_page end,
            }
            local result = client:login()
            assert.is_true(result.ok)
            assert.is_true(client.logged_in)
            assert.are.same("fresh-token", client.csrf_token)
            local post = server.requests[2]
            assert.are.same("POST", post.method)
            assert.is_nil(post.username)
            assert.is_truthy(post.body:find("csrf_token=tok%26en", 1, true))
            assert.is_truthy(post.body:find("username=reader", 1, true))
            assert.is_truthy(post.body:find("password=secret", 1, true))
            assert.are.same(tostring(#post.body), post.headers["Content-Length"])
            assert.are.same(1, server.posts)
        end)

        it("should reuse a session already established by a reverse proxy", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/login"] = function() return 302, { location = "/" } end,
                ["GET http://nas.local:8083/"] = function() return 200, {}, index_page end,
            }
            assert.is_true(client:login().ok)
            assert.is_false(server.requests[1].follow_redirects)
            assert.are.same(0, server.posts)
        end)

        it("should report wrong credentials without retrying", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/login"] = function() return 200, {}, login_page end,
                ["POST http://nas.local:8083/login"] = function() return 401, {}, login_page end,
            }
            assert.are.same("auth", client:login().error)
            assert.is_false(client.logged_in)
            assert.are.same(1, server.posts)
        end)

        it("should report rate limiting and CSRF failures", function()
            local client = newClient{
                ["GET http://nas.local:8083/login"] = function() return 200, {}, login_page end,
                ["POST http://nas.local:8083/login"] = function() return 429, {}, "" end,
            }
            assert.are.same("rate_limited", client:login().error)
            client = newClient{
                ["GET http://nas.local:8083/login"] = function() return 200, {}, login_page end,
                ["POST http://nas.local:8083/login"] = function() return 400, {}, "The CSRF token is missing." end,
            }
            assert.are.same("csrf", client:login().error)
        end)

        it("should treat a redirect back to the login page as a failure", function()
            local client = newClient{
                ["GET http://nas.local:8083/login"] = function() return 200, {}, login_page end,
                ["POST http://nas.local:8083/login"] = function() return 302, { location = "/login?next=%2F" } end,
            }
            assert.are.same("auth", client:login().error)
        end)

        it("should report single sign-on and login pages without a password form", function()
            local client, server = newClient{
                ["GET http://nas.local:8083/login"] = function()
                    return 302, { location = "https://sso.example.test/authorize" }
                end,
            }
            assert.are.same("sso", client:login().error)
            assert.are.same(0, server.posts)
            client = newClient{
                ["GET http://nas.local:8083/login"] = function()
                    return 200, {}, "<html><a href='/login/github'>GitHub</a></html>"
                end,
            }
            assert.are.same("unsupported", client:login().error)
        end)
    end)

    describe("upload", function()
        local function loggedIn(routes)
            local client, server = newClient(routes)
            client.logged_in = true
            client.csrf_token = "tok"
            client.upload_chunk_size = 1000
            return client, server
        end

        local function binaryContent(size)
            local bytes = {}
            for i = 1, size do bytes[i] = string.char((i * 7) % 256) end
            return table.concat(bytes)
        end

        it("should stream a bounded multipart body with an exact Content-Length", function()
            local dir = makeDir("upload_ok")
            local content = binaryContent(5000)
            writeFile(dir .. "/book.epub", content)
            local client, server = loggedIn{
                ["POST http://nas.local:8083/upload"] = function()
                    return 200, { ["content-type"] = "application/json" }, '{"location": "/admin/book/42"}'
                end,
            }
            local result = client:upload(dir .. "/book.epub", 'My "Book"\r\n.epub')
            assert.are.same("uploaded", result.status)
            assert.are.same(42, result.book_id)
            local post = server.requests[1]
            assert.are.same(tostring(#post.body), post.headers["Content-Length"])
            assert.is_true(post.max_chunk <= 1000 + 300)
            assert.are.same("tok", post.headers["X-CSRFToken"])
            assert.is_truthy(post.body:find('name="btn-upload"; filename="My %22Book%22%0D%0A.epub"', 1, true))
            assert.is_truthy(post.body:find('name="csrf_token"\r\n\r\ntok\r\n', 1, true))
            local boundary = post.headers["Content-Type"]:match("boundary=(.+)$")
            local file_part = post.body:match("Content%-Type: application/octet%-stream\r\n\r\n(.*)\r\n%-%-" .. boundary:gsub("%-", "%%-") .. "%-%-\r\n$")
            assert.are.same(content, file_part)
        end)

        it("should accept the non-editor book location", function()
            local dir = makeDir("upload_viewer")
            writeFile(dir .. "/book.epub", "x")
            local client = loggedIn{
                ["POST http://nas.local:8083/upload"] = function() return 200, {}, '{"location": "/calibre/book/7"}' end,
            }
            assert.are.same(7, client:upload(dir .. "/book.epub", "book.epub").book_id)
        end)

        it("should not trust HTTP 200 with a generic location", function()
            local dir = makeDir("upload_generic")
            writeFile(dir .. "/book.epub", "x")
            local client = loggedIn{
                ["POST http://nas.local:8083/upload"] = function() return 200, {}, '{"location": "/"}' end,
            }
            local result = client:upload(dir .. "/book.epub", "book.epub")
            assert.are.same("rejected", result.status)
            assert.is_nil(result.book_id)
        end)

        it("should report an interrupted response after a complete body as uncertain, without retrying", function()
            local dir = makeDir("upload_uncertain")
            writeFile(dir .. "/book.epub", binaryContent(3000))
            local client, server = loggedIn{
                ["POST http://nas.local:8083/upload"] = function() return "timeout" end,
            }
            local result = client:upload(dir .. "/book.epub", "book.epub")
            assert.are.same("uncertain", result.status)
            assert.are.same(1, server.posts)
        end)

        it("should report a failure before the body was sent as failed", function()
            local dir = makeDir("upload_cancel")
            writeFile(dir .. "/book.epub", binaryContent(3000))
            local client = loggedIn{
                ["POST http://nas.local:8083/upload"] = function() return 200, {}, '{"location": "/book/1"}' end,
            }
            local result = client:upload(dir .. "/book.epub", "book.epub", function()
                error("connection reset")
            end)
            assert.are.same("failed", result.status)
        end)

        it("should handle expired sessions, permissions and login HTML", function()
            local dir = makeDir("upload_errors")
            writeFile(dir .. "/book.epub", "x")
            local cases = {
                { 302, { location = "/login?next=%2Fupload" }, "", "auth_required" },
                { 403, {}, "", "forbidden" },
                { 400, {}, "The CSRF token has expired.", "csrf" },
                { 200, { ["content-type"] = "text/html" }, '<form><input name="password"></form>', "auth_required" },
            }
            for _, case in ipairs(cases) do
                local client = loggedIn{
                    ["POST http://nas.local:8083/upload"] = function() return case[1], case[2], case[3] end,
                }
                local result = client:upload(dir .. "/book.epub", "book.epub")
                assert.are.same("failed", result.status)
                assert.are.same(case[4], result.error)
            end
        end)

        it("should require a session", function()
            local client = newClient{}
            assert.are.same("auth_required", client:upload("/nonexistent", "x.epub").error)
        end)

        it("should look up an uploaded book's UUID", function()
            local client = loggedIn{
                ["GET http://nas.local:8083/ajax/listbooks?sort=id&order=desc&offset=0&limit=50"] = function()
                    return 200, { ["content-type"] = "application/json" },
                        '{"total": 2, "rows": [{"id": 43, "uuid": "other"}, {"id": 42, "uuid": "u-42", "title": "Mine"}]}'
                end,
            }
            local book = client:lookupBookById(42)
            assert.are.same("u-42", book.uuid)
            assert.is_nil(client:lookupBookById(1))
        end)
    end)

    describe("download", function()
        local function bookFormat(href)
            return { format = "EPUB", href = href or "http://nas.local:8083/opds/download/1/epub/" }
        end

        it("should write binary content and never overwrite an existing file", function()
            local dir = makeDir("download_ok")
            writeFile(dir .. "/Title - Author.epub", "existing")
            local content = "PK\0\1\2\3binary\255\254"
            local client, server = newClient{
                ["GET http://nas.local:8083/opds/download/1/epub/"] = function()
                    return 200, { ["content-length"] = tostring(#content), ["content-type"] = "application/epub+zip" }, content
                end,
            }
            local result = client:download(bookFormat(), dir, "Title - Author.epub")
            assert.is_true(result.ok)
            assert.are.same(dir .. "/Title - Author (2).epub", result.path)
            assert.are.same(content, readFile(result.path))
            assert.are.same("existing", readFile(dir .. "/Title - Author.epub"))
            assert.are.same("reader", server.requests[1].username)
            for f in lfs.dir(dir) do assert.is_falsy(f:match("%.cwpart$")) end
        end)

        local function assertNoPartial(dir)
            for f in lfs.dir(dir) do
                if f ~= "." and f ~= ".." then error("unexpected file left behind: " .. f) end
            end
        end

        it("should clean up after truncated, HTML, failed or cancelled transfers", function()
            local cases = {
                { "truncated", function() return 200, { ["content-length"] = "100" }, "short" end },
                { "html", function() return 200, { ["content-type"] = "text/html" }, "<!DOCTYPE html><html>login</html>" end },
                { "auth", function() return 401, {}, "nope" end },
                { "network", function() return "closed" end },
            }
            for _, case in ipairs(cases) do
                local dir = makeDir("download_" .. case[1])
                local client = newClient{ ["GET http://nas.local:8083/opds/download/1/epub/"] = case[2] }
                local result = client:download(bookFormat(), dir, "book.epub")
                assert.is_false(result.ok)
                assert.are.same(case[1], result.error)
                assertNoPartial(dir)
            end
            local dir = makeDir("download_cancel")
            local client = newClient{
                ["GET http://nas.local:8083/opds/download/1/epub/"] = function() return 200, {}, string.rep("x", 100) end,
            }
            local result = client:download(bookFormat(), dir, "book.epub", function() return true end)
            assert.are.same("cancelled", result.error)
            assertNoPartial(dir)
        end)

        it("should refuse links outside the server and missing folders", function()
            local dir = makeDir("download_foreign")
            local client = newClient{}
            assert.are.same("foreign_link", client:download(bookFormat("http://evil.test/x"), dir, "a.epub").error)
            assert.are.same("no_dir", client:download(bookFormat(), dir .. "/missing", "a.epub").error)
        end)
    end)

    describe("index", function()
        local CalibreWebIndex
        local function isEpub(path) return path:match("%.epub$") ~= nil end

        setup(function()
            CalibreWebIndex = require("calibrewebindex")
        end)

        describe("roots", function()
            it("should drop the filesystem root, duplicates and nested roots", function()
                local dir = makeDir("roots")
                util.makePath(dir .. "/inner")
                local roots = CalibreWebIndex.normalizeRoots{
                    { path = "/", kind = "user" },
                    { path = dir .. "/inner/", kind = "user" },
                    { path = dir, kind = "home" },
                    { path = dir .. "/", kind = "device" },
                }
                assert.are.same(1, #roots)
                assert.are.same(dir, roots[1].path)
                assert.are.same("home", roots[1].kind)
            end)

            it("should add known external storage and say when enumeration is partial", function()
                local function device(kind)
                    return {
                        home_dir = "/mnt/onboard",
                        isAndroid = function() return kind == "android" end,
                        isKobo = function() return kind == "kobo" end,
                        isCervantes = function() return false end,
                        isPocketBook = function() return false end,
                        isKindle = function() return false end,
                        isRemarkable = function() return false end,
                        hasExternalSD = function() return true, "/storage/sd" end,
                    }
                end
                local roots, complete = CalibreWebIndex.discoverRoots(device("kobo"), "/mnt/onboard", { "/mnt/usb" })
                assert.is_true(complete)
                local paths = {}
                for _, r in ipairs(roots) do paths[r.path] = r.kind end
                assert.are.same("external", paths["/mnt/sd"])
                assert.are.same("user", paths["/mnt/usb"])
                roots, complete = CalibreWebIndex.discoverRoots(device("android"), "/storage/emulated/0")
                assert.is_false(complete)
                paths = {}
                for _, r in ipairs(roots) do paths[r.path] = r.kind end
                assert.are.same("external", paths["/storage/sd"])
                complete = select(2, CalibreWebIndex.discoverRoots(device("other"), "/home/user"))
                assert.is_false(complete)
            end)
        end)

        describe("scan", function()
            it("should find supported books, skip exclusions, hidden folders and links", function()
                local dir = makeDir("scan")
                util.makePath(dir .. "/a/b")
                util.makePath(dir .. "/book.sdr")
                util.makePath(dir .. "/.hidden")
                writeFile(dir .. "/a/one.epub", "1")
                writeFile(dir .. "/a/b/two.epub", "22")
                writeFile(dir .. "/a/notes.txt", "x")
                writeFile(dir .. "/book.sdr/three.epub", "3")
                writeFile(dir .. "/.hidden/four.epub", "4")
                os.execute("ln -s " .. dir .. " " .. dir .. "/a/loop")
                os.execute("ln -s " .. dir .. "/a/one.epub " .. dir .. "/link.epub")
                local inventory = CalibreWebIndex.scan{
                    roots = { { path = dir } },
                    is_supported = isEpub,
                    exclude_dirs = { "%.sdr$" },
                }
                assert.is_true(inventory.complete)
                assert.are.same(2, inventory.count)
                assert.is_not_nil(inventory.files[dir .. "/a/one.epub"])
                assert.are.same(2, inventory.files[dir .. "/a/b/two.epub"].size)
                assert.are.same(2, inventory.skipped_links)
                assert.are.same("ok", inventory.roots[dir])
            end)

            it("should report missing storage and unreadable folders as incomplete", function()
                local dir = makeDir("scan_partial")
                util.makePath(dir .. "/locked")
                writeFile(dir .. "/locked/x.epub", "x")
                writeFile(dir .. "/ok.epub", "x")
                os.execute("chmod 000 " .. dir .. "/locked")
                finally(function() os.execute("chmod 755 " .. dir .. "/locked") end)
                local inventory = CalibreWebIndex.scan{
                    roots = { { path = dir }, { path = dir .. "_unplugged_sd" } },
                    is_supported = isEpub,
                }
                assert.is_false(inventory.complete)
                assert.are.same("missing", inventory.roots[dir .. "_unplugged_sd"])
                assert.is_not_nil(inventory.files[dir .. "/ok.epub"])
                -- root can read everything: only check the unreadable folder when it really is unreadable
                if not io.open(dir .. "/locked/x.epub") then
                    assert.are.same("partial", inventory.roots[dir])
                    assert.is_true(inventory.unreadable[dir .. "/locked"])
                end
            end)

            it("should be cancellable and keep cached metadata of unchanged files", function()
                local dir = makeDir("scan_cancel")
                for i = 1, 30 do util.makePath(dir .. "/d" .. i) end
                writeFile(dir .. "/d1/x.epub", "x")
                local cancelled = CalibreWebIndex.scan{
                    roots = { { path = dir } },
                    is_supported = isEpub,
                    should_continue = function() return false end,
                }
                assert.is_false(cancelled.complete)
                assert.is_true(cancelled.cancelled)
                local first = CalibreWebIndex.scan{ roots = { { path = dir } }, is_supported = isEpub }
                first.files[dir .. "/d1/x.epub"].title = "Cached title"
                local second = CalibreWebIndex.scan{ roots = { { path = dir } }, is_supported = isEpub, previous = first }
                assert.are.same("Cached title", second.files[dir .. "/d1/x.epub"].title)
                writeFile(dir .. "/d1/x.epub", "changed")
                local third = CalibreWebIndex.scan{ roots = { { path = dir } }, is_supported = isEpub, previous = second }
                assert.is_nil(third.files[dir .. "/d1/x.epub"].title)
            end)
        end)

        describe("presence", function()
            local dir, now
            local function book(uuid, id, title)
                return { uuid = uuid, key = uuid, id = id, title = title, authors = { "A" },
                         formats = { EPUB = { format = "EPUB", href = "http://nas.local/opds/download/" .. id .. "/epub/" } } }
            end
            local function snapshot(books, complete, age)
                local t = { books = {}, complete = complete ~= false, fetched_at = now - (age or 0) }
                for _, b in ipairs(books) do t.books[b.key] = b end
                return t
            end
            local function inventory(paths, complete)
                local inv = { files = {}, roots = { [dir] = "ok" }, complete = complete ~= false }
                for _, p in ipairs(paths) do inv.files[p] = { size = 1, mtime = 1, root = dir } end
                return inv
            end
            local function byKey(rows)
                local t = {}
                for _, r in ipairs(rows) do t[r.key] = r end
                return t
            end
            local function newAccount() return { mappings = {}, pending_uploads = {} } end

            before_each(function()
                dir = makeDir("presence")
                now = os.time()
            end)

            it("should derive Both, Remote only and Local only from evidence", function()
                writeFile(dir .. "/Mapped.epub", "x")
                writeFile(dir .. "/Unrelated local.epub", "x")
                local account = newAccount()
                local mapped = book("u-1", 1, "Mapped")
                CalibreWebIndex.link(account, mapped, dir .. "/Mapped.epub", "EPUB", "download")
                local rows, summary = CalibreWebIndex.derive{
                    account = account,
                    snapshot = snapshot{ mapped, book("u-2", 2, "Remote book") },
                    inventory = inventory{ dir .. "/Mapped.epub", dir .. "/Unrelated local.epub" },
                    now = now,
                }
                rows = byKey(rows)
                assert.are.same("both", rows["u-1"].status)
                assert.are.same("remote", rows["u-2"].status)
                assert.are.same("local", rows["local:" .. dir .. "/Unrelated local.epub"].status)
                assert.are.same(1, summary.both)
            end)

            it("should stay Unknown without complete, fresh evidence", function()
                writeFile(dir .. "/Local.epub", "x")
                local remote = book("u-2", 2, "Remote book")
                local local_key = "local:" .. dir .. "/Local.epub"
                local cases = {
                    { snapshot{ remote }, inventory({ dir .. "/Local.epub" }, false), "unknown", "local" },
                    { snapshot({ remote }, true, 30 * 24 * 3600), inventory{ dir .. "/Local.epub" }, "remote", "unknown" },
                    { nil, inventory{ dir .. "/Local.epub" }, nil, "unknown" },
                }
                for i, case in ipairs(cases) do
                    local rows = byKey(CalibreWebIndex.derive{
                        account = newAccount(), snapshot = case[1], inventory = case[2], now = now })
                    if case[3] then assert.are.same(case[3], rows["u-2"].status, "case " .. i) end
                    assert.are.same(case[4], rows[local_key].status, "case " .. i)
                end
            end)

            it("should only use partial refreshes as positive evidence", function()
                local rows = byKey(CalibreWebIndex.derive{
                    account = newAccount(),
                    partial_snapshot = snapshot({ book("u-9", 9, "Partial") }, false),
                    inventory = inventory{},
                    now = now,
                })
                assert.are.same("remote", rows["u-9"].status)
            end)

            it("should never silently match by title", function()
                writeFile(dir .. "/Same Title - Someone.epub", "x")
                local rows = byKey(CalibreWebIndex.derive{
                    account = newAccount(),
                    snapshot = snapshot{ book("u-3", 3, "Same title") },
                    inventory = inventory{ dir .. "/Same Title - Someone.epub" },
                    now = now,
                })
                assert.are.same("unknown", rows["u-3"].status)
                assert.are.same("possible_local_copy", rows["u-3"].reason)
                local local_row = rows["local:" .. dir .. "/Same Title - Someone.epub"]
                assert.are.same("unknown", local_row.status)
                assert.are.same({ "u-3" }, local_row.remote_candidates)
            end)

            it("should keep mapped books on removed storage Unknown", function()
                local account = newAccount()
                local sd = dir .. "_sd"
                CalibreWebIndex.link(account, book("u-4", 4, "On SD"), sd .. "/book.epub", "EPUB", "download")
                local inv = inventory{}
                inv.roots[sd] = "missing"
                inv.complete = false
                local rows = byKey(CalibreWebIndex.derive{
                    account = account, snapshot = snapshot{ book("u-4", 4, "On SD") }, inventory = inv, now = now })
                assert.are.same("unknown", rows["u-4"].status)
                assert.are.same("storage_unavailable", rows["u-4"].reason)
            end)

            it("should support several local copies and formats of one book", function()
                writeFile(dir .. "/copy.epub", "x")
                writeFile(dir .. "/copy.pdf", "x")
                local account = newAccount()
                local b = book("u-5", 5, "Copies")
                CalibreWebIndex.link(account, b, dir .. "/copy.epub", "EPUB", "download")
                CalibreWebIndex.link(account, b, dir .. "/copy.pdf", "PDF", "manual")
                local rows = byKey(CalibreWebIndex.derive{
                    account = account, snapshot = snapshot{ b }, inventory = inventory{}, now = now })
                assert.are.same("both", rows["u-5"].status)
                assert.are.same(2, #rows["u-5"].local_paths)
            end)

            it("should not report Both after an uncertain upload", function()
                writeFile(dir .. "/Uploaded.epub", "x")
                local account = newAccount()
                account.pending_uploads[dir .. "/Uploaded.epub"] = { status = "uncertain", format = "EPUB", at = now }
                local rows = byKey(CalibreWebIndex.derive{
                    account = account, snapshot = snapshot{}, inventory = inventory{ dir .. "/Uploaded.epub" }, now = now })
                local row = rows["local:" .. dir .. "/Uploaded.epub"]
                assert.are.same("unknown", row.status)
                assert.are.same("upload_uncertain", row.reason)
            end)

            it("should reconcile verified uploads once the book shows up remotely", function()
                writeFile(dir .. "/Uploaded.epub", "x")
                local account = newAccount()
                account.pending_uploads[dir .. "/Uploaded.epub"] = { status = "unverified", format = "EPUB", book_id = 12 }
                assert.are.same(0, CalibreWebIndex.reconcileUploads(account, {}))
                assert.are.same(1, CalibreWebIndex.reconcileUploads(account, { ["u-12"] = book("u-12", 12, "Uploaded") }))
                assert.is_nil(account.pending_uploads[dir .. "/Uploaded.epub"])
                assert.are.same("upload", account.mappings["u-12"].files[dir .. "/Uploaded.epub"].source)
            end)

            it("should report a mapped book missing from a complete catalog as Local only", function()
                writeFile(dir .. "/Gone.epub", "x")
                local account = newAccount()
                CalibreWebIndex.link(account, book("u-6", 6, "Gone"), dir .. "/Gone.epub", "EPUB", "download")
                local rows = byKey(CalibreWebIndex.derive{
                    account = account, snapshot = snapshot{}, inventory = inventory{}, now = now })
                assert.are.same("local", rows["u-6"].status)
            end)

            it("should move a path to its new remote book and drop mappings on UUID mismatch", function()
                local account = newAccount()
                local path = dir .. "/x.epub"
                CalibreWebIndex.link(account, book("aaaaaaaa-1111-2222-3333-444444444444", 1, "A"), path, "EPUB", "manual")
                CalibreWebIndex.link(account, book("bbbbbbbb-1111-2222-3333-444444444444", 2, "B"), path, "EPUB", "manual")
                assert.is_nil(account.mappings["aaaaaaaa-1111-2222-3333-444444444444"])
                local key = "bbbbbbbb-1111-2222-3333-444444444444"
                assert.are.same("match", CalibreWebIndex.verifyIdentity(account, key, path,
                    "calibre:BBBBBBBB-1111-2222-3333-444444444444\nisbn:123"))
                assert.are.same("unknown", CalibreWebIndex.verifyIdentity(account, key, path, "isbn:123"))
                assert.are.same("mismatch", CalibreWebIndex.verifyIdentity(account, key, path,
                    "calibre:cccccccc-1111-2222-3333-444444444444"))
                assert.is_nil(account.mappings[key])
            end)
        end)

        describe("search", function()
            local function row(title, authors, year, formats, paths, status)
                local f = {}
                for _, x in ipairs(formats or {}) do f[x] = {} end
                return { title = title, authors = authors or {}, status = status or "remote",
                         remote = { year = year, formats = f }, local_paths = paths or {} }
            end
            local function match(r, q) return CalibreWebIndex.matchSearch(r, CalibreWebIndex.parseSearch(q)) end

            it("should match all words across title, author, year and format, ignoring case and accents", function()
                local r = row("Cien años de soledad", { "Gabriel García Márquez" }, 1967, { "EPUB" })
                assert.is_true(match(r, "garcia SOLEDAD"))
                assert.is_true(match(r, "1967 epub"))
                assert.is_true(match(r, "Años"))
                assert.is_false(match(r, "garcia dune"))
                assert.is_true(match(r, ""))
            end)

            it("should support field prefixes, year ranges, status and phrases", function()
                local r = row("Dune Messiah", { "Frank Herbert" }, 1969, { "EPUB", "MOBI" }, { "/books/dune.azw3" }, "both")
                assert.is_true(match(r, "author:herbert"))
                assert.is_false(match(r, "title:herbert"))
                assert.is_true(match(r, "year:1960-1970"))
                assert.is_false(match(r, "year:1970"))
                assert.is_true(match(r, "format:mobi"))
                assert.is_true(match(r, "format:azw3"))
                assert.is_false(match(r, "format:pdf"))
                assert.is_true(match(r, "status:both"))
                assert.is_false(match(r, "status:local"))
                assert.is_true(match(r, '"dune messiah"'))
                assert.is_false(match(r, '"messiah dune"'))
                assert.is_true(match(r, 'author:"frank herbert"'))
            end)

            it("should treat unknown prefixes as plain text", function()
                local r = row("Re:Zero", { "Tappei" }, 2014, { "EPUB" })
                assert.is_true(match(r, "re:zero"))
                assert.are.same(1, #CalibreWebIndex.parseSearch("re:zero"))
                assert.are.same(0, #CalibreWebIndex.parseSearch("year:abc"))
            end)
        end)

        describe("store", function()
            it("should persist mappings per account and keep the last complete snapshot", function()
                local dir = makeDir("store")
                local store = CalibreWebIndex.Store:new(dir)
                local account = store:getAccount("http://nas.local:8083|reader")
                CalibreWebIndex.link(account, { uuid = "u-1", key = "u-1", title = "T" }, "/books/t.epub", "EPUB", "download")
                assert.is_true(store:saveSnapshot("http://nas.local:8083|reader", { complete = true, books = { x = {} } }))
                assert.is_false(store:saveSnapshot("http://nas.local:8083|reader", { complete = false, books = {} }))
                store:markDirty()
                store:flush()

                local reopened = CalibreWebIndex.Store:new(dir)
                assert.is_not_nil(reopened:getAccount("http://nas.local:8083|reader").mappings["u-1"])
                assert.is_nil(reopened:getAccount("http://nas.local:8083|other").mappings["u-1"])
                assert.is_not_nil(reopened:getSnapshot("http://nas.local:8083|reader").books.x)
            end)
        end)
    end)

    describe("browser", function()
        local CalibreWebBrowser, CalibreWebIndex, NetworkMgr, Trapper, UIManager
        local shown, stubs

        setup(function()
            CalibreWebBrowser = require("calibrewebbrowser")
            CalibreWebIndex = require("calibrewebindex")
            NetworkMgr = require("ui/network/manager")
            Trapper = require("ui/trapper")
            UIManager = require("ui/uimanager")
        end)

        before_each(function()
            shown = {}
            stubs = {
                stub(UIManager, "show", function(_, widget) table.insert(shown, widget) end),
                stub(UIManager, "close"),
                stub(NetworkMgr, "runWhenConnected", function(_, callback) callback() end),
                stub(Trapper, "wrap", function(_, func) func() end),
                stub(Trapper, "info", function() return true end),
                stub(Trapper, "clear"),
            }
        end)

        after_each(function()
            for _, s in ipairs(stubs) do s:revert() end
        end)

        local function newBrowser(dir, routes)
            local store = CalibreWebIndex.Store:new(dir)
            store:saveConfig{ base_url = "http://nas.local:8083", username = "reader", download_dir = dir .. "/books" }
            util.makePath(dir .. "/books")
            local key = CalibreWebClient.accountKey("http://nas.local:8083", "reader")
            local session = { password = "secret" }
            session.client = CalibreWebClient:new{
                base_url = "http://nas.local:8083", username = "reader", password = "secret",
                http_client = fakeServer(routes or {}),
            }
            session.client_key = key
            store:saveSnapshot(key, {
                complete = true, fetched_at = os.time(), count = 2,
                books = {
                    ["u-1"] = { uuid = "u-1", key = "u-1", id = 1, title = "Remote one", authors = { "Ann" },
                        formats = { EPUB = { format = "EPUB", href = "http://nas.local:8083/opds/download/1/epub/" } } },
                    ["u-2"] = { uuid = "u-2", key = "u-2", id = 2, title = "Remote two", authors = { "Bob" },
                        formats = { PDF = { format = "PDF", href = "http://nas.local:8083/opds/download/2/pdf/" } } },
                },
            })
            store:saveInventory{ complete = true, files = {}, roots = { [dir] = "ok" }, scanned_at = os.time(), count = 0 }
            local manager = { ui = {}, openCalibreWebFile = function(self_, path) self_.opened = path end }
            local browser = CalibreWebBrowser:new{
                store = store, session = session, _manager = manager,
                is_borderless = true, title_bar_fm_style = true,
            }
            return browser, store, session, manager
        end

        it("should list remote books with their status and filter them", function()
            local dir = makeDir("browser_list")
            local browser = newBrowser(dir)
            assert.are.same(3, #browser.item_table)
            assert.is_true(browser.item_table[1].is_search)
            assert.are.same("Remote one — Ann", browser.item_table[2].text)
            assert.are.same("Remote", browser.item_table[2].mandatory)
            browser.filter = "both"
            browser:refreshList()
            assert.are.same(1, #browser.item_table)
            browser.filter = "all"
            browser.session.search = { query = "two" }
            browser:refreshList()
            assert.are.same(2, #browser.item_table)
            assert.are.same(1, browser.item_table[1].result_count)
            browser:onClose()
        end)

        it("should render cover rows and fetch missing covers lazily", function()
            local dir = makeDir("browser_covers")
            local png = assert(readFile("resources/koreader.png"))
            local fetched = 0
            local schedule_stub = stub(UIManager, "scheduleIn", function(_, _, func) func() end)
            local connected_stub = stub(NetworkMgr, "isConnected", function() return true end)
            finally(function() schedule_stub:revert() connected_stub:revert() end)
            local browser, store = newBrowser(dir, {
                ["GET http://nas.local:8083/opds/cover/1"] = function() fetched = fetched + 1 return 200, {}, png end,
            })
            local key = CalibreWebClient.accountKey("http://nas.local:8083", "reader")
            local snapshot = store:getSnapshot(key)
            snapshot.books["u-1"].cover_href = "http://nas.local:8083/opds/cover/1"
            snapshot.books["u-1"].year = 2001
            browser:refreshList()
            assert.are.same(1, fetched)
            local CalibreWebItem = require("calibrewebitem")
            assert.are.same(CalibreWebItem.SearchBar, getmetatable(browser.item_group[1]).__index)
            local first = browser.item_group[2]
            assert.are.same(CalibreWebItem, getmetatable(first).__index)
            assert.is_not_nil(first.cover_bb)
            assert.is_nil(browser.item_group[3].cover_bb)
            -- cached on disk: no second download
            browser:refreshList()
            assert.are.same(1, fetched)
            browser:onClose()
        end)

        it("should filter by server search results, not by local text", function()
            local dir = makeDir("browser_server_search")
            local browser = newBrowser(dir, {
                ["GET http://nas.local:8083/opds/search?query=space%20opera"] = function()
                    return 200, atom, feedXml({ entryXml("u-2", 2, "Remote two", "Bob", { { name = "PDF" } }),
                        entryXml("u-7", 7, "Only on server", "Cy", { { name = "EPUB" } }) })
                end,
            })
            browser:searchServer("space opera")
            local titles = {}
            for i = 2, #browser.item_table do table.insert(titles, browser.item_table[i].row.title) end
            assert.are.same({ "Only on server", "Remote two" }, titles)
            browser:onMenuHold(browser.item_table[1]) -- hold the search bar to clear
            assert.is_nil(browser.session.search)
            assert.are.same(4, #browser.item_table)
            browser:onClose()
        end)

        it("should open the search dialog from the search bar", function()
            local dir = makeDir("browser_search_dialog")
            local browser = newBrowser(dir)
            browser:onMenuSelect(browser.item_table[1])
            local InputDialog = require("ui/widget/inputdialog")
            assert.are.same(InputDialog, getmetatable(shown[#shown]).__index)
            browser:onClose()
        end)

        it("should migrate an existing setup and keep matches across server addresses", function()
            local dir = makeDir("browser_addresses")
            local key = CalibreWebClient.accountKey("http://nas.local:8083", "reader")
            local browser, store, session = newBrowser(dir, {
                ["GET http://nas.local:8083/opds/download/1/epub/"] = function() return 200, {}, "LAN!" end,
            })
            -- pre-addresses configuration is migrated without changing the account key
            assert.are.same({ { name = "Home", url = "http://nas.local:8083" } }, browser.config.addresses)
            assert.are.same(key, browser:getAccountKey())
            CalibreWebIndex.link(store:getAccount(key), { uuid = "u-2", key = "u-2", title = "Remote two" },
                dir .. "/books/two.pdf", "PDF", "manual")

            table.insert(browser.config.addresses, { name = "Tailscale", url = "http://100.64.0.5:8083" })
            local vpn_server = fakeServer{
                ["GET http://100.64.0.5:8083/opds/download/1/epub/"] = function() return 200, {}, "VPN!" end,
            }
            browser.newClient = function(self_, base_url)
                return CalibreWebClient:new{ base_url = base_url, username = "reader", password = "secret",
                    http_client = base_url:find("100.64", 1, true) and vpn_server or fakeServer{} }
            end
            browser:setActiveAddress(2)
            assert.are.same("http://100.64.0.5:8083", browser.config.base_url)
            assert.are.same(key, browser:getAccountKey())
            assert.is_not_nil(store:getAccount(browser:getAccountKey()).mappings["u-2"])
            -- the cached catalog's links now go through the VPN address
            local row
            for __, item in ipairs(browser.item_table) do
                if item.row and item.row.key == "u-1" then row = item.row end
            end
            browser:downloadBook(row, "EPUB")
            assert.are.same("VPN!", readFile(dir .. "/books/Remote one - Ann.epub"))
            -- persisted
            local reopened = CalibreWebIndex.Store:new(dir)
            assert.are.same(2, reopened:getConfig().active_address)
            assert.are.same(session, browser.session)
            browser:onClose()
        end)

        it("should switch to the first reachable address", function()
            local dir = makeDir("browser_reachable")
            local browser = newBrowser(dir)
            browser.config.addresses = {
                { name = "Home", url = "http://nas.local:8083" },
                { name = "Tailscale", url = "http://100.64.0.5:8083" },
            }
            browser.config.active_address = 1
            browser.newClient = function(self_, base_url)
                local routes = {}
                if base_url:find("100.64", 1, true) then
                    routes["GET " .. base_url .. "/opds"] = function() return 200, atom, feedXml({}) end
                else
                    routes["GET " .. base_url .. "/opds"] = function() return "timeout" end
                end
                return CalibreWebClient:new{ base_url = base_url, username = "reader", http_client = fakeServer(routes) }
            end
            browser:findReachableAddress()
            assert.are.same(2, browser.config.active_address)
            assert.are.same("http://100.64.0.5:8083", browser.config.base_url)
            local ButtonDialog = require("ui/widget/buttondialog")
            local MultiInputDialog = require("ui/widget/multiinputdialog")
            browser:showAddressesDialog()
            assert.are.same(ButtonDialog, getmetatable(shown[#shown]).__index)
            browser:showAddressDialog(1)
            assert.are.same(MultiInputDialog, getmetatable(shown[#shown]).__index)
            browser:showAddressDialog()
            assert.are.same(MultiInputDialog, getmetatable(shown[#shown]).__index)
            browser:onClose()
        end)

        it("should download a book, map it and show it as Both", function()
            local dir = makeDir("browser_download")
            local browser, store = newBrowser(dir, {
                ["GET http://nas.local:8083/opds/download/1/epub/"] = function()
                    return 200, { ["content-length"] = "4" }, "EPUB"
                end,
            })
            browser:onMenuSelect(browser.item_table[2])
            local dialog = shown[#shown]
            assert.is_truthy(dialog.title:find("Remote one", 1, true))
            browser:downloadBook(browser.item_table[2].row, "EPUB")
            local path = dir .. "/books/Remote one - Ann.epub"
            assert.are.same("EPUB", readFile(path))
            assert.are.same("Both", browser.item_table[2].mandatory)
            local account = store:getAccount(CalibreWebClient.accountKey("http://nas.local:8083", "reader"))
            assert.are.same("download", account.mappings["u-1"].files[path].source)
            -- persisted across a restart
            local reopened = CalibreWebIndex.Store:new(dir)
            assert.is_not_nil(reopened:getAccount(CalibreWebClient.accountKey("http://nas.local:8083", "reader")).mappings["u-1"])
            browser:onClose()
        end)

        it("should not map anything when a download fails", function()
            local dir = makeDir("browser_download_fail")
            local browser, store = newBrowser(dir, {
                ["GET http://nas.local:8083/opds/download/1/epub/"] = function() return 500, {}, "" end,
            })
            browser:downloadBook(browser.item_table[2].row, "EPUB")
            local account = store:getAccount(CalibreWebClient.accountKey("http://nas.local:8083", "reader"))
            assert.is_nil(account.mappings["u-1"])
            assert.are.same("Remote", browser.item_table[2].mandatory)
            browser:onClose()
        end)

        it("should record an uncertain upload and keep the book Unknown", function()
            local dir = makeDir("browser_upload")
            local book_path = dir .. "/books/Mine.epub"
            util.makePath(dir .. "/books")
            writeFile(book_path, "content")
            local browser, store, session = newBrowser(dir, {
                ["POST http://nas.local:8083/upload"] = function() return "timeout" end,
            })
            session.client.logged_in = true
            store:saveInventory{ complete = true, files = { [book_path] = { size = 7, mtime = 1 } },
                roots = { [dir] = "ok" }, scanned_at = os.time(), count = 1 }
            browser:upload(book_path)
            local account = store:getAccount(CalibreWebClient.accountKey("http://nas.local:8083", "reader"))
            assert.are.same("uncertain", account.pending_uploads[book_path].status)
            local row
            for _, item in ipairs(browser.item_table) do
                if item.row and item.row.key == "local:" .. book_path then row = item.row end
            end
            assert.are.same("unknown", row.status)
            browser:onClose()
        end)

        it("should verify an accepted upload before mapping it", function()
            local dir = makeDir("browser_upload_ok")
            local book_path = dir .. "/books/Mine.epub"
            util.makePath(dir .. "/books")
            writeFile(book_path, "content")
            local browser, store, session = newBrowser(dir, {
                ["POST http://nas.local:8083/upload"] = function() return 200, {}, '{"location": "/admin/book/9"}' end,
                ["GET http://nas.local:8083/ajax/listbooks?sort=id&order=desc&offset=0&limit=50"] = function()
                    return 200, {}, '{"rows": [{"id": 9, "uuid": "u-9", "title": "Mine"}]}'
                end,
                ["GET http://nas.local:8083/opds/search?query=Mine"] = function()
                    return 200, atom, feedXml({ entryXml("u-9", 9, "Mine", "Me", { { name = "EPUB" } }) })
                end,
            })
            session.client.logged_in = true
            browser:upload(book_path)
            local account = store:getAccount(CalibreWebClient.accountKey("http://nas.local:8083", "reader"))
            assert.are.same("upload", account.mappings["u-9"].files[book_path].source)
            assert.is_nil(account.pending_uploads[book_path])
            browser:onClose()
        end)
    end)
end)
