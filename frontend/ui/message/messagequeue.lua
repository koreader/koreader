local ffi = require("ffi")
local Event = require("ui/event")
local logger = require("logger")

local _ = require("ffi/zeromq_h")
local czmq = ffi.loadlib("czmq", "4")

local MessageQueue = {}

function MessageQueue:extend(subclass_prototype)
    local o = subclass_prototype or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MessageQueue:new(o)
    o = self:extend(o)
    if o.init then o:init() end
    self.messages = {}
    return o
end

function MessageQueue:init()
end

function MessageQueue:start()
end

function MessageQueue:stop()
end

function MessageQueue:waitEvent()
end

function MessageQueue:handleZMsgs(messages)
    local function drop_message()
        if czmq.zmsg_size(messages[1]) == 0 then
            czmq.zmsg_destroy(ffi.new('zmsg_t *[1]', messages[1]))
            table.remove(messages, 1)
        end
    end
    local function pop_string()
        local str_p = czmq.zmsg_popstr(messages[1])
        local res = ffi.string(str_p)
        czmq.zstr_free(ffi.new('char *[1]', str_p))
        drop_message()
        return res
    end
    local function pop_header()
        local header = {}
        local frame = czmq.zmsg_pop(messages[1])
        if frame ~= nil then
            local hash = czmq.zhash_unpack(frame)
            czmq.zframe_destroy(ffi.new('zframe_t *[1]', frame))
            if hash ~= nil then
                local value, key = czmq.zhash_first(hash), czmq.zhash_cursor(hash)
                while value ~= nil and key ~= nil do
                    header[ffi.string(key)] = ffi.string(value)
                    value, key = czmq.zhash_next(hash), czmq.zhash_cursor(hash)
                end
                czmq.zhash_destroy(ffi.new('zhash_t *[1]', hash))
            end
        end
        drop_message()
        return header
    end
    if #messages == 0 then return end
    local command = pop_string()
    logger.dbg("ØMQ message", command)
    if command == "ENTER" then
        local id = pop_string()
        local name = pop_string()
        local header = pop_header()
        local endpoint = pop_string()
        return Event:new("ZyreEnter", id, name, header, endpoint)
    elseif command == "DELIVER" then
        local filename = pop_string()
        local fullname = pop_string()
        return Event:new("FileDeliver", filename, fullname)
    end
end

return MessageQueue
