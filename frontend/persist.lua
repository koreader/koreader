local bitser = require("ffi/bitser")
local buffer = require("string.buffer")
local dump = require("dump")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local zstd = require("ffi/zstd")

local C = ffi.C

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
        reads_from_file = false,
        writes_to_file = false,

        serialize = function(t)
            local ok, str = pcall(bitser.dumps, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            return str
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
        reads_from_file = false,
        writes_to_file = false,

        serialize = function(t)
            local ok, str = pcall(buffer.encode, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end
            return str
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
        reads_from_file = true,
        writes_to_file = true,

        serialize = function(t, as_bytecode, path)
            local ok, str = pcall(buffer.encode, t)
            if not ok then
                return nil, "cannot serialize " .. tostring(t) .. " (" .. str .. ")"
            end

            local cbuff, clen = zstd.zstd_compress(str, #str)

            local f = C.fopen(path, "wb")
            if f == nil then
                return nil, "fopen: " .. ffi.string(C.strerror(ffi.errno()))
            end
            if C.fwrite(cbuff, 1, clen, f) < clen then
                C.fclose(f)
                C.free(cbuff)
                return nil, "failed to write file"
            end
            C.fclose(f)
            C.free(cbuff)

            --- @note: Slight API extension for TileCacheItem, which needs to know the on-disk size, and saves us a :size() call
            return true, clen
        end,

        deserialize = function(path)
            local f = C.fopen(path, "rb")
            if f == nil then
                return nil, "fopen: " .. ffi.string(C.strerror(ffi.errno()))
            end
            local size = lfs.attributes(path, "size")
            -- NOTE: In a perfect world, we'd just mmap the file.
            --       But that's problematic on a portability level: while mmap is POSIX, implementations differ,
            --       and some old platforms don't support mmap-on-vfat (Legacy Kindle) :'(.
            local data = C.malloc(size)
            if data == nil then
                C.fclose(f)
                return nil, "failed to allocate read buffer"
            end
            if C.fread(data, 1, size, f) < size or C.ferror(f) ~= 0 then
                C.free(data)
                C.fclose(f)
                return nil, "failed to read file"
            end
            C.fclose(f)

            local buff, ulen = zstd.zstd_uncompress(data, size)
            C.free(data)

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
        reads_from_file = true,
        writes_to_file = false,

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
    if codecs[self.codec].writes_to_file then
        local ok, err = codecs[self.codec].serialize(t, as_bytecode, self.path)
        if not ok then
            return nil, err
        end

        -- c.f., note above, err is the on-disk size
        return true, err
    else
        local str, err = codecs[self.codec].serialize(t, as_bytecode)
        if not str then
            return nil, err
        end
        local file
        file, err = io.open(self.path, "wb")
        if not file then
            return nil, err
        end
        file:write(str)
        file:close()
    end
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
