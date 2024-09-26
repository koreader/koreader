local ffi = require("ffi")
local logger = require("logger")
local MessageQueue = require("ui/message/messagequeue")

local _ = require("ffi/zeromq_h")
local zmq = ffi.loadlib("zmq", "5")
local czmq = ffi.loadlib("czmq", "4")
local C = ffi.C

local StreamMessageQueue = MessageQueue:extend{
    host = nil,
    port = nil,
}

function StreamMessageQueue:start()
    local endpoint = string.format("tcp://%s:%d", self.host, self.port)
    self.socket = czmq.zsock_new(C.ZMQ_STREAM)
    if not self.socket then
        error("cannot create socket for endpoint " .. endpoint)
    end
    logger.dbg("connecting to endpoint", endpoint)
    if czmq.zsock_connect(self.socket, endpoint) ~= 0 then
        error("cannot connect to " .. endpoint)
    end
    local id_size = ffi.new("size_t[1]", 255)
    local buffer = ffi.new("uint8_t[?]", id_size[0])
    if zmq.zmq_getsockopt(czmq.zsock_resolve(self.socket), C.ZMQ_IDENTITY, buffer, id_size) ~= 0 then
        error("cannot get socket identity for endpoint " .. endpoint)
    end
    self.id = ffi.string(buffer, id_size[0])
    self.poller = czmq.zpoller_new(self.socket, nil)
    if not self.poller then
        error("cannot create poller for endpoint " .. endpoint)
    end
end

function StreamMessageQueue:stop()
    if self.poller ~= nil then
        czmq.zpoller_destroy(ffi.new('zpoller_t *[1]', self.poller))
    end
    if self.socket ~= nil then
        czmq.zsock_destroy(ffi.new('zsock_t *[1]', self.socket))
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
    -- Successive zframes may come in batches of tens or hundreds in some cases.
    -- Since we buffer each frame's data in a Lua string,
    -- and then let the caller concatenate those,
    -- it may consume a significant amount of memory.
    -- And it's fairly easy to trigger when receiving file data from Calibre.
    -- So, throttle reception to 256 packages at most in one waitEvent loop,
    -- after which we immediately call receiveCallback.
    local wait_packages = 256
    -- In a similar spirit, much like LuaSocket,
    -- we store the data as ropes of strings in an array,
    -- to be concatenated by the caller.
    local t = {}
    while czmq.zpoller_wait(self.poller, 0) ~= nil and wait_packages > 0 do
        local id_frame = czmq.zframe_recv(self.socket)
        if id_frame ~= nil then
            self:handleZframe(id_frame)
        end
        local frame = czmq.zframe_recv(self.socket)
        if frame ~= nil then
            local data = self:handleZframe(frame)
            if data then
                table.insert(t, data)
            end
        end
        wait_packages = wait_packages - 1
    end
    if self.receiveCallback and #t ~= 0 then
        self.receiveCallback(t)
    end
end

function StreamMessageQueue:send(data)
    local msg = czmq.zmsg_new()
    czmq.zmsg_addmem(msg, self.id, #self.id)
    czmq.zmsg_addmem(msg, data, #data)
    czmq.zmsg_send(ffi.new('zmsg_t *[1]', msg), self.socket)
end

return StreamMessageQueue
