local ffi = require("ffi")
local DEBUG = require("dbg")
local util = require("ffi/util")
local Event = require("ui/event")
local MessageQueue = require("ui/message/messagequeue")

local dummy = require("ffi/zeromq_h")
local zyre = ffi.load("libs/libzyre.so.1")

local ZyreMessageQueue = MessageQueue:new{
    header = {},
}

function ZyreMessageQueue:start()
    self.node = zyre.zyre_new()
    for key, value in pairs(self.header) do
        zyre.zyre_set_header(self.node, key, value)
    end
    zyre.zyre_set_verbose(self.node)
    zyre.zyre_start(self.node)
    zyre.zyre_join(self.node, "GLOBAL")
end

function ZyreMessageQueue:stop()
    if self.node ~= nil then
        DEBUG("stop zyre node")
        zyre.zyre_stop(self.node)
        zyre.zyre_destroy(ffi.new('zyre_t *[1]', self.node))
    end
end

function ZyreMessageQueue:waitEvent()
    local msg = zyre.zyre_recv_nowait(self.node)
    while msg ~= nil do
        table.insert(self.messages, msg)
        msg = zyre.zyre_recv_nowait(self.node)
    end
    return self:handleZMsgs(self.messages)
end

return ZyreMessageQueue
