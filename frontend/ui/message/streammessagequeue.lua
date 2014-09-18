local ffi = require("ffi")
local DEBUG = require("dbg")
local util = require("ffi/util")
local Event = require("ui/event")
local MessageQueue = require("ui/message/messagequeue")

local dummy = require("ffi/zeromq_h")
local zmq = ffi.load("libs/libzmq.so.4")
local czmq = ffi.load("libs/libczmq.so.1")

local StreamMessageQueue = MessageQueue:new{
    host = nil,
    port = nil,
}

function StreamMessageQueue:start()
    self.context = czmq.zctx_new();
    self.socket = czmq.zsocket_new(self.context, ffi.C.ZMQ_STREAM)
    self.poller = czmq.zpoller_new(self.socket, nil)
    local endpoint = string.format("tcp://%s:%d", self.host, self.port)
    DEBUG("connect to endpoint", endpoint)
    local rc = czmq.zsocket_connect(self.socket, endpoint)
    if rc ~= 0 then
        error("cannot connect to " .. endpoint)
    end
    local id_size = ffi.new("size_t[1]", 256)
    local buffer = ffi.new("uint8_t[?]", id_size[0])
    local rc = zmq.zmq_getsockopt(self.socket, ffi.C.ZMQ_IDENTITY, buffer, id_size)
    self.id = ffi.string(buffer, id_size[0])
    DEBUG("id", #self.id, self.id)
end

function StreamMessageQueue:stop()
    if self.poller ~= nil then
        czmq.zpoller_destroy(ffi.new('zpoller_t *[1]', self.poller))
    end
    if self.socket ~= nil then
        czmq.zsocket_destroy(self.context, self.socket)
    end
    if self.context ~= nil then
        czmq.zctx_destroy(ffi.new('zctx_t *[1]', self.context))
    end
end

function StreamMessageQueue:handleZframe(frame)
    local size = czmq.zframe_size(frame)
    local data = nil
    if size > 0 then
        local frame_data = czmq.zframe_data(frame)
        if frame_data ~= nil then
            data = ffi.string(frame_data, size)
        end
    end
    czmq.zframe_destroy(ffi.new('zframe_t *[1]', frame))
    return data
end

function StreamMessageQueue:waitEvent()
    local data = ""
    while czmq.zpoller_wait(self.poller, 0) ~= nil do
        local id_frame = czmq.zframe_recv(self.socket)
        if id_frame ~= nil then
            local id = self:handleZframe(id_frame)
        end
        local frame = czmq.zframe_recv(self.socket)
        if frame ~= nil then
            data = data .. (self:handleZframe(frame) or "")
        end
    end
    if self.receiveCallback and data ~= "" then
        self.receiveCallback(data)
    end
end

function StreamMessageQueue:send(data)
    --DEBUG("send", data)
    local msg = czmq.zmsg_new()
    czmq.zmsg_addmem(msg, self.id, #self.id)
    czmq.zmsg_addmem(msg, data, #data)
    czmq.zmsg_send(ffi.new('zmsg_t *[1]', msg), self.socket)
end

return StreamMessageQueue
