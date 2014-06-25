local ffi = require("ffi")
local DEBUG = require("dbg")
local util = require("ffi/util")
local Event = require("ui/event")
local MessageQueue = require("ui/message/messagequeue")

local dummy = require("ffi/zeromq_h")
local czmq = ffi.load("libs/libczmq.so.1")
local zyre = ffi.load("libs/libzyre.so.1")

local ZyreMessageQueue = MessageQueue:new{
    header = {},
}

function ZyreMessageQueue:start()
    self.node = zyre.zyre_new()
    self.poller = czmq.zpoller_new(zyre.zyre_socket(self.node), nil)
    for key, value in pairs(self.header) do
        zyre.zyre_set_header(self.node, key, value)
    end
    --zyre.zyre_set_verbose(self.node)
    zyre.zyre_set_interface(self.node, "wlan0")
    zyre.zyre_start(self.node)
    zyre.zyre_join(self.node, "GLOBAL")
    --zyre.zyre_dump(self.node)
end

function ZyreMessageQueue:stop()
    if self.node ~= nil then
        DEBUG("stop zyre node")
        zyre.zyre_stop(self.node)
        zyre.zyre_destroy(ffi.new('zyre_t *[1]', self.node))
    end
    if self.poller ~= nil then
        czmq.zpoller_destroy(ffi.new('zpoller_t *[1]', self.poller))
    end
end

function ZyreMessageQueue:waitEvent()
    if czmq.zpoller_wait(self.poller, 0) ~= nil then
        local msg = zyre.zyre_recv(self.node)
        if msg ~= nil then
            table.insert(self.messages, msg)
        end
    end
    return self:handleZMsgs(self.messages)
end

return ZyreMessageQueue
