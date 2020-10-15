local ffi = require("ffi")

-- Utilities functions needed by this plugin, but that may be added to
-- existing base/ffi/ files
local xutil = {}

-- Data compression/decompression of strings thru zlib (may be put in a new base/ffi/zlib.lua)
-- from http://luajit.org/ext_ffi_tutorial.html
ffi.cdef[[
unsigned long compressBound(unsigned long sourceLen);
int compress2(uint8_t *dest, unsigned long *destLen,
              const uint8_t *source, unsigned long sourceLen, int level);
int uncompress(uint8_t *dest, unsigned long *destLen,
               const uint8_t *source, unsigned long sourceLen);
]]
local zlib = ffi.load(ffi.os == "Windows" and "zlib1" or "z")

function xutil.zlib_compress(data)
    local n = zlib.compressBound(#data)
    local buf = ffi.new("uint8_t[?]", n)
    local buflen = ffi.new("unsigned long[1]", n)
    local res = zlib.compress2(buf, buflen, data, #data, 9)
    assert(res == 0)
    return ffi.string(buf, buflen[0])
end

function xutil.zlib_uncompress(zdata, datalen)
    local buf = ffi.new("uint8_t[?]", datalen)
    local buflen = ffi.new("unsigned long[1]", datalen)
    local res = zlib.uncompress(buf, buflen, zdata, #zdata)
    assert(res == 0)
    return ffi.string(buf, buflen[0])
end

return xutil
