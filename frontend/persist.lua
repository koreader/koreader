local bitser = require("ffi/bitser")
local buffer = require("string.buffer")
local dump = require("dump")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local serpent = require("ffi/serpent")
local zstd = require("ffi/zstd")

local C = ffi.C
require("ffi/posix_h")

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
    -- bitser: binary format, fast encode/decode, low size. Not human readable.
    bitser = {
        id = "bitser",

        serialize = function(t)
            local ok, str = pcall(bitser.dumps, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            return str, #str
        end,

        deserialize = function(str)
            local ok, t = pcall(bitser.loads, str)
            if not ok then
                return nil, "malformed serialized data: " .. t
            end
            return t
        end,
    },
    -- luajit: binary format, optimized for speed, not size (combine w/ zstd if necessary). Not human readable.
    --         Slightly larger on-disk representation than bitser, *much* faster to decode, slightly faster to encode.
    luajit = {
        id = "luajit",

        serialize = function(t)
            local ok, str = pcall(buffer.encode, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            return str, #str
        end,

        deserialize = function(str)
            local ok, t = pcall(buffer.decode, str)
            if not ok then
                return nil, "malformed serialized data (" .. t .. ")"
            end
            return t
        end,
    },
    -- zstd: luajit, but compressed w/ zstd ;). Much smaller, at a very small performance cost (decompressing is *fast*).
    zstd = {
        id = "zstd",

        serialize = function(t, as_bytecode)
            local ok, str = pcall(buffer.encode, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            local buff, clen = zstd.zstd_compress(str, #str)
            str = ffi.string(buff, clen)
            C.free(buff)
            return str, tonumber(clen)
        end,

        deserialize = function(data)
            local buff, ulen = zstd.zstd_uncompress(data, #data)
            local str = ffi.string(buff, ulen)
            C.free(buff)
            local ok, t = pcall(buffer.decode, str)
            if not ok then
                return nil, "malformed serialized data (" .. t .. ")"
            end
            return t
        end,
    },
    -- dump: human readable, pretty printed, fast enough for most use cases.
    dump = {
        id = "dump",

        serialize = function(t, as_bytecode)
            local ok, d = pcall(dump, t)
            if not ok then
                return nil, d
            end
            d = "return " .. d
            if as_bytecode then
                local bytecode, err = load("return " .. d)
                if not bytecode then
                    logger.warn("cannot convert table to bytecode", err, "fallback to text")
                else
                    d = string.dump(bytecode, true)
                end
            end
            return d, #d
        end,

        deserialize = function(str)
            local t, err = loadstring(str)
            if not t then
                return nil, err
            end
            return t()
        end,
    },
    -- serpent: human readable (-ish), more thorough than dump (in particular, supports serializing functions)
    -- NOTE: if you want pretty printing, pass { sortkeys = true, compact = false, indent = "  " } to serpent's second arg.
    serpent = {
        id = "serpent",

        serialize = function(t)
            local ok, str = pcall(serpent.dump, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            return str, #str
        end,

        deserialize = function(str)
            local ok, t = serpent.load(str, {safe=false})
            if not ok then
                return nil, "malformed serialized data (" .. t .. ")"
            end
            return t
        end,
    }
}

local Persist = {}

function Persist:new(o)
    o = o or {}
    assert(type(o.path) == "string", "path is required")
    o.codec = o.codec or "serpent"
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
    local str, err
    str, err = readFile(self.path)
    if not str then
        return nil, err
    end
    local t
    t, err = codecs[self.codec].deserialize(str)
    if not t then
        return nil, err
    end
    self.loaded = true
    return t
end

function Persist:save(t, as_bytecode)
    local ok, err
    ok, err = codecs[self.codec].serialize(t, as_bytecode)
    if not ok then
        return nil, err
    end
    local file
    file, err = io.open(self.path, "wb")
    if not file then
        return nil, err
    end
    file:write(ok)
    ffiUtil.fsyncOpenedFile(file)
    file:close()
    -- If we've just created the file, fsync the directory, too
    if not self.loaded then
        ffiUtil.fsyncDirectory(self.path)
        self.loaded = true
    end
    -- note: err is the serialized size
    return true, err
end

function Persist:delete()
    if not self:exists() then return end
    return os.remove(self.path)
end

function Persist.getCodec(name)
    for key, codec in pairs(codecs) do
        if key == name then
            return codec
        end
    end
    return codecs["serpent"]
end

return Persist
