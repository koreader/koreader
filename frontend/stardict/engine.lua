--[[--
FastDict: multi-dictionary lookup orchestration.

Scans dictionary directories for .ifo files, opens them with stardict.lua,
and answers batched exact lookups with the same dictionary filtering and
ordering semantics as KOReader's sdcv invocation (-u bookname options).

Pure LuaJIT; no unconditional KOReader dependencies.
]]

local stardict = require("stardict/stardict")

local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then
    ok_lfs, lfs = pcall(require, "lfs")
end

local M = {}

local Engine = {}
Engine.__index = Engine

function M.new(opts)
    return setmetatable({
        dict_dirs = assert(opts.dict_dirs),
        cache_dir = opts.cache_dir or "/tmp",
        dicts = nil,
    }, Engine)
end

local function find_ifos(dir, out)
    if ok_lfs then
        local mode = lfs.attributes(dir, "mode")
        if mode ~= "directory" then return end
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." and not name:match("^%.") then
                local path = dir .. "/" .. name
                local m = lfs.attributes(path, "mode")
                if m == "directory" then
                    find_ifos(path, out)
                elseif m == "file" and name:match("%.ifo$") then
                    out[#out + 1] = path
                end
            end
        end
    else
        -- desktop test fallback without lfs. %q is Lua quoting (adequate
        -- here for test-only use); -not -path '*/.*' also excludes a root
        -- dir that itself lives under a dot-directory.
        local p = io.popen(string.format("find %q -name '*.ifo' -not -path '*/.*' 2>/dev/null", dir))
        if p then
            for line in p:lines() do out[#out + 1] = line end
            p:close()
        end
    end
end

function Engine:load()
    self.dicts = {}
    self.by_name = {}
    for _, dir in ipairs(self.dict_dirs) do
        local ifos = {}
        find_ifos(dir, ifos)
        -- sdcv uses readdir order; sorted order is a deliberate deterministic
        -- choice (only observable when no dict_names filter is passed).
        table.sort(ifos)
        for _, ifo in ipairs(ifos) do
            local d = stardict.open(ifo, self.cache_dir)
            if d then
                self.dicts[#self.dicts + 1] = d
                if d.bookname and not self.by_name[d.bookname] then
                    self.by_name[d.bookname] = d
                end
            end
        end
    end
end

-- Words sdcv would route to regex/fuzzy/data lookup instead of simple lookup
-- (analyze_query): leading '/' or '|', any '*', '?' or '\'.
local function is_special(word)
    return word:sub(1, 1) == "/" or word:sub(1, 1) == "|"
        or word:find("[*?\\]") ~= nil
end

--- Batched exact lookup.
-- @param words array of query strings
-- @param dict_names optional array of booknames (KOReader's enabled dicts, in
--   priority order); nil or empty = all dictionaries, like sdcv without -u.
-- @return results[i] = array of {dict, word, definition} for words[i],
--   or nil, reason when this call must be answered by sdcv instead.
function Engine:lookup_words(words, dict_names)
    for _, w in ipairs(words) do
        if is_special(w) then
            return nil, "special query syntax: " .. w
        end
    end
    if not self.dicts then
        self:load()
    end
    if #self.dicts == 0 then
        return nil, "no dictionaries found"
    end
    local order = {}
    if dict_names and #dict_names > 0 then
        for _, name in ipairs(dict_names) do
            local d = self.by_name[name]
            if d then -- unknown names are skipped, like sdcv's unknown -u
                if not d.supported then
                    return nil, "unsupported dictionary enabled: " .. name
                end
                order[#order + 1] = d
            end
        end
    else
        -- Deliberate deviation from sdcv: sdcv is invoked once per dict dir
        -- (all data/dict results precede data/dict_ext per word) and queries
        -- same-bookname duplicates in both dirs, while the engine merges
        -- dirs, orders strictly by dict_names priority, and first-wins on
        -- duplicate booknames.
        for _, d in ipairs(self.dicts) do
            if not d.supported then
                return nil, "unsupported dictionary present: " .. (d.bookname or d.ifo_path)
            end
            order[#order + 1] = d
        end
    end
    local all = {}
    for wi, word in ipairs(words) do
        local per = {}
        for _, d in ipairs(order) do
            local ok, entries = pcall(d.lookup, d, word)
            if not ok then
                -- quarantine this dictionary and let sdcv answer the call
                d.supported = false
                d.unsupported_reason = "lookup error: " .. tostring(entries)
                return nil, "dictionary failed, deferring to sdcv: " .. tostring(entries)
            end
            for _, r in ipairs(entries) do
                per[#per + 1] = { dict = d.bookname, word = r.word, definition = r.definition }
            end
        end
        all[wi] = per
    end
    return all
end

--- Build (or load) sidecar caches for every supported dictionary.
function Engine:build_all()
    if not self.dicts then
        self:load()
    end
    local first_err
    for _, d in ipairs(self.dicts) do
        if d.supported then
            local ok, err = d:ensure_index()
            if not ok then
                first_err = first_err or err
            end
        end
    end
    if first_err then
        return nil, first_err
    end
    return true
end

--- Delete sidecar caches and rebuild from scratch, re-scanning dictionaries
-- (this also clears any quarantine from transient lookup failures).
function Engine:rebuild_all()
    if not self.dicts then
        self:load()
    end
    for _, d in ipairs(self.dicts) do
        d:close()
        d.ready = false
        os.remove(d:cache_path())
    end
    self.dicts = nil
    self.by_name = nil
    return self:build_all()
end

function Engine:status()
    if not self.dicts then
        self:load()
    end
    local st = {}
    for _, d in ipairs(self.dicts) do
        st[#st + 1] = {
            bookname = d.bookname or d.ifo_path,
            supported = d.supported,
            ready = d.ready or false,
            reason = d.unsupported_reason,
        }
    end
    return st
end

return M
