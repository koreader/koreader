--[[--
Non-blocking HTTP(S) downloads and a coroutine-based concurrent scheduler.

Unlike `httpclient.lua` (Turbo's I/O loop), this works without Turbo: it
drives LuaSocket/LuaSec sockets in non-blocking mode, yielding to a
`socket.select`-based scheduler so one Lua state can interleave many
downloads.

Sources:
- The coroutine scheduler is based on <https://www.lua.org/pil/9.4.html>
- The HTTP request/response handling (request lines, header parsing, redirects, chunked and content-length body reading) is adapted from LuaSocket (http.lua / the LTN12/http client).
]]

local logger = require("logger")
local socket = require("socket")
local socket_url = require("socket.url")
local ssl = require("ssl")
local socketutil = require("socketutil")
local util = require("util")

local HttpAsync = {}

local MAX_REDIRECTS = 5
local DEFAULT_CONCURRENCY = 10

--- Non-blocking receive; yields (socket, "r"/"w") until data/error/EOF.
-- LuaSocket's receive(pattern, prefix) prepends `prefix` to the buffer it
-- reads into, so any partial data already consumed from the socket on a
-- previous (timed-out) call must be passed back as the prefix on the next
-- call. We accumulate that partial data in `accumulated` and always prepend
-- it, so a resumed receive continues exactly where it left off instead of
-- discarding bytes already pulled from the socket.
local function async_receive(sock, pattern)
    local accumulated = ""
    while true do
        local res, err, partial = sock:receive(pattern, accumulated)
        if err == "timeout" or err == "wantread" then
            -- Carry forward the partial data already consumed from the socket.
            accumulated = partial or accumulated
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return res, err, partial
        end
    end
end

--- Non-blocking send; yields (socket, "w"/"r") while it would block.
local function async_send(sock, data)
    local i = 1
    local n = #data
    while i <= n do
        local res, err, last = sock:send(data, i)
        if err == "timeout" or err == "wantwrite" then
            coroutine.yield(sock, "w")
            -- LuaSocket reports the index of the last byte sent on error.
            if last then i = last + 1 end
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err then
            return nil, err
        else
            i = res + 1
        end
    end
    return true
end

--- Non-blocking connect; yields (socket, "w") until connected or failed.
local function async_connect(sock, host, port)
    sock:settimeout(0)
    while true do
        local res, err = sock:connect(host, port)
        if res or err == "already connected" then
            return true
        elseif err == "timeout" or err == "Operation already in progress" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

--- Non-blocking TLS handshake; yields (socket, "r"/"w") while it would block.
local function async_handshake(sock)
    while true do
        local res, err = sock:dohandshake()
        if res then
            return true
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

--- Fetch one URL over a raw non-blocking socket, yielding while it would
-- block so the caller can interleave many downloads.
-- @param url string
-- @param redirect_count number internal recursion guard
-- @param headers table optional extra request headers (e.g. cookie)
-- @return (true, content_type, content) or (false, err)
function HttpAsync.fetch_url(url, redirect_count, headers)
    redirect_count = redirect_count or 0
    if redirect_count > MAX_REDIRECTS then return false, "Too many redirects" end

    local parsed = socket_url.parse(url)
    if not parsed then return false, "invalid url" end
    if parsed.path then
        -- Encode invalid path chars (e.g., spaces) while preserving "/" and "%".
        parsed.path = util.urlEncode(parsed.path, "/%%")
        url = socket_url.build(parsed)
    end

    local host = parsed.host
    if not host then return false, "invalid url" end
    local port = parsed.port or (parsed.scheme == "https" and 443 or 80)
    local path = parsed.path or "/"
    if parsed.query then path = path .. "?" .. parsed.query end

    local sock = socket.tcp()
    local ok, err = async_connect(sock, host, port)
    if not ok then
        sock:close()
        return false, "connect error: " .. tostring(err)
    end

    if parsed.scheme == "https" then
        local ssl_params = {
            mode = "client",
            protocol = "any",
            verify = "none",
            options = {"all", "no_sslv2", "no_sslv3"},
        }
        local ssl_sock, wrap_err = ssl.wrap(sock, ssl_params)
        if not ssl_sock then
            sock:close()
            return false, "ssl wrap error: " .. tostring(wrap_err)
        end
        sock = ssl_sock
        sock:settimeout(0)
        if sock.sni then
            sock:sni(host)
        end
        local hok, herr = async_handshake(sock)
        if not hok then
            sock:close()
            return false, "ssl handshake error: " .. tostring(herr)
        end
    end

    local req_lines = {
        string.format("GET %s HTTP/1.1", path),
        string.format("Host: %s", host),
        string.format("User-Agent: %s", socketutil.USER_AGENT),
    }
    if headers then
        for k, v in pairs(headers) do
            table.insert(req_lines, string.format("%s: %s", k, v))
        end
    end
    table.insert(req_lines, "Connection: close")
    table.insert(req_lines, "")
    table.insert(req_lines, "")
    local req = table.concat(req_lines, "\r\n")

    local sok, serr = async_send(sock, req)
    if not sok then
        sock:close()
        return false, "send error: " .. tostring(serr)
    end

    -- Read status line and headers.
    local resp_headers = {}
    local status_line
    while true do
        local line, lerr = async_receive(sock, "*l")
        if not line then
            sock:close()
            return false, "read error: " .. tostring(lerr)
        end
        if line == "" then break end
        if not status_line then
            status_line = line
        else
            local k, v = line:match("^(.-):%s*(.*)")
            if k and v then resp_headers[k:lower()] = v end
        end
    end

    if not status_line then
        sock:close()
        return false, "no status line received"
    end

    local code = tonumber(status_line:match("HTTP/%d%.%d%s+(%d%d%d)"))

    if code and code >= 300 and code < 400 and resp_headers["location"] then
        sock:close()
        local location = resp_headers["location"]:gsub("\r$", "")
        local new_url = socket_url.absolute(url, location)
        return HttpAsync.fetch_url(new_url, redirect_count + 1, headers)
    end

    if code and code >= 400 then
        sock:close()
        return false, "HTTP error " .. tostring(code)
    end

    -- Read the body, handling both chunked and fixed/until-close encodings.
    local body = {}
    local transfer_encoding = resp_headers["transfer-encoding"]
    if transfer_encoding and transfer_encoding:lower():find("chunked", 1, true) then
        while true do
            local chunk_size_str = async_receive(sock, "*l")
            if not chunk_size_str then break end
            local hex = chunk_size_str:match("^%x+")
            if not hex then break end
            local chunk_size = tonumber(hex, 16)
            if not chunk_size or chunk_size == 0 then break end

            local chunk_data = async_receive(sock, chunk_size)
            if chunk_data and #chunk_data > 0 then table.insert(body, chunk_data) end
            async_receive(sock, 2) -- trailing CRLF
        end
    else
        local content_length = tonumber(resp_headers["content-length"])
        if content_length then
            local remaining = content_length
            while remaining > 0 do
                local chunk = async_receive(sock, remaining)
                if not chunk then break end
                table.insert(body, chunk)
                remaining = remaining - #chunk
            end
        else
            while true do
                local chunk, cerr, partial = async_receive(sock, 8192)
                if chunk then
                    table.insert(body, chunk)
                else
                    if partial and #partial > 0 then table.insert(body, partial) end
                    if cerr == "closed" then break end
                    if cerr ~= "timeout" and cerr ~= "wantread" then
                        -- Some other error: stop reading.
                        break
                    end
                end
            end
        end
    end

    sock:close()
    local content = table.concat(body)
    return true, resp_headers["content-type"], content
end

--- Download many tasks concurrently via a coroutine scheduler.
--
-- Each task is a caller-supplied value; `opts.get_url(task)` yields its URL.
-- The scheduler runs up to `opts.concurrency` fetches at once, resuming each
-- coroutine whenever `socket.select` says its socket is ready.
--
-- @param tasks list of arbitrary task values
-- @param opts table:
--   concurrency  number  max simultaneous fetches (default 10)
--   get_url(task) -> string  (default: identity, i.e. tasks are URL strings)
--   fetch(url)    -> (success, content)  (default: HttpAsync.fetch_url)
--   on_success(task, content) called for each successful download
--   on_failure(task, err)     called for each failed download
--   on_progress(completed, total) -> bool  called periodically; return false to cancel
-- @return true if cancelled, false if all tasks completed
function HttpAsync.fetch_many(tasks, opts)
    opts = opts or {}
    local concurrency = opts.concurrency or DEFAULT_CONCURRENCY
    local get_url = opts.get_url or function(task) return task end
    local fetch = opts.fetch or function(url)
        local ok, _, content = HttpAsync.fetch_url(url)
        return ok, content
    end
    local on_success = opts.on_success
    local on_failure = opts.on_failure
    local on_progress = opts.on_progress

    local pending = {}
    for i, task in ipairs(tasks) do
        table.insert(pending, {task = task, index = i})
    end
    local total = #pending

    local active = {}   -- running coroutines
    local co2sock = {}  -- coroutine -> socket it's waiting on
    local co2mode = {}  -- coroutine -> "r" or "w"
    local completed = 0

    local function refill_pool()
        while #active < concurrency and #pending > 0 do
            local item = table.remove(pending, 1)
            local co = coroutine.create(function()
                local ok, content = fetch(get_url(item.task))
                coroutine.yield("RESULT", item, ok, content)
            end)
            table.insert(active, co)
        end
    end

    refill_pool()

    local cancelled = false
    while #active > 0 and not cancelled do
        -- Gather sockets we're waiting on and select() on them.
        local recvt, sendt = {}, {}
        for _, co in ipairs(active) do
            local sock = co2sock[co]
            if sock then
                if co2mode[co] == "r" then table.insert(recvt, sock) end
                if co2mode[co] == "w" then table.insert(sendt, sock) end
            end
        end

        local ready
        if #recvt > 0 or #sendt > 0 then
            local r, w = socket.select(recvt, sendt, 0.1)
            ready = {}
            for _, s in ipairs(r or {}) do ready[s] = true end
            for _, s in ipairs(w or {}) do ready[s] = true end
        end

        -- Resume coroutines that are ready (or haven't yielded a socket yet).
        local next_active = {}
        for _, co in ipairs(active) do
            local sock = co2sock[co]
            local is_ready = not sock or (ready and ready[sock])

            if not is_ready then
                table.insert(next_active, co)
            else
                if sock then
                    co2sock[co] = nil
                    co2mode[co] = nil
                end

                local ok, yield_type, yield_arg2, success, content = coroutine.resume(co)

                if not ok then
                    logger.warn("httpasync coroutine error:", yield_type)
                    completed = completed + 1
                elseif coroutine.status(co) == "dead" then
                    -- Finished without a RESULT yield; treat as done.
                    completed = completed + 1
                elseif yield_type == "RESULT" then
                    completed = completed + 1
                    local item = yield_arg2
                    if success and content then
                        if on_success then on_success(item.task, content) end
                    else
                        if on_failure then on_failure(item.task, content) end
                    end
                else
                    -- The coroutine yielded a socket and mode ("r"/"w").
                    co2sock[co] = yield_type
                    co2mode[co] = yield_arg2
                    table.insert(next_active, co)
                end
            end
        end
        active = next_active

        refill_pool()

        if on_progress and not on_progress(completed, total) then
            cancelled = true
        end
    end

    return cancelled
end

return HttpAsync
