local bitser = require("ffi/bitser")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")

local codecs = {
    -- bitser: binary form, fast encode/decode, low size. Not human readable.
    bitser = {
        serialize = function(t, file)
            local ok, str = pcall(bitser.dumps, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t)
            end
            return str
        end,

        deserialize = function(file)
            local f, err, str
            f, err = io.open(file, "rb")
            if not f then
                return nil, err
            end
            str, err = f:read("*a")
            f:close()
            if not str then
                return nil, err
            end
            local ok, t = pcall(bitser.loads, str)
            if not ok then
                return nil, "malformed serialized data"
            end
            return t
        end,
    },
    -- dump: human readable, pretty printed, fast enough for most user cases.
    dump = {
        serialize = function(t, file, as_bytecode)
            local str
            if as_bytecode then
                local bytecode, err = load("return " .. dump(t))
                if not bytecode then
                    print("cannot convert table to bytecode: %s, ignoring", err)
                else
                    str = string.dump(bytecode, true)
                end
            end
            if not str then
                str = "return " .. dump(t)
            end
            return str
        end,

        deserialize = function(file)
            local ok, t, err = pcall(dofile, file)
            if not ok then
                return nil, err
            end
            return t
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
    local t, err = codecs[self.codec].deserialize(self.path)
    if not t then
        return nil, err
    end
    return t
end

function Persist:save(t, as_bytecode)
    local str, file, err
    str, err = codecs[self.codec].serialize(t, self.path, as_bytecode)
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

return Persist
