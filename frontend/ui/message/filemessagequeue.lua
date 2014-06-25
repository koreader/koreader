local ffi = require("ffi")
local DEBUG = require("dbg")
local util = require("ffi/util")
local Event = require("ui/event")
local MessageQueue = require("ui/message/messagequeue")

local dummy = require("ffi/zeromq_h")
local czmq = ffi.load("libs/libczmq.so.1")
local filemq = ffi.load("libs/libfmq.so.1")

local FileMessageQueue = MessageQueue:new{
    client = nil,
    server = nil,
}

function FileMessageQueue:init()
    if self.client ~= nil then
        self.fmq_recv = filemq.fmq_client_recv
        self.filemq = self.client
        self.poller = czmq.zpoller_new(filemq.fmq_client_handle(self.client), nil)
    elseif self.server ~= nil then
        -- TODO: currently fmq_server_recv API is not available
        --self.fmq_recv = filemq.fmq_server_recv
        self.filemq = self.server
        -- TODO: currently fmq_server_handle API is not available
        --self.poller = czmq.zpoller_new(filemq.fmq_server_handle(self.server), nil)
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
    if self.poller ~= nil then
        czmq.zpoller_destroy(ffi.new('zpoller_t *[1]', self.poller))
    end
end

function FileMessageQueue:waitEvent()
    if not self.poller then return end
    if czmq.zpoller_wait(self.poller, 0) ~= nil then
        local msg = self.fmq_recv(self.filemq)
        if msg ~= nil then
            table.insert(self.messages, msg)
        end
    end
    return self:handleZMsgs(self.messages)
end

return FileMessageQueue
