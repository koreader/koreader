local ffi = require("ffi")
local logger = require("logger")
local MessageQueue = require("ui/message/messagequeue")

local _ = require("ffi/zeromq_h")
local czmq = ffi.load("libs/libczmq.so.1")
local C = ffi.C

local StreamMessageQueueServer = MessageQueue:extend{
    host = nil,
    port = nil,
}

function StreamMessageQueueServer:start()
    self.context = czmq.zctx_new()
    self.socket = czmq.zsocket_new(self.context, C.ZMQ_STREAM)
    self.poller = czmq.zpoller_new(self.socket, nil)
    local endpoint = string.format("tcp://%s:%d", self.host, self.port)
    logger.dbg("StreamMessageQueueServer: Binding to endpoint", endpoint)
    local rc = czmq.zsocket_bind(self.socket, endpoint)
    -- If success, rc is port number
    if rc == -1 then
        logger.err("StreamMessageQueueServer: Cannot bind to ", endpoint)
    end
end

function StreamMessageQueueServer:stop()
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

function StreamMessageQueueServer:handleZframe(frame)
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

function StreamMessageQueueServer:waitEvent()
    local request, id
    while czmq.zpoller_wait(self.poller, 0) ~= nil do
        -- See about ZMQ_STREAM and these 2 frames at http://hintjens.com/blog:42
        local id_frame = czmq.zframe_recv(self.socket)
        if id_frame ~= nil then
            id = id_frame
        end

        local frame = czmq.zframe_recv(self.socket)
        if frame ~= nil then
            local data = self:handleZframe(frame)
            if data then
                logger.dbg("StreamMessageQueueServer: Received data: ", data)
                request = data
            end
        end
    end
    if self.receiveCallback and request ~= nil then
        self.receiveCallback(request, id)
    end
end

function StreamMessageQueueServer:send(data, id_frame)
    czmq.zframe_send(ffi.new('zframe_t *[1]', id_frame), self.socket, C.ZFRAME_MORE + C.ZFRAME_REUSE)
    czmq.zmq_send(self.socket, ffi.cast("unsigned char*", data), #data, C.ZFRAME_MORE)
    -- Note: We can't use czmq.zstr_send(self.socket, data), which would stop on the first
    -- null byte in data (Lua strings can have null bytes inside).

    -- Close connection
    czmq.zframe_send(ffi.new('zframe_t *[1]', id_frame), self.socket, C.ZFRAME_MORE)
    czmq.zmq_send(self.socket, nil, 0, 0)
end

return StreamMessageQueueServer
