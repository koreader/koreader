local bitser = require("ffi/bitser")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local function readFile(file, bytes)
    local f, str, err
    f, err = io.open(file, "rb")
    if not f then
        return nil, err
    end
    str, err = f:read(bytes or "*a")
    f:close()
    if not str then
        return nil, err
    end
    return str
end

local codecs = {
    -- bitser: binary form, fast encode/decode, low size. Not human readable.
    bitser = {
        id = "bitser",
        reads_from_file = false,

        serialize = function(t)
            local ok, str = pcall(bitser.dumps, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t)
            end
            return str
        end,

        deserialize = function(str)
            local ok, t = pcall(bitser.loads, str)
            if not ok then
                return nil, "malformed serialized data"
            end
            return t
        end,
    },
    -- dump: human readable, pretty printed, fast enough for most user cases.
    dump = {
        id = "dump",
        reads_from_file = true,

        serialize = function(t, as_bytecode)
            local content
            if as_bytecode then
                local bytecode, err = load("return " .. dump(t))
                if not bytecode then
                    logger.warn("cannot convert table to bytecode", err, "fallback to text")
                else
                    content = string.dump(bytecode, true)
                end
            end
            if not content then
                content = "return " .. dump(t)
            end
            return content
        end,

        deserialize = function(str)
            local t, err = loadfile(str)
            if not t then
                t, err = loadstring(str)
            end
            if not t then
                return nil, err
            end
            return t()
        end,
    }
}

local Persist = {}

function Persist:new(o)
    o = o or {}
    assert(type(o.path) == "string", "path is required")
    o.codec = o.codec or "dump"
    setmetatable(o, self)
    self.__index = self
    return o
end

function Persist:exists()
    local mode = lfs.attributes(self.path, "mode")
    if mode then
        return mode == "file"
    end
end

function Persist:timestamp()
    return lfs.attributes(self.path, "modification")
end

function Persist:size()
    return lfs.attributes(self.path, "size")
end

function Persist:load()
    local t, err
    if codecs[self.codec].reads_from_file then
        t, err = codecs[self.codec].deserialize(self.path)
    else
        local str
        str, err = readFile(self.path)
        if not str then
            return nil, err
        end
        t, err = codecs[self.codec].deserialize(str)
    end
    if not t then
        return nil, err
    end
    return t
end

function Persist:save(t, as_bytecode)
    local str, file, err
    str, err = codecs[self.codec].serialize(t, as_bytecode)
    if not str then
        return nil, err
    end
    file, err = io.open(self.path, "wb")
    if not file then
        return nil, err
    end
    file:write(str)
    file:close()
    return true
end

function Persist:delete()
    if not self:exists() then return end
    return os.remove(self.path)
end

function Persist.getCodec(name)
    local fallback = codecs["dump"]
    for key, codec in pairs(codecs) do
        if type(key) == "string" and key == name then
            return codec
        end
    end
    return fallback
end

return Persist
