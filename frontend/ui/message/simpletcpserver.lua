local socket = require("socket")
local logger = require("logger")

-- Reference:
-- https://lunarmodules.github.io/luasocket/tcp.html

-- Drop-in alternative to streammessagequeueserver.lua, using
-- LuaSocket instead of ZeroMQ.
-- This SimpleTCPServer is still tied to HTTP, expecting lines of headers,
-- a blank like marking the end of the input request.

local SimpleTCPServer = {
    host = nil,
    port = nil,
}

function SimpleTCPServer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function SimpleTCPServer:start()
    self.server = socket.bind(self.host, self.port)
    self.server:settimeout(0.01) -- set timeout (10ms)
    logger.dbg("SimpleTCPServer: Server listening on port " .. self.port)
end

function SimpleTCPServer:stop()
    self.server:close()
end

function SimpleTCPServer:waitEvent()
    local client = self.server:accept() -- wait for a client to connect
    if client then
        -- We expect to get all headers in 100ms. We will block during this timeframe.
        client:settimeout(0.1, "t")
        local lines = {}
        while true do
            local data = client:receive("*l") -- read a line from input
            if not data then -- timeout
                client:close()
                break
            end
            if data == "" then -- proper empty line after request headers
                table.insert(lines, data) -- keep it in content
                data = table.concat(lines, "\r\n")
                logger.dbg("SimpleTCPServer: Received data: ", data)
                -- Give us more time to process the request and send the response
                client:settimeout(0.5, "t")
                self.receiveCallback(data, client)
                    -- This should call SimpleTCPServer:send() to send
                    -- the response and close this connection.
            else
                table.insert(lines, data)
            end
        end
    end
end

function SimpleTCPServer:send(data, client)
    client:send(data) -- send the response back to the client
    client:close() -- close the connection to the client
end

return SimpleTCPServer
