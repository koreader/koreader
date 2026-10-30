--[[--
Network client for a self-hosted Calibre-Web server.

Catalog access goes through Calibre-Web's OPDS feeds with HTTP Basic authentication,
uploads go through the web UI (`POST /upload`), which needs a login session and a CSRF token.

Results are plain tables: callers decide how to present them.
Nothing in here persists credentials or cookies.
--]]

local CookieJar = require("cookiejar")
local OPDSClient = require("opdsclient")
local OPDSParser = require("opdsparser")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")

local CalibreWebClient = {
    all_books_path = "/opds/books/letter/00",
    max_catalog_pages = 5000,
    upload_chunk_size = 16 * 1024,
    ca_bundle = "data/ca-bundle.crt",
}
CalibreWebClient.__index = CalibreWebClient

local default_ports = { http = 80, https = 443 }

local acquisition_rel = "http://opds-spec.org/acquisition"
local image_rel = "http://opds-spec.org/image"
local thumbnail_rel = "http://opds-spec.org/image/thumbnail"

--- Normalizes user input into a canonical server base URL.
-- Keeps reverse-proxy sub-paths, drops trailing slashes, default ports, queries and fragments.
-- @treturn string|nil base URL
-- @treturn string|nil error key: "empty", "scheme", "host", "userinfo"
function CalibreWebClient.normalizeBaseUrl(input)
    if type(input) ~= "string" then return nil, "empty" end
    input = util.trim(input)
    if input == "" then return nil, "empty" end
    if not input:match("^%a[%w+.-]*://") then
        -- Reject things like "ftp:host" or "javascript:x" instead of mangling them into a host name
        if input:match("^%a[%w+.-]*:[^%d]") then return nil, "scheme" end
        input = "http://" .. input
    end
    local parsed = url.parse(input)
    if not parsed then return nil, "host" end
    local scheme = parsed.scheme and parsed.scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then return nil, "scheme" end
    if parsed.userinfo or parsed.user or parsed.password then return nil, "userinfo" end
    local host = parsed.host and parsed.host:lower()
    if not host or host == "" or host:match("[^%w%.%-%[%]:]") then return nil, "host" end
    local port = parsed.port
    if port and port ~= "" then
        local port_num = tonumber(port)
        if not port_num or port_num < 1 or port_num > 65535 or port_num % 1 ~= 0 then return nil, "host" end
        port = port_num ~= default_ports[scheme] and tostring(port_num) or nil
    else
        port = nil
    end
    local path = parsed.path or ""
    path = path:gsub("/+", "/"):gsub("/$", "")
    -- Users frequently paste the OPDS root or the login page: the base is what precedes it
    path = path:gsub("/opds$", ""):gsub("/login$", "")
    return scheme .. "://" .. host .. (port and (":" .. port) or "") .. path
end

--- Canonical key identifying one account on one server (mappings are namespaced by it).
function CalibreWebClient.accountKey(base_url, username)
    return base_url .. "|" .. (username or ""):lower()
end

local function originOf(u)
    local parsed = url.parse(u)
    if not parsed or not parsed.host then return nil end
    local scheme = parsed.scheme and parsed.scheme:lower()
    return scheme .. "://" .. parsed.host:lower() .. ":" .. (tonumber(parsed.port) or default_ports[scheme] or "")
end

local function isWithinBase(base_url, target)
    if originOf(base_url) ~= originOf(target) then return false end
    local base_path = url.parse(base_url).path or ""
    local target_path = url.parse(target).path or "/"
    return base_path == "" or target_path == base_path or util.stringStartsWith(target_path, base_path .. "/")
end
CalibreWebClient.isWithinBase = isWithinBase

--- Turns a server URL into a path relative to `base_url` (starting with "/"), so cached catalogs
-- stay valid when the same server is reached through another address (e.g. LAN vs VPN).
function CalibreWebClient:relativeHref(href)
    if not isWithinBase(self.base_url, href) then return href end
    local base_path = url.parse(self.base_url).path or ""
    local parsed = url.parse(href)
    local rel = (parsed.path or "/"):sub(#base_path + 1)
    if rel == "" then rel = "/" end
    if parsed.query then rel = rel .. "?" .. parsed.query end
    return rel
end

--- Resolves a relative catalog link against the active address. Absolute links from older caches
-- are re-based when they belong to one of the server's other known addresses.
function CalibreWebClient:resolveHref(href)
    if type(href) ~= "string" then return nil end
    if href:sub(1, 1) == "/" and href:sub(2, 2) ~= "/" then return self.base_url .. href end
    if isWithinBase(self.base_url, href) then return href end
    for __, other in ipairs(self.alt_bases or {}) do
        if isWithinBase(other, href) then
            local rel = CalibreWebClient.relativeHref({ base_url = other }, href)
            return self.base_url .. rel
        end
    end
    return href
end

-- Hostname check for LuaSec, which only validates the chain, not the name.
local function hostMatches(pattern, host)
    pattern = pattern:lower()
    if pattern == host then return true end
    -- Single left-most label wildcard only (RFC 6125 6.4.3)
    local suffix = pattern:match("^%*(%..+%..+)$")
    if suffix and host:sub(-#suffix) == suffix then
        local label = host:sub(1, #host - #suffix)
        return label ~= "" and not label:find("%.")
    end
    return false
end

function CalibreWebClient.certificateMatchesHost(cert, host)
    host = host:lower():gsub("^%[(.*)%]$", "%1")
    local is_ip = host:match("^%d+%.%d+%.%d+%.%d+$") or host:find(":")
    local has_dns_san = false
    local extensions = cert:extensions() or {}
    for _, ext in pairs(extensions) do
        if type(ext) == "table" then
            if is_ip then
                for _, ip in ipairs(ext.iPAddress or {}) do
                    if ip:lower() == host then return true end
                end
            else
                for _, dns in ipairs(ext.dNSName or {}) do
                    has_dns_san = true
                    if hostMatches(dns, host) then return true end
                end
            end
        end
    end
    if is_ip or has_dns_san then return false end
    for _, entry in ipairs(cert:subject() or {}) do
        if entry.oid == "2.5.4.3" and hostMatches(entry.value, host) then return true end
    end
    return false
end

-- Builds a LuaSocket `create` function for HTTPS that verifies the chain *and* the host name.
local function verifiedHttpsCreate(params)
    local ssl = require("ssl")
    return function()
        local conn = {}
        conn.sock = socket.try(socket.tcp())
        local settimeout = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout()
            return settimeout(self.sock, http.TIMEOUT)
        end
        function conn:connect(host, port)
            socket.try(self.sock:connect(host, port))
            self.sock = socket.try(ssl.wrap(self.sock, params))
            self.sock:sni(host)
            self.sock:settimeout(http.TIMEOUT)
            socket.try(self.sock:dohandshake())
            local cert = self.sock:getpeercertificate()
            if not cert or not CalibreWebClient.certificateMatchesHost(cert, host) then
                self.sock:close()
                socket.try(nil, "certificate host mismatch")
            end
            for name, method in pairs(getmetatable(self.sock).__index) do
                if type(method) == "function" then
                    conn[name] = function(this, ...) return method(this.sock, ...) end
                end
            end
            return 1
        end
        return conn
    end
end

function CalibreWebClient:new(o)
    o = setmetatable(o or {}, self)
    assert(o.base_url, "base_url required")
    o.account_key = CalibreWebClient.accountKey(o.base_url, o.username)
    if not o.http_client then
        local tls_params
        if lfs.attributes(o.ca_bundle, "mode") == "file" then
            tls_params = {
                create = verifiedHttpsCreate{
                    mode = "client",
                    protocol = "any",
                    options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
                    verify = { "peer", "fail_if_no_peer_cert" },
                    cafile = o.ca_bundle,
                },
            }
        else
            -- Without a CA bundle every certificate check would fail: refuse HTTPS rather than skip verification
            o.no_ca_bundle = true
        end
        o.http_client = OPDSClient:new{
            cookie_jar = CookieJar:new(),
            tls_params = tls_params,
        }
    end
    return o
end

function CalibreWebClient:isHttps()
    return self.base_url:match("^https://") ~= nil
end

-- Base path + path, for endpoints we address ourselves (not links from the server)
function CalibreWebClient:endpoint(path)
    return self.base_url .. path
end

--- Low-level request. Never throws.
-- @treturn table { code=, headers=, status=, body=, error= }
function CalibreWebClient:request(req)
    if self.no_ca_bundle and req.url:match("^https://") then
        return { error = "tls_unavailable" }
    end
    local body = {}
    local block_timeout, total_timeout = socketutil:set_timeout(
        req.block_timeout or socketutil.LARGE_BLOCK_TIMEOUT,
        req.total_timeout or socketutil.LARGE_TOTAL_TIMEOUT)
    local headers = { ["Accept-Encoding"] = "identity" }
    for name, value in pairs(req.headers or {}) do headers[name] = value end
    local ok, code, response_headers, status = pcall(self.http_client.request, self.http_client, {
        url = req.url,
        method = req.method,
        headers = headers,
        source = req.source,
        sink = req.sink or socketutil.table_sink(body),
        follow_redirects = req.follow_redirects,
        username = req.basic_auth and self.username or nil,
        -- LuaSocket URL-unescapes the password before Basic-encoding it
        password = req.basic_auth and self.password and url.escape(self.password) or nil,
    })
    socketutil:reset_timeout()
    if not ok then
        logger.warn("CalibreWeb: request failed:", req.method or "GET", req.url, code)
        return { error = "network", detail = tostring(code) }
    end
    local result = {
        code = code,
        headers = response_headers or {},
        status = status,
        body = not req.sink and table.concat(body) or nil,
    }
    if type(code) ~= "number" then
        result.error = "network"
        result.detail = socketutil.describe_error(code, block_timeout, total_timeout) or tostring(code or status)
        result.raw_error = code
    end
    return result
end

local http_errors = {
    [401] = "auth",
    [403] = "forbidden",
    [404] = "not_found",
    [429] = "rate_limited",
}

local function classify(result)
    if result.error then return result.error end
    if result.code >= 300 and result.code < 400 then return "redirect" end
    if result.code == 200 then return nil end
    return http_errors[result.code] or "http"
end

local function isHtml(result)
    local content_type = result.headers and result.headers["content-type"] or ""
    if content_type:lower():find("text/html", 1, true) then return true end
    local head = (result.body or ""):sub(1, 512):lower()
    return head:find("<!doctype html", 1, true) ~= nil or head:find("<html", 1, true) ~= nil
end
CalibreWebClient.isHtml = isHtml

local function getText(node)
    if type(node) == "string" then return util.trim(node) end
    if type(node) == "table" and type(node[1]) == "string" then return util.trim(node[1]) end
    return nil
end

--- Extracts a publication year. Calibre stores unknown dates as year 101, which is dropped.
function CalibreWebClient.parseYear(date)
    local year = type(date) == "string" and tonumber(date:match("^%s*(%d%d%d%d)"))
    if year and year >= 1000 then return year end
end

--- Converts one OPDS entry into a remote book record, or nil for navigation entries.
function CalibreWebClient:normalizeEntry(entry, page_url)
    local book = {
        title = getText(entry.title) or "",
        authors = {},
        formats = {},
        updated = getText(entry.updated),
        year = CalibreWebClient.parseYear(getText(entry.published) or getText(entry["dcterms:issued"])),
    }
    local id_text = getText(entry.id) or ""
    book.uuid = id_text:match("^urn:uuid:(%S+)$")
    for _, author in ipairs(entry.author or {}) do
        local name = getText(author.name)
        if name and name ~= "" then table.insert(book.authors, name) end
    end
    local has_acquisition = false
    for _, link in ipairs(entry.link or {}) do
        local rel = link.rel or ""
        if link.href and rel:find(acquisition_rel, 1, true) == 1 then
            has_acquisition = true
            local href = url.absolute(page_url, link.href)
            if isWithinBase(self.base_url, href) then
                local format = link.title or href:match("/download/%d+/([^/]+)/?$") or util.getFileNameSuffix(href)
                format = format and format:upper()
                if format and format ~= "" and not book.formats[format] then
                    book.formats[format] = {
                        format = format,
                        href = self:relativeHref(href),
                        type = link.type,
                        length = tonumber(link.length),
                    }
                end
                book.id = book.id or tonumber(href:match("/download/(%d+)/"))
            else
                book.foreign_links = true
            end
        elseif link.href and (rel == thumbnail_rel or (rel == image_rel and not book.cover_href)) then
            -- Prefer the thumbnail link when the server offers a distinct one
            local href = url.absolute(page_url, link.href)
            if isWithinBase(self.base_url, href) then book.cover_href = self:relativeHref(href) end
        end
    end
    if not has_acquisition then return nil end
    book.key = book.uuid or (book.id and ("id:" .. book.id))
    return book
end

local function findLink(feed, wanted_rel)
    for _, link in ipairs(feed.link or {}) do
        if link.rel == wanted_rel and link.href then return link.href end
    end
end

--- Fetches and parses a single OPDS page.
-- @treturn table { books = {...}, next_url = , error = , code = }
function CalibreWebClient:fetchOpdsPage(page_url)
    local result = self:request{ url = page_url, basic_auth = true,
        headers = { Accept = "application/atom+xml;profile=opds-catalog, application/atom+xml" } }
    local err = classify(result)
    if err then
        return { error = err, code = result.code, location = result.headers and result.headers.location,
                 detail = result.detail }
    end
    if isHtml(result) then
        -- Typically a login page served by a proxy/SSO in front of Calibre-Web
        return { error = "html", code = result.code }
    end
    local ok, feed = pcall(OPDSParser.parse, OPDSParser, result.body or "")
    if not ok or type(feed) ~= "table" or type(feed.feed) ~= "table" then
        return { error = "parse" }
    end
    feed = feed.feed
    local page = { books = {}, feed = feed }
    for _, entry in ipairs(feed.entry or {}) do
        local book = self:normalizeEntry(entry, page_url)
        if book then table.insert(page.books, book) end
    end
    local next_href = findLink(feed, "next")
    if next_href then page.next_url = url.absolute(page_url, next_href) end
    return page
end

--- Checks the connection and credentials via the OPDS root.
-- @treturn table { ok=, error=, is_calibre_web=, title= }
function CalibreWebClient:checkConnection()
    local page = self:fetchOpdsPage(self:endpoint("/opds"))
    if page.error then return { ok = false, error = page.error, code = page.code, location = page.location,
                                detail = page.detail } end
    local is_calibre_web = false
    local author = page.feed.author
    for _, a in ipairs(type(author) == "table" and author or {}) do
        local uri = getText(a.uri)
        if uri and uri:find("calibre-web", 1, true) then is_calibre_web = true end
    end
    return { ok = true, is_calibre_web = is_calibre_web, title = getText(page.feed.title) }
end

--- Walks the all-books acquisition feed.
-- @tparam[opt] function progress_callback(pages_done, books_found) -> false to cancel
-- @treturn table snapshot { complete=, books = {key = book}, count=, fetched_at=, error=, pages= }
function CalibreWebClient:fetchCatalog(progress_callback)
    local snapshot = { books = {}, count = 0, pages = 0, complete = false, fetched_at = os.time() }
    local seen_pages = {}
    local next_url = self:endpoint(self.all_books_path)
    while next_url do
        if seen_pages[next_url] then
            snapshot.error = "cycle"
            return snapshot
        end
        if snapshot.pages >= self.max_catalog_pages then
            snapshot.error = "too_many_pages"
            return snapshot
        end
        seen_pages[next_url] = true
        local page = self:fetchOpdsPage(next_url)
        if page.error then
            snapshot.error = page.error
            snapshot.code = page.code
            snapshot.detail = page.detail
            return snapshot
        end
        snapshot.pages = snapshot.pages + 1
        local new_books = 0
        for _, book in ipairs(page.books) do
            if not book.uuid then snapshot.missing_uuids = (snapshot.missing_uuids or 0) + 1 end
            if book.key and not snapshot.books[book.key] then
                snapshot.books[book.key] = book
                snapshot.count = snapshot.count + 1
                new_books = new_books + 1
            end
        end
        if page.next_url and #page.books > 0 and new_books == 0 then
            -- A page that only repeats known books means the server isn't advancing the offset
            snapshot.error = "cycle"
            return snapshot
        end
        if progress_callback and progress_callback(snapshot.pages, snapshot.count) == false then
            snapshot.error = "cancelled"
            return snapshot
        end
        next_url = page.next_url
    end
    snapshot.complete = true
    snapshot.fetched_at = os.time()
    return snapshot
end

--- Searches the catalog. Results never establish that a book is absent from the server.
function CalibreWebClient:search(query)
    local page = self:fetchOpdsPage(self:endpoint("/opds/search?query=" .. util.urlEncode(query)))
    if page.error then return { error = page.error, code = page.code } end
    return { books = page.books }
end

-- Web session ------------------------------------------------------------------------------------

local function htmlAttr(tag, name)
    return tag:match("%s" .. name .. "%s*=%s*\"([^\"]*)\"") or tag:match("%s" .. name .. "%s*=%s*'([^']*)'")
end

--- Extracts a Flask-WTF CSRF token from an HTML page.
function CalibreWebClient.extractCsrfToken(html)
    if type(html) ~= "string" then return nil end
    for tag in html:gmatch("<input[^>]*>") do
        if htmlAttr(tag, "name") == "csrf_token" then
            local value = htmlAttr(tag, "value")
            if value and value ~= "" then return util.htmlEntitiesToUtf8(value) end
        end
    end
    for tag in html:gmatch("<meta[^>]*>") do
        if htmlAttr(tag, "name") == "csrf-token" then
            local value = htmlAttr(tag, "content")
            if value and value ~= "" then return util.htmlEntitiesToUtf8(value) end
        end
    end
end

local function hasPasswordField(html)
    for tag in (html or ""):gmatch("<input[^>]*>") do
        if htmlAttr(tag, "name") == "password" then return true end
    end
    return false
end

local function isLoginLocation(location)
    return location ~= nil and (location:match("/login$") or location:match("/login[?#]")) ~= nil
end

local function formEncode(fields)
    local parts = {}
    for _, field in ipairs(fields) do
        table.insert(parts, util.urlEncode(field[1]) .. "=" .. util.urlEncode(field[2]))
    end
    return table.concat(parts, "&")
end

--- Logs into the web UI. Makes a single attempt: Calibre-Web rate limits logins.
-- @treturn table { ok=, error= } error in "auth", "rate_limited", "csrf", "sso", "unsupported", "network", ...
function CalibreWebClient:login()
    self.logged_in = false
    self.csrf_token = nil
    local login_url = self:endpoint("/login")
    local page = self:request{ url = login_url, headers = { Accept = "text/html" }, follow_redirects = false }
    if page.error then return { ok = false, error = page.error, detail = page.detail } end
    if page.code >= 300 and page.code < 400 then
        local target = page.headers.location and url.absolute(login_url, page.headers.location)
        if target and not isWithinBase(self.base_url, target) then
            return { ok = false, error = "sso", location = target }
        end
        -- Already authenticated, e.g. by a trusted reverse proxy header
        return self:refreshSession(target)
    end
    if page.code ~= 200 then return { ok = false, error = classify(page) or "http", code = page.code } end
    if not hasPasswordField(page.body) then
        return { ok = false, error = "unsupported" }
    end
    local token = CalibreWebClient.extractCsrfToken(page.body)
    local body = formEncode{
        { "csrf_token", token or "" },
        { "username", self.username or "" },
        { "password", self.password or "" },
        { "next", "/" },
        { "submit", "" },
    }
    local response = self:request{
        url = login_url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-Length"] = tostring(#body),
            Accept = "text/html",
        },
        source = ltn12.source.string(body),
    }
    if response.error then return { ok = false, error = response.error, detail = response.detail } end
    local code = response.code
    if code == 302 or code == 303 then
        local target = response.headers.location and url.absolute(login_url, response.headers.location)
        if not target or isLoginLocation(target) then return { ok = false, error = "auth" } end
        if not isWithinBase(self.base_url, target) then return { ok = false, error = "sso", location = target } end
        return self:refreshSession(target, token)
    elseif code == 400 then
        return { ok = false, error = "csrf" }
    elseif code == 401 or code == 200 then
        -- Calibre-Web re-renders the login form with a 401 on bad credentials
        return { ok = false, error = "auth" }
    end
    return { ok = false, error = classify(response) or "http", code = code }
end

-- Loads an authenticated page to confirm the session and pick up a current CSRF token.
function CalibreWebClient:refreshSession(page_url, fallback_token)
    local result = self:request{ url = page_url or self:endpoint("/"), headers = { Accept = "text/html" } }
    if result.error then return { ok = false, error = result.error, detail = result.detail } end
    if result.code >= 300 and result.code < 400 then
        if isLoginLocation(result.headers.location) then return { ok = false, error = "auth" } end
    elseif result.code ~= 200 then
        return { ok = false, error = classify(result) or "http", code = result.code }
    elseif hasPasswordField(result.body) and result.body:find("/login", 1, true) then
        return { ok = false, error = "auth" }
    end
    self.csrf_token = CalibreWebClient.extractCsrfToken(result.body) or fallback_token
    self.logged_in = true
    return { ok = true }
end

-- Upload -----------------------------------------------------------------------------------------

local function escapeMultipartValue(value)
    -- Browsers percent-encode quotes and line breaks in multipart filenames (WHATWG HTML spec)
    return (value:gsub("[\r\n\"]", { ["\r"] = "%0D", ["\n"] = "%0A", ['"'] = "%22" }))
end
CalibreWebClient.escapeMultipartValue = escapeMultipartValue

local function randomBoundary()
    local chars = {}
    for i = 1, 24 do chars[i] = string.format("%x", math.random(0, 15)) end
    return "----KOReaderCalibreWeb" .. table.concat(chars)
end

--- Builds a streaming multipart source for one file. Reads the file in bounded chunks.
-- @treturn function source, number content_length, string content_type, table state
function CalibreWebClient:buildMultipart(file_path, file_name, fields)
    local size = lfs.attributes(file_path, "size")
    if not size then return nil, "unreadable" end
    local handle = io.open(file_path, "rb")
    if not handle then return nil, "unreadable" end
    local boundary = randomBoundary()
    local preamble = {}
    for _, field in ipairs(fields or {}) do
        table.insert(preamble, "--" .. boundary .. "\r\n"
            .. 'Content-Disposition: form-data; name="' .. field[1] .. '"\r\n\r\n'
            .. field[2] .. "\r\n")
    end
    table.insert(preamble, "--" .. boundary .. "\r\n"
        .. 'Content-Disposition: form-data; name="btn-upload"; filename="' .. escapeMultipartValue(file_name) .. '"\r\n'
        .. "Content-Type: application/octet-stream\r\n\r\n")
    preamble = table.concat(preamble)
    local epilogue = "\r\n--" .. boundary .. "--\r\n"
    local state = { sent = 0, file_bytes = 0, body_complete = false }
    local stage = 1
    local chunk_size = self.upload_chunk_size
    local function source()
        if state.cancelled then
            if handle then handle:close() handle = nil end
            return nil, "cancelled"
        end
        if stage == 1 then
            stage = 2
            state.sent = state.sent + #preamble
            return preamble
        elseif stage == 2 then
            local chunk, err = handle:read(chunk_size)
            if chunk then
                state.file_bytes = state.file_bytes + #chunk
                state.sent = state.sent + #chunk
                if state.on_progress then state.on_progress(state.file_bytes, size) end
                return chunk
            end
            handle:close()
            handle = nil
            if err then return nil, err end
            if state.file_bytes ~= size then return nil, "file changed during upload" end
            stage = 3
            state.sent = state.sent + #epilogue
            state.body_complete = true
            return epilogue
        end
        return nil
    end
    state.close = function()
        if handle then handle:close() handle = nil end
    end
    return source, #preamble + size + #epilogue, "multipart/form-data; boundary=" .. boundary, state
end

--- Uploads one file as a new book.
-- Never retries: a POST that may have reached the server is reported as "uncertain".
-- @treturn table { status = "uploaded"|"rejected"|"uncertain"|"failed", book_id=, error=, message= }
function CalibreWebClient:upload(file_path, file_name, on_progress)
    if not self.logged_in then
        return { status = "failed", error = "auth_required" }
    end
    local fields = {}
    if self.csrf_token then table.insert(fields, { "csrf_token", self.csrf_token }) end
    local source, content_length, content_type, state = self:buildMultipart(file_path, file_name, fields)
    if not source then return { status = "failed", error = content_length } end
    state.on_progress = on_progress
    local headers = {
        ["Content-Type"] = content_type,
        ["Content-Length"] = tostring(content_length),
        Accept = "application/json",
        ["X-Requested-With"] = "XMLHttpRequest",
    }
    if self.csrf_token then headers["X-CSRFToken"] = self.csrf_token end
    local result = self:request{
        url = self:endpoint("/upload"),
        method = "POST",
        headers = headers,
        source = source,
        block_timeout = socketutil.FILE_BLOCK_TIMEOUT,
        total_timeout = socketutil.FILE_TOTAL_TIMEOUT,
    }
    state.close()
    if result.error then
        if state.body_complete then
            -- The server may have stored the book before the connection failed
            return { status = "uncertain", error = result.error, detail = result.detail }
        end
        return { status = "failed", error = result.error, detail = result.detail }
    end
    local code = result.code
    if code >= 300 and code < 400 then
        if isLoginLocation(result.headers.location) then
            self.logged_in = false
            return { status = "failed", error = "auth_required" }
        end
        return { status = "failed", error = "redirect", location = result.headers.location }
    elseif code == 400 then
        return { status = "failed", error = "csrf" }
    elseif code == 401 then
        self.logged_in = false
        return { status = "failed", error = "auth_required" }
    elseif code == 403 then
        return { status = "failed", error = "forbidden" }
    elseif code == 413 then
        return { status = "failed", error = "too_large" }
    elseif code ~= 200 then
        -- A server error after the whole body was sent may still have created the book
        return { status = code >= 500 and "uncertain" or "failed", error = "http", code = code }
    end
    if isHtml(result) then
        if hasPasswordField(result.body) then
            self.logged_in = false
            return { status = "failed", error = "auth_required" }
        end
        return { status = "uncertain", error = "unexpected_response" }
    end
    local JSON = require("json")
    local ok, decoded = pcall(JSON.decode, result.body or "")
    if not ok or type(decoded) ~= "table" or type(decoded.location) ~= "string" then
        return { status = "uncertain", error = "unexpected_response" }
    end
    local book_id = tonumber(decoded.location:match("/admin/book/(%d+)/?$") or decoded.location:match("/book/(%d+)/?$"))
    if not book_id then
        -- Calibre-Web answers errors (e.g. disallowed format) with a generic location and a flash message
        return { status = "rejected", error = "server_rejected", location = decoded.location }
    end
    return { status = "uploaded", book_id = book_id }
end

--- Looks up a book by its numeric id through the authenticated JSON book list.
-- @treturn table|nil { id=, uuid=, title= }
function CalibreWebClient:lookupBookById(book_id)
    local result = self:request{
        url = self:endpoint("/ajax/listbooks?sort=id&order=desc&offset=0&limit=50"),
        headers = { Accept = "application/json" },
    }
    if result.error or result.code ~= 200 or isHtml(result) then return nil end
    local JSON = require("json")
    local ok, decoded = pcall(JSON.decode, result.body or "")
    if not ok or type(decoded) ~= "table" or type(decoded.rows) ~= "table" then return nil end
    for _, row in ipairs(decoded.rows) do
        if tonumber(row.id) == book_id then
            return { id = book_id, uuid = type(row.uuid) == "string" and row.uuid or nil, title = row.title }
        end
    end
end

-- Covers -----------------------------------------------------------------------------------------

CalibreWebClient.max_cover_size = 4 * 1024 * 1024

local image_magic = {
    "^\255\216\255",     -- JPEG
    "^\137PNG\r\n",      -- PNG
    "^GIF8",               -- GIF
    "^RIFF....WEBP",       -- WebP
}

--- Downloads a cover image to `dest_path` (replacing a previous cached copy).
-- @treturn bool success, string|nil error
function CalibreWebClient:fetchCover(href, dest_path)
    href = self:resolveHref(href)
    if not href or not isWithinBase(self.base_url, href) then return false, "foreign_link" end
    local chunks, size = {}, 0
    local function sink(chunk)
        if chunk == nil then return 1 end
        size = size + #chunk
        if size > self.max_cover_size then return nil, "too_large" end
        table.insert(chunks, chunk)
        return 1
    end
    local result = self:request{ url = href, basic_auth = true, sink = sink, headers = { Accept = "image/*" } }
    if result.raw_error == "too_large" then return false, "too_large" end
    local err = classify(result)
    if err then return false, err end
    local data = table.concat(chunks)
    local is_image = false
    for _, magic in ipairs(image_magic) do
        if data:find(magic) then is_image = true break end
    end
    if not is_image then return false, "not_image" end
    local tmp_path = dest_path .. ".part"
    local handle = io.open(tmp_path, "wb")
    if not handle then return false, "disk" end
    local ok = handle:write(data)
    handle:close()
    if not ok or not os.rename(tmp_path, dest_path) then
        os.remove(tmp_path)
        return false, "disk"
    end
    return true
end

-- Download ---------------------------------------------------------------------------------------

--- Picks a file name that doesn't exist yet in `dir`.
function CalibreWebClient.uniquePath(dir, file_name)
    local safe = util.getSafeFilename(file_name, dir)
    local stem, ext = util.splitFileNameSuffix(safe)
    local prefix = dir ~= "/" and dir or ""
    local candidate = prefix .. "/" .. safe
    local i = 2
    while lfs.attributes(candidate) do
        candidate = prefix .. "/" .. stem .. " (" .. i .. ")" .. (ext ~= "" and ("." .. ext) or "")
        i = i + 1
        if i > 1000 then return nil end
    end
    return candidate
end

--- Downloads one format of a book into `dir` without ever overwriting an existing file.
-- @treturn table { ok=, path=, error= }
function CalibreWebClient:download(format_info, dir, file_name, should_cancel)
    local href = self:resolveHref(format_info.href)
    if not href or not isWithinBase(self.base_url, href) then
        return { ok = false, error = "foreign_link" }
    end
    if lfs.attributes(dir, "mode") ~= "directory" then
        return { ok = false, error = "no_dir" }
    end
    local final_path = CalibreWebClient.uniquePath(dir, file_name)
    if not final_path then return { ok = false, error = "collision" } end
    local tmp_dir, tmp_name = util.splitFilePathName(final_path)
    local tmp_path = tmp_dir .. "." .. tmp_name .. ".cwpart"
    local handle = io.open(tmp_path, "wb")
    if not handle then return { ok = false, error = "disk" } end
    local written, sniff, write_error = 0, "", nil
    local function sink(chunk, err)
        if chunk == nil then
            if handle then handle:close() handle = nil end
            return 1
        end
        if should_cancel and should_cancel() then return nil, "cancelled" end
        if #sniff < 512 then sniff = sniff .. chunk:sub(1, 512 - #sniff) end
        local ok, io_err = handle:write(chunk)
        if not ok then
            write_error = io_err
            return nil, "disk"
        end
        written = written + #chunk
        return 1
    end
    local result = self:request{
        url = href,
        basic_auth = true,
        sink = sink,
        block_timeout = socketutil.FILE_BLOCK_TIMEOUT,
        total_timeout = socketutil.FILE_TOTAL_TIMEOUT,
    }
    if handle then handle:close() handle = nil end
    local function fail(err, extra)
        os.remove(tmp_path)
        local r = { ok = false, error = err }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end
    if write_error or result.raw_error == "disk" then return fail("disk", { detail = write_error }) end
    if result.raw_error == "cancelled" then return fail("cancelled") end
    local err = classify(result)
    if err then return fail(err, { code = result.code, detail = result.detail }) end
    local expected = tonumber(result.headers["content-length"])
    if expected and expected ~= written then return fail("truncated") end
    if written == 0 then return fail("empty") end
    if isHtml{ headers = result.headers, body = sniff } and format_info.format ~= "HTML" then
        return fail("html")
    end
    -- Re-check right before the rename: never replace a file that appeared meanwhile
    if lfs.attributes(final_path) then
        final_path = CalibreWebClient.uniquePath(dir, file_name)
        if not final_path then return fail("collision") end
    end
    local ok, rename_err = os.rename(tmp_path, final_path)
    if not ok then return fail("disk", { detail = rename_err }) end
    return { ok = true, path = final_path, size = written }
end

return CalibreWebClient
