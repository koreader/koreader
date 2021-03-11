--[[--
This module contains miscellaneous helper functions for specific to our usage of LuaSocket/LuaSec.
]]

local Version = require("version")
local http = require("socket.http")
local https = require("ssl.https")
local socket = require("socket")
local ssl = require("ssl")

local socketutil = {
    -- Init to the default LuaSocket/LuaSec values
    block_timeout = 60,
    total_timeout = -1,
}

--- Builds a sensible UserAgent that fits Wikipedia's UA policy <https://meta.wikimedia.org/wiki/User-Agent_policy>
socketutil.USER_AGENT = "KOReader/" .. Version:getShortVersion() .. " (https://koreader.rocks/) " .. http.USERAGENT:gsub(" ", "/")

--- Common timeout values
-- Large content
socketutil.LARGE_BLOCK_TIMEOUT = 10
socketutil.LARGE_TOTAL_TIMEOUT = 30
-- File downloads
socketutil.FILE_BLOCK_TIMEOUT = 15
socketutil.FILE_TOTAL_TIMEOUT = 60

--- Update the timeout values
function socketutil:set_timeout(block_timeout, total_timeout)
    self.block_timeout = block_timeout or 5
    self.total_timeout = total_timeout or 15

    -- Also update the actual LuaSocket & LuaSec constants, because:
    -- 1. LuaSocket's open does a settimeout *after* create
    -- 2. KOSync updates it to a stupidly low value
    http.TIMEOUT = self.block_timeout
    https.TIMEOUT = self.block_timeout
end

--- Custom `socket.tcp` (LuaSocket) with tighter timeouts, to avoid blocking the UI for too long.
function socketutil.http_tcp()
    -- c.f., https://stackoverflow.com/a/6021774
    local req_sock = socket.tcp()
    req_sock:settimeout(socketutil.block_timeout, 'b')
    req_sock:settimeout(socketutil.total_timeout, 't')
    return req_sock
end

-- From LuaSec, for the tweaked tcp function below.
-- TLS configuration
local cfg = {
    protocol = "any",
    options  = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
    verify   = "none",
}

-- Forward calls to the real connection object.
local function reg(conn)
   local mt = getmetatable(conn.sock).__index
   for name, method in pairs(mt) do
      if type(method) == "function" then
         conn[name] = function (self, ...)
                         return method(self.sock, ...)
                      end
      end
   end
end

--- Custom `https.tcp` (LuaSec's wrapper around LuaSocket's socket.tcp) with tighter timeouts, to avoid blocking the UI for too long.
-- NOTE: Keep me in sync w/ LuaSec's in https.lua!
-- NOTE: We don't really have a better choice than monkey-patching the actual LuaSec function,
--       because LuaSocket's adjustrequest function (in http.lua) passes the adjusted nreqt table to it,
--       but only when it does the automagic scheme handling, not when it's set by the caller :/.
--       And LuaSec's request function *forbids* setting create, because of similar shenanigans...
https.tcp = function(params)
    params = params or {}
    -- Default settings
    for k, v in pairs(cfg) do
        params[k] = params[k] or v
    end
    -- Force client mode
    params.mode = "client"
    -- 'create' function for LuaSocket
    return function ()
        local conn = {}
        conn.sock = socket.try(socket.tcp())
        conn.sock:settimeout(socketutil.block_timeout, 'b')
        conn.sock:settimeout(socketutil.total_timeout, 't')
        local st = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout(...)
            return st(self.sock, ...)
        end
        -- Replace TCP's connection function
        function conn:connect(host, port)
            socket.try(self.sock:connect(host, port))
            self.sock = socket.try(ssl.wrap(self.sock, params))
            self.sock:sni(host)
            self.sock:settimeout(https.TIMEOUT)
            socket.try(self.sock:dohandshake())
            reg(self, getmetatable(self.sock))
            return 1
        end
        return conn
    end
end

return socketutil
