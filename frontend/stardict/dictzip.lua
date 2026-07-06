--[[--
FastDict: random-access reader for dictzip (.dz) files.

A .dz file is a gzip member whose FEXTRA header carries an 'RA' subfield
listing the compressed size of each fixed-length (chlen) chunk. Chunks are
separated with Z_FULL_FLUSH, so each one can be inflated independently with
a raw-deflate inflater.

Pure LuaJIT + FFI; no KOReader dependencies.
]]

local bit = require("bit")
local ffi = require("ffi")

pcall(ffi.cdef, [[
typedef struct fastdict_z_stream {
    const uint8_t *next_in;
    unsigned avail_in;
    unsigned long total_in;
    uint8_t *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state;
    void *zalloc;
    void *zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} fastdict_z_stream;
int inflateInit2_(fastdict_z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(fastdict_z_stream *strm, int flush);
int inflateEnd(fastdict_z_stream *strm);
const char *zlibVersion(void);
]])

local libz
do
    -- ffi.loadlib is a KOReader extension; plain ffi.load for desktop luajit.
    local ok, lib = pcall(function() return ffi.loadlib("z", 1) end)
    if ok then libz = lib else libz = ffi.load("z") end
end

-- Flush-when-full cache size: once cache_count reaches this, the whole
-- chunk cache is cleared (not an LRU eviction of individual entries).
local MAX_CACHED_CHUNKS = 8

local function inflate_raw(cdata, max_out)
    local strm = ffi.new("fastdict_z_stream")
    local ret = libz.inflateInit2_(strm, -15, libz.zlibVersion(), ffi.sizeof("fastdict_z_stream"))
    if ret ~= 0 then
        error("inflateInit2 failed: " .. ret)
    end
    local inbuf = ffi.new("uint8_t[?]", #cdata)
    ffi.copy(inbuf, cdata, #cdata)
    local outbuf = ffi.new("uint8_t[?]", max_out)
    strm.next_in, strm.avail_in = inbuf, #cdata
    strm.next_out, strm.avail_out = outbuf, max_out
    ret = libz.inflate(strm, 0) -- Z_NO_FLUSH
    local produced = max_out - strm.avail_out
    libz.inflateEnd(strm)
    -- Z_OK (0) mid-stream chunk, Z_STREAM_END (1) final chunk,
    -- Z_BUF_ERROR (-5) all input consumed with output space left.
    if ret ~= 0 and ret ~= 1 and ret ~= -5 then
        error("inflate failed: " .. ret)
    end
    return ffi.string(outbuf, produced)
end

local function u16le(s, pos)
    local a, b = s:byte(pos, pos + 1)
    return a + b * 256
end

local DictZip = {}
DictZip.__index = DictZip

local M = {}

function M.open(path)
    local f = io.open(path, "rb")
    if not f then
        return nil, "cannot open " .. path
    end
    local head = f:read(12)
    if not head or #head < 12 or head:byte(1) ~= 0x1f or head:byte(2) ~= 0x8b then
        f:close()
        return nil, "not a gzip file: " .. path
    end
    local flg = head:byte(4)
    if bit.band(flg, 0x04) == 0 then
        f:close()
        return nil, "no FEXTRA field (not dictzip): " .. path
    end
    local xlen = u16le(head, 11)
    local extra = f:read(xlen)
    if not extra or #extra < xlen then
        f:close()
        return nil, "truncated FEXTRA: " .. path
    end
    local chlen, sizes
    local pos = 1
    while pos + 3 <= xlen do
        local si1, si2 = extra:byte(pos, pos + 1)
        local len = u16le(extra, pos + 2)
        if si1 == 82 and si2 == 65 then -- 'R','A'
            chlen = u16le(extra, pos + 6)
            local chcnt = u16le(extra, pos + 8)
            sizes = {}
            local p = pos + 10
            for i = 1, chcnt do
                sizes[i] = u16le(extra, p)
                p = p + 2
            end
        end
        pos = pos + 4 + len
    end
    if not chlen or not sizes then
        f:close()
        return nil, "no RA subfield (not dictzip): " .. path
    end
    -- skip optional FNAME / FCOMMENT / FHCRC to find the data start
    for _, flag in ipairs({ 0x08, 0x10 }) do
        if bit.band(flg, flag) ~= 0 then
            repeat
                local c = f:read(1)
                if not c then f:close() return nil, "truncated gzip header" end
            until c == "\0"
        end
    end
    if bit.band(flg, 0x02) ~= 0 then
        f:read(2)
    end
    local data_start = f:seek()
    local offs = {}
    local o = data_start
    for i = 1, #sizes do
        offs[i] = o
        o = o + sizes[i]
    end
    return setmetatable({
        f = f,
        chlen = chlen,
        sizes = sizes,
        offs = offs,
        cache = {},
        cache_count = 0,
    }, DictZip)
end

function DictZip:_chunk(i) -- 0-based chunk number
    local cached = self.cache[i]
    if cached then
        return cached
    end
    if i < 0 or i >= #self.sizes then
        error("chunk out of range: " .. i)
    end
    self.f:seek("set", self.offs[i + 1])
    local cdata = self.f:read(self.sizes[i + 1])
    local out = inflate_raw(cdata, self.chlen)
    -- flush-when-full: the whole cache is cleared once it reaches
    -- MAX_CACHED_CHUNKS, rather than evicting a single least-recently-used
    -- entry like a true LRU would.
    if self.cache_count >= MAX_CACHED_CHUNKS then
        self.cache = {}
        self.cache_count = 0
    end
    self.cache[i] = out
    self.cache_count = self.cache_count + 1
    return out
end

function DictZip:read(offset, size)
    if size <= 0 then
        return ""
    end
    local first = math.floor(offset / self.chlen)
    local last = math.floor((offset + size - 1) / self.chlen)
    local parts = {}
    for i = first, last do
        parts[#parts + 1] = self:_chunk(i)
    end
    local blob = table.concat(parts)
    local rel = offset - first * self.chlen
    return blob:sub(rel + 1, rel + size)
end

function DictZip:close()
    self.f:close()
end

return M
