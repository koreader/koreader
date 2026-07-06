--[[--
FastDict: StarDict dictionary reader with sidecar offset caches.

Replicates the exact-search behavior of sdcv 0.5.5 (Dict::Lookup +
libwrapper parse_data): binary search over .syn and .idx with
stardict_strcmp, definitions formatted per sametypesequence.

Pure LuaJIT + FFI; no unconditional KOReader dependencies.
]]

local ffi = require("ffi")
local dictzip = require("stardict/dictzip")

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then
    ok_lfs, lfs = pcall(require, "lfs")
end

local M = {}

-- @return size, mtime (mtime is 0 when lfs is unavailable: desktop tests)
local function file_stat(path)
    if ok_lfs then
        local a = lfs.attributes(path)
        if not a then return nil end
        return a.size, a.modification
    end
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size, 0
end
M._file_stat = file_stat -- exposed for tests

local byte = string.byte

--- stardict_strcmp: g_ascii_strcasecmp (sign only), strcmp tiebreak.
function M.cmp(a, b)
    local la, lb = #a, #b
    local n = la < lb and la or lb
    for i = 1, n do
        local ca, cb = byte(a, i), byte(b, i)
        if ca >= 65 and ca <= 90 then ca = ca + 32 end
        if cb >= 65 and cb <= 90 then cb = cb + 32 end
        if ca ~= cb then
            return ca < cb and -1 or 1
        end
    end
    if la ~= lb then
        -- caseless prefix: shorter first
        return la < lb and -1 or 1
    end
    -- caseless equal: bytewise strcmp tiebreak. LuaJIT's string `<`/`>` is a
    -- raw byte comparison (not locale-collation like PUC Lua): this bytewise
    -- behavior is load-bearing for sdcv sort-order parity, do not "fix" it
    -- to locale-aware comparison.
    if a == b then return 0 end
    return a < b and -1 or 1
end

function M.parse_ifo(path)
    local f = io.open(path, "rb")
    if not f then
        return nil, "cannot open " .. path
    end
    local content = f:read("*a") or ""
    f:close()
    if not content:find("StarDict's dict ifo file", 1, true) then
        return nil, "not a StarDict ifo: " .. path
    end
    local info = {}
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then info[k] = v end
    end
    return info
end

local Dict = {}
Dict.__index = Dict

local SUPPORTED_TYPES = { h = true, m = true, w = true, l = true,
                          g = true, x = true, t = true, k = true, y = true }

function M.open(ifo_path, fallback_cache_dir)
    local info, err = M.parse_ifo(ifo_path)
    if not info then
        return nil, err
    end
    local d = setmetatable({
        ifo_path = ifo_path,
        base = (ifo_path:gsub("%.ifo$", "")),
        info = info,
        bookname = info.bookname,
        wordcount = tonumber(info.wordcount) or 0,
        synwordcount = tonumber(info.synwordcount) or 0,
        sametypesequence = info.sametypesequence,
        fallback_cache_dir = fallback_cache_dir,
        supported = true,
    }, Dict)
    if not d.bookname or d.bookname == "" then
        d.supported, d.unsupported_reason = false, "missing bookname"
    elseif info.idxoffsetbits == "64" then
        d.supported, d.unsupported_reason = false, "64-bit idx offsets"
    elseif not d.sametypesequence or not SUPPORTED_TYPES[d.sametypesequence] then
        d.supported, d.unsupported_reason = false,
            "unsupported sametypesequence: " .. tostring(d.sametypesequence)
    elseif not file_stat(d.base .. ".idx") then
        d.supported, d.unsupported_reason = false, "no plain .idx file"
    end
    return d
end

--- Scan a .idx/.syn file once, recording the offset of every entry.
-- stride = fixed bytes after each NUL (8 for .idx with 32-bit offsets, 4 for .syn).
-- Returns a uint32 FFI array with expected_count+1 slots (last = file size).
function M.scan_offsets(path, stride, expected_count)
    local f = io.open(path, "rb")
    if not f then
        return nil, "cannot open " .. path
    end
    local offs = ffi.new("uint32_t[?]", expected_count + 1)
    local count = 0
    local base, buf, pos = 0, "", 1
    offs[0] = 0
    while true do
        local z = buf:find("\0", pos, true)
        if z then
            if count >= expected_count then
                f:close()
                return nil, string.format("scan mismatch in %s: more than %d entries", path, expected_count)
            end
            count = count + 1
            pos = z + stride + 1
            offs[count] = base + pos - 1
        else
            local chunk = f:read(1048576)
            if not chunk then break end
            -- keep unscanned tail; `pos` may point past the buffer end when an
            -- entry's fixed-width tail straddles the refill boundary
            local blen = #buf
            local keep = pos <= blen and buf:sub(pos) or ""
            local skip = pos > blen and (pos - blen - 1) or 0
            buf = keep .. chunk
            base = base + (blen - #keep)
            pos = 1 + skip
        end
    end
    local fsize = f:seek("end")
    f:close()
    if count ~= expected_count or offs[count] ~= fsize then
        return nil, string.format("scan mismatch in %s: %d entries / sentinel %d (expected %d / %d)",
            path, count, count > 0 and tonumber(offs[count]) or -1, expected_count, fsize)
    end
    return offs
end

local CACHE_MAGIC = "FDX1"
local CACHE_VERSION = 1
local HEADER_BYTES = 32 -- 4 magic + 7 * u32

local function pack_u32(...)
    local n = select("#", ...)
    local arr = ffi.new("uint32_t[?]", n, ...)
    return ffi.string(arr, n * 4)
end

function Dict:cache_path()
    if self._cache_path then
        return self._cache_path
    end
    local next_to_dict = self.base .. ".fdx"
    local probe = io.open(next_to_dict, "a+b")
    if probe then
        probe:close()
        self._cache_path = next_to_dict
    else
        local name = self.base:gsub("[^%w%-_.]", "#") .. ".fdx"
        self._cache_path = self.fallback_cache_dir .. "/" .. name
    end
    return self._cache_path
end

function Dict:_build_cache()
    local idx_path = self.base .. ".idx"
    local idx_size, idx_mtime = file_stat(idx_path)
    if not idx_size then
        return nil, "missing " .. idx_path
    end
    local idx_off, err = M.scan_offsets(idx_path, 8, self.wordcount)
    if not idx_off then
        return nil, err
    end
    local syn_off, syn_size, syn_mtime
    if self.synwordcount > 0 then
        local syn_path = self.base .. ".syn"
        syn_size, syn_mtime = file_stat(syn_path)
        if not syn_size then
            return nil, "missing " .. syn_path
        end
        syn_off, err = M.scan_offsets(syn_path, 4, self.synwordcount)
        if not syn_off then
            return nil, err
        end
    end
    local cp = self:cache_path()
    local tmp = cp .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then
        return nil, "cannot write " .. tmp
    end
    f:write(CACHE_MAGIC)
    f:write(pack_u32(CACHE_VERSION, idx_size, idx_mtime,
        syn_size or 0, syn_mtime or 0,
        self.wordcount + 1, syn_off and (self.synwordcount + 1) or 0))
    f:write(ffi.string(idx_off, (self.wordcount + 1) * 4))
    if syn_off then
        f:write(ffi.string(syn_off, (self.synwordcount + 1) * 4))
    end
    f:close()
    -- required on FAT/vfat filesystems (Kindle user storage), where rename
    -- won't overwrite an existing file.
    os.remove(cp)
    local ok = os.rename(tmp, cp)
    if not ok then
        return nil, "cannot rename " .. tmp
    end
    return true
end

function Dict:_load_cache()
    local cp = self:cache_path()
    local f = io.open(cp, "rb")
    if not f then
        return nil
    end
    local blob = f:read("*a")
    f:close()
    if not blob or #blob < HEADER_BYTES or blob:sub(1, 4) ~= CACHE_MAGIC then
        return nil
    end
    local hdr = ffi.cast("const uint32_t *", ffi.cast("const char *", blob) + 4)
    local version, idx_size, idx_mtime = hdr[0], hdr[1], hdr[2]
    local syn_size, syn_mtime, n_idx, n_syn = hdr[3], hdr[4], hdr[5], hdr[6]
    if version ~= CACHE_VERSION then
        return nil
    end
    if #blob ~= HEADER_BYTES + (tonumber(n_idx) + tonumber(n_syn)) * 4 then
        return nil
    end
    local cur_idx_size, cur_idx_mtime = file_stat(self.base .. ".idx")
    if cur_idx_size ~= tonumber(idx_size) or cur_idx_mtime ~= tonumber(idx_mtime) then
        return nil
    end
    if self.synwordcount > 0 then
        local cur_syn_size, cur_syn_mtime = file_stat(self.base .. ".syn")
        if cur_syn_size ~= tonumber(syn_size) or cur_syn_mtime ~= tonumber(syn_mtime) then
            return nil
        end
        if tonumber(n_syn) ~= self.synwordcount + 1 then
            return nil
        end
    end
    if tonumber(n_idx) ~= self.wordcount + 1 then
        return nil
    end
    self._cache_blob = blob -- anchor: FFI pointers below point into this string
    local p = ffi.cast("const uint8_t *", blob)
    self.idx_off = ffi.cast("const uint32_t *", p + HEADER_BYTES)
    self.n_idx = self.wordcount
    if self.synwordcount > 0 then
        self.syn_off = ffi.cast("const uint32_t *", p + HEADER_BYTES + tonumber(n_idx) * 4)
        self.n_syn = self.synwordcount
    else
        self.syn_off, self.n_syn = nil, 0
    end
    return true
end

local function plain_reader(path)
    local f = io.open(path, "rb")
    if not f then
        return nil, "cannot open " .. path
    end
    return {
        read = function(_, off, size)
            f:seek("set", off)
            return f:read(size) or ""
        end,
        close = function() f:close() end,
    }
end

function Dict:ensure_index()
    if self.ready then
        return true
    end
    if not self.supported then
        return nil, "unsupported dictionary: " .. tostring(self.unsupported_reason)
    end
    if not self.dict_f then
        local dz = self.base .. ".dict.dz"
        local r, err
        if file_stat(dz) then
            r, err = dictzip.open(dz)
        else
            r, err = plain_reader(self.base .. ".dict")
        end
        if not r then
            return nil, err
        end
        self.dict_f = r
    end
    self.idx_f = self.idx_f or io.open(self.base .. ".idx", "rb")
    if not self.idx_f then
        return nil, "cannot open " .. self.base .. ".idx"
    end
    if self.synwordcount > 0 then
        self.syn_f = self.syn_f or io.open(self.base .. ".syn", "rb")
        if not self.syn_f then
            return nil, "cannot open " .. self.base .. ".syn"
        end
    end
    if not self:_load_cache() then
        local ok, err = self:_build_cache()
        if not ok then
            return nil, err
        end
        if not self:_load_cache() then
            return nil, "sidecar cache unreadable after build: " .. self:cache_path()
        end
    end
    self.ready = true
    return true
end

function Dict:close()
    if self.dict_f then self.dict_f:close() self.dict_f = nil end
    if self.idx_f then self.idx_f:close() self.idx_f = nil end
    if self.syn_f then self.syn_f:close() self.syn_f = nil end
    self.ready = false
end

--- Port of sdcv's xdxf2text with colorize=false.
local function xdxf2text(p)
    local res = {}
    local i, n = 1, #p
    while i <= n do
        local c = p:sub(i, i)
        if c ~= "<" then
            if p:sub(i, i + 3) == "&gt;" then
                res[#res + 1] = ">" ; i = i + 4
            elseif p:sub(i, i + 3) == "&lt;" then
                res[#res + 1] = "<" ; i = i + 4
            elseif p:sub(i, i + 4) == "&amp;" then
                res[#res + 1] = "&" ; i = i + 5
            elseif p:sub(i, i + 5) == "&quot;" then
                res[#res + 1] = "\"" ; i = i + 6
            elseif p:sub(i, i + 5) == "&apos;" then
                res[#res + 1] = "'" ; i = i + 6
            else
                res[#res + 1] = c ; i = i + 1
            end
        else
            local gt = p:find(">", i, true)
            if not gt then
                i = i + 1 -- sdcv skips a lone '<'
            else
                local name = p:sub(i + 1, gt - 1)
                local nexti = gt + 1
                if name == "k" then
                    local close = p:find("</k>", gt, true)
                    if close then nexti = close + 4 end
                elseif name == "tr" then
                    res[#res + 1] = "["
                elseif name == "/tr" then
                    res[#res + 1] = "]"
                end
                -- every other tag renders as nothing without colorize
                i = nexti
            end
        end
    end
    return table.concat(res)
end
M._xdxf2text = xdxf2text -- exposed for tests

--- Format a raw .dict payload the way sdcv's parse_data renders it in JSON mode.
function Dict:_format(payload)
    local t = self.sametypesequence
    local seg = payload:match("^[^%z]*") -- sdcv reads with strlen()
    if #seg == 0 then
        return ""
    end
    if t == "x" or t == "g" then
        return "\n" .. xdxf2text(seg)
    elseif t == "t" then
        return "\n[" .. seg .. "]"
    elseif t == "k" or t == "y" then
        return seg
    else -- h, m, w, l
        return "\n" .. seg
    end
end

function Dict:_read_range(f, from, to)
    f:seek("set", from)
    return f:read(to - from) or ""
end

function Dict:_idx_entry(i) -- 0-based; returns word, offset, size
    local raw = self:_read_range(self.idx_f, tonumber(self.idx_off[i]), tonumber(self.idx_off[i + 1]))
    local z = raw:find("\0", 1, true)
    local o1, o2, o3, o4, s1, s2, s3, s4 = raw:byte(z + 1, z + 8)
    return raw:sub(1, z - 1),
        ((o1 * 256 + o2) * 256 + o3) * 256 + o4,
        ((s1 * 256 + s2) * 256 + s3) * 256 + s4
end

function Dict:_idx_word(i)
    local raw = self:_read_range(self.idx_f, tonumber(self.idx_off[i]), tonumber(self.idx_off[i + 1]))
    return raw:sub(1, raw:find("\0", 1, true) - 1)
end

function Dict:_syn_entry(i) -- 0-based; returns word, target idx entry number
    local raw = self:_read_range(self.syn_f, tonumber(self.syn_off[i]), tonumber(self.syn_off[i + 1]))
    local z = raw:find("\0", 1, true)
    local n1, n2, n3, n4 = raw:byte(z + 1, z + 4)
    return raw:sub(1, z - 1), ((n1 * 256 + n2) * 256 + n3) * 256 + n4
end

-- Binary search over entries 0..n-1 using M.cmp; returns the inclusive
-- range [first, last] of entries equal to word, or nil.
local function bsearch(n, getword, word)
    local lo, hi = 0, n - 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local c = M.cmp(word, getword(mid))
        if c > 0 then
            lo = mid + 1
        elseif c < 0 then
            hi = mid - 1
        else
            local first, last = mid, mid
            while first > 0 and M.cmp(word, getword(first - 1)) == 0 do
                first = first - 1
            end
            while last < n - 1 and M.cmp(word, getword(last + 1)) == 0 do
                last = last + 1
            end
            return first, last
        end
    end
    return nil
end

--- Exact lookup, replicating sdcv's Dict::Lookup + SimpleLookup rendering.
-- @return array of { word = idx headword, definition = formatted text }
function Dict:lookup(word)
    local ok, err = self:ensure_index()
    if not ok then
        error(err)
    end
    local hits, seen = {}, {}
    if self.n_syn and self.n_syn > 0 then
        local first, last = bsearch(self.n_syn,
            function(i) return (self:_syn_entry(i)) end, word)
        if first then
            for i = first, last do
                local _, target = self:_syn_entry(i)
                if target < self.n_idx and not seen[target] then
                    seen[target] = true
                    hits[#hits + 1] = target
                end
            end
        end
    end
    local first, last = bsearch(self.n_idx,
        function(i) return (self:_idx_word(i)) end, word)
    if first then
        for i = first, last do
            if not seen[i] then
                seen[i] = true
                hits[#hits + 1] = i
            end
        end
    end
    table.sort(hits)
    local results = {}
    for _, i in ipairs(hits) do
        local w, off, size = self:_idx_entry(i)
        results[#results + 1] = {
            word = w,
            definition = self:_format(self.dict_f:read(off, size)),
        }
    end
    return results
end

return M
