local ffi = require("ffi")
local DEBUG = require("dbg")
local util = require("ffi/util")
local Event = require("ui/event")
local MessageQueue = require("ui/message/messagequeue")

local dummy = require("ffi/zeromq_h")
local filemq = ffi.load("libs/libfmq.so.1")

local FileMessageQueue = MessageQueue:new{
    client = nil,
    server = nil,
}

function FileMessageQueue:init()
    if self.client ~= nil then
        self.fmq_recv = filemq.fmq_client_recv_nowait
        self.filemq = self.client
    elseif self.server ~= nil then
        self.fmq_recv = filemq.fmq_server_recv_nowait
        self.filemq = self.server
    end
end

function FileMessageQueue:stop()
    if self.client ~= nil then
        DEBUG("stop filemq client")
        filemq.fmq_client_destroy(ffi.new('fmq_client_t *[1]', self.client))
    end
    if self.server ~= nil then
        DEBUG("stop filemq server")
        filemq.fmq_server_destroy(ffi.new('fmq_server_t *[1]', self.server))
    end
end

function FileMessageQueue:waitEvent()
    local msg = self.fmq_recv(self.filemq)
    while msg ~= nil do
        table.insert(self.messages, msg)
        msg = self.fmq_recv(self.filemq)
    end
    return self:handleZMsgs(self.messages)
end

return FileMessageQueue
