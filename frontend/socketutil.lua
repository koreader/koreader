--[[--
This module contains miscellaneous helper functions for specific to our usage of LuaSocket/LuaSec.
]]

local Version = require("version")
local http = require("socket.http")
local https = require("ssl.https")
local socket = require("socket")

local socketutil = {}

--- Builds a sensible UserAgent that fits Wikipedia's UA policy <https://meta.wikimedia.org/wiki/User-Agent_policy>
socketutil.USER_AGENT = "KOReader/" .. Version:getShortVersion() .. " (https://koreader.rocks/) " .. http.USERAGENT:gsub(" ", "/")

--- Custom `socket.tcp` (LuaSocket) with tighter timeouts, to avoid blocking the UI for too long.
function socketutil.http_tcp(block_timeout, total_timeout)
    -- open does a settimeout *after* create(), so, mangle that, too.
    http.TIMEOUT = block_timeout or 5
    -- c.f., https://stackoverflow.com/a/6021774
    local req_sock = socket.tcp()
    req_sock:settimeout(http.TIMEOUT, 'b')
    req_sock:settimeout(total_timeout or 15, 't')
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
local function https_tcp(params, block_timeout, total_timeout)
    params = params or {}
    -- Default settings
    for k, v in pairs(cfg) do
        params[k] = params[k] or v
    end
    -- Force client mode
    params.mode = "client"
    -- 'create' function for LuaSocket
    https.TIMEOUT = block_timeout or 5
    return function ()
        local conn = {}
        conn.sock = socket.try(socket.tcp())
        conn.sock:settimeout(https.TIMEOUT, 'b')
        conn.sock:settimeout(total_timeout or 15, 't')
        local st = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout(...)
            return st(self.sock, ...)
        end
        -- Replace TCP's connection function
        function conn:connect(host, port)
            socket.try(self.sock:connect(host, port))
            self.sock = socket.try(ssl.wrap(self.sock, params))
            self.sock:sni(host)
            socket.try(self.sock:dohandshake())
            reg(self, getmetatable(self.sock))
            return 1
        end
        return conn
    end
end

function socketutil.https_tcp(params, block_timeout, total_timeout)
    local create = https_tcp(params, block_timeout, total_timeout)
    return create()
end

return socketutil
