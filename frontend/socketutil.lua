--[[--
This module contains miscellaneous helper functions specific to our usage of LuaSocket/LuaSec.
]]

local Device = require("device")
local Version = require("version")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")

local socketutil = {
    -- Init to the default LuaSocket/LuaSec values
    block_timeout = 60,
    total_timeout = -1,
}

--- Builds a sensible UserAgent that fits Wikipedia's UA policy <https://meta.wikimedia.org/wiki/User-Agent_policy>
local socket_ua = http.USERAGENT
socketutil.USER_AGENT = "KOReader/" .. Version:getShortVersion() .. " (" .. Device.model .. "; " .. jit.os .. "; " .. jit.arch .. ") " .. socket_ua:gsub(" ", "/")
-- Monkey-patch it in LuaSocket, as it already takes care of inserting the appropriate header to its requests.
http.USERAGENT = socketutil.USER_AGENT

--- Common timeout values
-- Large content
socketutil.LARGE_BLOCK_TIMEOUT = 10
socketutil.LARGE_TOTAL_TIMEOUT = 30
-- File downloads
socketutil.FILE_BLOCK_TIMEOUT = 15
socketutil.FILE_TOTAL_TIMEOUT = 60
-- Upstream defaults
socketutil.DEFAULT_BLOCK_TIMEOUT = 60
socketutil.DEFAULT_TOTAL_TIMEOUT = -1

--- Update the timeout values.
-- Note that this only affects socket polling,
-- c.f., LuaSocket's timeout_getretry @ src/timeout.c & usage in src/usocket.c
-- Moreover, the timeout is actually *reset* between polls (via timeout_markstart, e.g. in buffer_meth_receive).
-- So, in practice, this timeout only helps *very* bad connections (on one end or the other),
-- and you'd be hard-pressed to ever hit the *total* timeout, since the starting point is reset extremely often.
-- In our case, we want to enforce an *actual* limit on how much time we're willing to block for, start to finish.
-- We do that via the custom sinks below, which will start ticking as soon as the first chunk of data is received.
-- To simplify, in most cases, the socket timeout matters *before* we receive data,
-- and the sink timeout *once* we've started receiving data (at which point the socket timeout is reset every chunk).
-- In practice, that means you don't want to set block_timeout too low,
-- as that's what the socket timeout will end up using most of the time.
-- Note that name resolution happens earlier and one level lower (e.g., glibc),
-- so name resolution delays will fall outside of these timeouts.
function socketutil:set_timeout(block_timeout, total_timeout)
    self.block_timeout = block_timeout or 5
    self.total_timeout = total_timeout or 15

    -- Also update the actual LuaSocket & LuaSec constants, because:
    -- 1. LuaSocket's `open` does a `settimeout` *after* create with this constant
    -- 2. Rogue code might be attempting to enforce them
    http.TIMEOUT = self.block_timeout
    https.TIMEOUT = self.block_timeout
end

--- Reset timeout values to LuaSocket defaults.
function socketutil:reset_timeout()
    self.block_timeout = self.DEFAULT_BLOCK_TIMEOUT
    self.total_timeout = self.DEFAULT_TOTAL_TIMEOUT

    http.TIMEOUT = self.block_timeout
    https.TIMEOUT = self.block_timeout
end

--- Monkey-patch LuaSocket's `socket.tcp` in order to honor tighter timeouts, to avoid blocking the UI for too long.
-- NOTE: While we could use a custom `create` function for HTTP LuaSocket `request`s,
--       with HTTPS, the way LuaSocket/LuaSec handles those is much more finicky,
--       because LuaSocket's adjustrequest function (in http.lua) passes the adjusted nreqt table to it,
--       but only when it does the automagic scheme handling, not when it's set by the caller :/.
--       And LuaSec's own `request` function overload *forbids* setting create, because of similar shenanigans...
-- TL;DR: Just monkey-patching socket.tcp directly will affect both HTTP & HTTPS
--        without us having to maintain a tweaked version of LuaSec's `https.tcp` function...
local real_socket_tcp = socket.tcp
function socketutil.tcp()
    -- Based on https://stackoverflow.com/a/6021774
    local req_sock = real_socket_tcp()
    req_sock:settimeout(socketutil.block_timeout, "b")
    req_sock:settimeout(socketutil.total_timeout, "t")
    return req_sock
end
socket.tcp = socketutil.tcp

--- Various timeout return codes
socketutil.TIMEOUT_CODE         = "timeout"      -- from LuaSocket's io.c
socketutil.SSL_HANDSHAKE_CODE   = "wantread"     -- from LuaSec's ssl.c
socketutil.SINK_TIMEOUT_CODE    = "sink timeout" -- from our own socketutil

-- NOTE: Use os.time() for simplicity's sake (we don't really need subsecond precision).
--       LuaSocket itself is already using gettimeofday anyway (although it does the maths, like ffi/util's getTimestamp).
--- Custom version of `ltn12.sink.table` that honors total_timeout
function socketutil.table_sink(t)
    if socketutil.total_timeout < 0 then
        return ltn12.sink.table(t)
    end

    local start_ts = os.time()
    t = t or {}
    local f = function(chunk, err)
        if chunk then
            if os.time() - start_ts > socketutil.total_timeout then
                return nil, socketutil.SINK_TIMEOUT_CODE
            end
            table.insert(t, chunk)
        end
        return 1
    end
    return f, t
end

--- Custom version of `ltn12.sink.file` that honors total_timeout
function socketutil.file_sink(handle, io_err)
    if socketutil.total_timeout < 0 then
        return ltn12.sink.file(handle, io_err)
    end

    if handle then
        local start_ts = os.time()
        return function(chunk, err)
            if not chunk then
                handle:close()
                return 1
            else
                if os.time() - start_ts > socketutil.total_timeout then
                    handle:close()
                    return nil, socketutil.SINK_TIMEOUT_CODE
                end
                return handle:write(chunk)
            end
        end
    else
        return nil, io_err or "unable to open file"
    end
end

function socketutil.redact_headers(headers)
    local sensitive_headers = {
        ["authorization"] = true,
        ["cookie"] = true,
        ["proxy-authorization"] = true,
        ["set-cookie"] = true,
    }
    local safe_headers = {}
    for key, value in pairs(headers) do
        if sensitive_headers[key] then
            safe_headers[key] = "REDACTED"
        else
            safe_headers[key] = value
        end
    end
    return safe_headers
end

function socketutil.redact_request(request)
    local sensitive_props = {
        ["password"] = true,
        ["user"] = true,
    }
    local safe_request = {}
    for key, value in pairs(request) do
        if sensitive_props[key] then
            safe_request[key] = "REDACTED"
        elseif key == "headers" then
            safe_request[key] = socketutil.redact_headers(value)
        else
            safe_request[key] = value
        end
    end
    return safe_request
end

function socketutil.chainSinkWithProgressCallback(sink, progressCallback)
    if sink == nil or progressCallback == nil then
        return sink
    end

    local downloaded_bytes = 0
    local progress_reporter_filter = function(chunk, err)
        if chunk ~= nil then
            -- accumulate the downloaded bytes so we don't need to check the actual file every time
            downloaded_bytes = downloaded_bytes + chunk:len()
            progressCallback(downloaded_bytes)
        end
        return chunk, err
    end

    return ltn12.sink.chain(progress_reporter_filter, sink)
end

return socketutil
