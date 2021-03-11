--[[--
This module contains miscellaneous helper functions for specific to our usage of LuaSocket/LuaSec.
]]

local Version = require("version")
local http = require("socket.http")
local socket = require("socket")

local socketutil = {}

--- Builds a sensible UserAgent that fits Wikipedia's UA policy <https://meta.wikimedia.org/wiki/User-Agent_policy>
socketutil.USER_AGENT = "KOReader/" .. Version:getShortVersion() .. " (https://koreader.rocks/) " .. http.USERAGENT:gsub(" ", "/")

-- Custom `socket.tcp` with tighter timeouts, to avoid blocking the UI for too long.
function socketutil.create_tcp(block_timeeout, total_timeout)
    -- c.f., https://stackoverflow.com/a/6021774
    local req_sock = socket.tcp()
    req_sock:settimeout(block_timeeout or 5, 'b')
    req_sock:settimeout(total_timeout or 15, 't')
    return req_sock
end

return socketutil
