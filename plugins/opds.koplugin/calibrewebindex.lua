--[[--
Device-side bookkeeping for the Calibre-Web view.

* `Store`: persistent settings, confirmed book mappings and cached snapshots (never desktop Calibre files).
* `discoverRoots` / `scan`: inventory of supported books on accessible user storage.
* `derive`: presence status computed from evidence (mappings, snapshots, inventory), never from saved flags.
--]]

local LuaSettings = require("luasettings")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local CalibreWebIndex = {
    -- A remote snapshot older than this can no longer prove absence
    stale_after = 7 * 24 * 3600,
    STATUS_BOTH = "both",
    STATUS_LOCAL = "local",
    STATUS_REMOTE = "remote",
    STATUS_UNKNOWN = "unknown",
}

-- Store ------------------------------------------------------------------------------------------

local Store = {}
Store.__index = Store
CalibreWebIndex.Store = Store

function Store:new(dir)
    local o = setmetatable({ dir = dir }, self)
    o.settings = LuaSettings:open(dir .. "/calibreweb.lua")
    o.cache = LuaSettings:open(dir .. "/calibreweb_cache.lua")
    return o
end

function Store:getConfig()
    return self.settings:readSetting("config", {})
end

function Store:saveConfig(config)
    self.settings:saveSetting("config", config)
    self.dirty = true
end

function Store:getAccount(account_key)
    local accounts = self.settings:readSetting("accounts", {})
    if not accounts[account_key] then
        accounts[account_key] = { mappings = {}, pending_uploads = {} }
        self.dirty = true
    end
    return accounts[account_key]
end

--- Last *complete* catalog snapshot for an account. Incomplete refreshes never replace it.
function Store:getSnapshot(account_key)
    return self.cache:readSetting("snapshots", {})[account_key]
end

function Store:saveSnapshot(account_key, snapshot)
    if not (snapshot and snapshot.complete) then return false end
    self.cache:readSetting("snapshots", {})[account_key] = snapshot
    self.cache_dirty = true
    return true
end

--- Last complete device inventory (shared by all accounts).
function Store:getInventory()
    return self.cache:readSetting("inventory")
end

function Store:saveInventory(inventory)
    if not (inventory and inventory.complete) then return false end
    self.cache:saveSetting("inventory", inventory)
    self.cache_dirty = true
    return true
end

function Store:markDirty()
    self.dirty = true
end

function Store:flush()
    if self.dirty then
        self.settings:flush()
        self.dirty = nil
    end
    if self.cache_dirty then
        self.cache:flush()
        self.cache_dirty = nil
    end
end

-- Mappings ---------------------------------------------------------------------------------------

--- Records a confirmed link between a remote book and a local file.
-- @tparam string source "download", "upload", "uuid" or "manual"
function CalibreWebIndex.link(account, remote_book, path, format, source)
    local key = remote_book.uuid or remote_book.key
    local mapping = account.mappings[key]
    if not mapping then
        mapping = { files = {} }
        account.mappings[key] = mapping
    end
    mapping.uuid = remote_book.uuid
    mapping.id = remote_book.id
    mapping.title = remote_book.title
    mapping.authors = remote_book.authors
    -- A path belongs to at most one remote book
    for other_key, other in pairs(account.mappings) do
        if other_key ~= key and other.files[path] then
            other.files[path] = nil
            if next(other.files) == nil then account.mappings[other_key] = nil end
        end
    end
    local attr = lfs.attributes(path) or {}
    mapping.files[path] = {
        format = format and format:upper() or util.getFileNameSuffix(path):upper(),
        source = source,
        linked_at = os.time(),
        size = attr.size,
        mtime = attr.modification,
    }
    account.pending_uploads[path] = nil
    return mapping
end

function CalibreWebIndex.unlink(account, key, path)
    local mapping = account.mappings[key]
    if not mapping then return end
    mapping.files[path] = nil
    if next(mapping.files) == nil then account.mappings[key] = nil end
end

--- Extracts Calibre book UUIDs from a document's `identifiers` property.
function CalibreWebIndex.parseIdentifiers(identifiers)
    local found = {}
    if type(identifiers) ~= "string" then return found end
    for line in identifiers:gmatch("[^\n]+") do
        local scheme, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        if scheme then
            scheme = scheme:lower()
            value = value:lower():gsub("^urn:uuid:", "")
            if (scheme == "calibre" or scheme == "uuid") and value:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
                found[value] = scheme
            end
        end
    end
    return found
end

--- Compares a local document's identifiers with the remote UUID it is mapped to.
-- Drops the mapping on a mismatch.
-- @treturn string "match", "mismatch" or "unknown"
function CalibreWebIndex.verifyIdentity(account, key, path, identifiers)
    local mapping = account.mappings[key]
    if not mapping or not mapping.uuid then return "unknown" end
    local ids = CalibreWebIndex.parseIdentifiers(identifiers)
    if ids[mapping.uuid:lower()] then return "match" end
    for _, scheme in pairs(ids) do
        if scheme == "calibre" then
            CalibreWebIndex.unlink(account, key, path)
            return "mismatch"
        end
    end
    return "unknown"
end

--- Turns pending uploads into mappings once the remote snapshot shows the uploaded book.
-- @treturn int number of reconciled uploads
function CalibreWebIndex.reconcileUploads(account, snapshot_books)
    local by_id = {}
    for _, book in pairs(snapshot_books or {}) do
        if book.id then by_id[book.id] = book end
    end
    local reconciled = 0
    for path, pending in pairs(account.pending_uploads) do
        local book = pending.book_id and by_id[pending.book_id]
        if book and book.formats[pending.format] then
            CalibreWebIndex.link(account, book, path, pending.format, "upload")
            reconciled = reconciled + 1
        end
    end
    return reconciled
end

-- Storage roots ----------------------------------------------------------------------------------

local function realpath(path)
    return ffiUtil.realpath(path) or path
end

local function isUnder(path, root)
    return path == root or util.stringStartsWith(path, root == "/" and "/" or root .. "/")
end
CalibreWebIndex.isUnder = isUnder

--- Lists user storage roots worth scanning.
-- @treturn table roots { {path=, kind=, label=} }, boolean whether platform enumeration is complete
function CalibreWebIndex.discoverRoots(Device, home_dir, extra_roots)
    local candidates = {}
    local function add(path, kind)
        if path and path ~= "" then table.insert(candidates, { path = path, kind = kind }) end
    end
    add(home_dir, "home")
    add(Device.home_dir, "device")
    local enumeration_complete = false
    if Device:isAndroid() then
        local ok, sd_path = Device:hasExternalSD()
        if ok then add(sd_path, "external") end
        -- Other volumes (USB OTG, secondary SD) aren't enumerated: users can add them manually
    elseif Device:isKobo() or Device:isCervantes() then
        add("/mnt/sd", "external")
        enumeration_complete = true
    elseif Device:isPocketBook() then
        add("/mnt/ext2", "external")
        enumeration_complete = true
    elseif Device:isKindle() or Device:isRemarkable() then
        enumeration_complete = true
    end
    for _, path in ipairs(extra_roots or {}) do add(path, "user") end
    return CalibreWebIndex.normalizeRoots(candidates), enumeration_complete
end

--- Resolves, de-duplicates and drops nested roots. The filesystem root is never a scan root.
function CalibreWebIndex.normalizeRoots(candidates)
    local resolved = {}
    for i, root in ipairs(candidates) do
        local path = root.path:gsub("/+$", "")
        if path ~= "" then
            local real = lfs.attributes(path, "mode") == "directory" and realpath(path) or path
            if real ~= "/" then
                table.insert(resolved, { path = real, kind = root.kind, configured = root.path, order = i })
            end
        end
    end
    -- Shortest first, so nested roots are dropped; ties keep the configuration order
    table.sort(resolved, function(a, b)
        if #a.path ~= #b.path then return #a.path < #b.path end
        return a.order < b.order
    end)
    local roots = {}
    for _, root in ipairs(resolved) do
        local nested = false
        for _, kept in ipairs(roots) do
            if isUnder(root.path, kept.path) then nested = true break end
        end
        if not nested then table.insert(roots, root) end
    end
    return roots
end

-- Scanning ---------------------------------------------------------------------------------------

local default_skip_dirs = {
    -- Android app-private storage
    "^Android$",
    "^%.android_secure$",
    "^LOST%.DIR$",
}

--- Scans roots for supported documents.
-- @tparam table opts {
--   roots = {...}, is_supported = function(path), exclude_dirs = {patterns}, exclude_files = {patterns},
--   skip_paths = {absolute paths}, should_continue = function(stats) -> false to cancel, previous = inventory }
-- @treturn table inventory { complete=, files = {[path] = {size, mtime, root, title?}}, roots = {[path] = status}, ... }
function CalibreWebIndex.scan(opts)
    local inventory = {
        files = {},
        roots = {},
        unreadable = {},
        complete = true,
        scanned_at = os.time(),
        dirs = 0,
        count = 0,
        skipped_links = 0,
    }
    local previous_files = opts.previous and opts.previous.files or {}
    local exclude_dirs = opts.exclude_dirs or {}
    local exclude_files = opts.exclude_files or {}
    local skip_paths = {}
    for _, path in ipairs(opts.skip_paths or {}) do skip_paths[realpath(path)] = true end
    local symlinkattributes = lfs.symlinkattributes or lfs.attributes

    local function excluded(name, patterns)
        for _, pattern in ipairs(patterns) do
            if name:match(pattern) then return true end
        end
        return false
    end

    for _, root in ipairs(opts.roots) do
        local root_path = root.path
        local attr = lfs.attributes(root_path)
        if not attr or attr.mode ~= "directory" then
            -- Disconnected storage: unknown, *not* empty
            inventory.roots[root_path] = "missing"
            inventory.complete = false
        else
            inventory.roots[root_path] = "ok"
            local visited = {}
            local stack = { root_path }
            while #stack > 0 do
                local dir = table.remove(stack)
                local dir_attr = lfs.attributes(dir)
                local dir_id = dir_attr and (dir_attr.dev .. ":" .. dir_attr.ino)
                if dir_id and not visited[dir_id] and not skip_paths[dir] then
                    visited[dir_id] = true
                    inventory.dirs = inventory.dirs + 1
                    if opts.should_continue and inventory.dirs % 20 == 0
                        and opts.should_continue(inventory) == false then
                        inventory.complete = false
                        inventory.cancelled = true
                        return inventory
                    end
                    local ok, iter, dir_obj = pcall(lfs.dir, dir)
                    if not ok or not iter then
                        inventory.unreadable[dir] = true
                        inventory.roots[root_path] = "partial"
                        inventory.complete = false
                    else
                        for name in iter, dir_obj do
                            if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
                                local path = dir == "/" and ("/" .. name) or (dir .. "/" .. name)
                                local mode = symlinkattributes(path, "mode")
                                if mode == "link" then
                                    -- Following links risks loops and double counting
                                    inventory.skipped_links = inventory.skipped_links + 1
                                elseif mode == "directory" then
                                    if not excluded(name, exclude_dirs) and not excluded(name, default_skip_dirs) then
                                        table.insert(stack, path)
                                    end
                                elseif mode == "file" and not excluded(name, exclude_files) and opts.is_supported(path) then
                                    local file_attr = lfs.attributes(path)
                                    if file_attr then
                                        local entry = {
                                            size = file_attr.size,
                                            mtime = file_attr.modification,
                                            root = root_path,
                                        }
                                        local cached = previous_files[path]
                                        if cached and cached.size == entry.size and cached.mtime == entry.mtime then
                                            -- Unchanged file: keep lazily gathered metadata
                                            entry.title = cached.title
                                            entry.authors = cached.authors
                                            entry.identifiers = cached.identifiers
                                        end
                                        inventory.files[path] = entry
                                        inventory.count = inventory.count + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return inventory
end

-- Search -----------------------------------------------------------------------------------------

local accent_map = {}
do
    local groups = {
        a = "àáâãäåāăą", c = "çćĉċč", d = "ďđ", e = "èéêëēĕėęě", g = "ĝğġģ", h = "ĥħ",
        i = "ìíîïĩīĭįı", j = "ĵ", k = "ķ", l = "ĺļľŀł", n = "ñńņňŉ", o = "òóôõöøōŏő",
        r = "ŕŗř", s = "śŝşšș", t = "ţťŧț", u = "ùúûüũūŭůűų", w = "ŵ", y = "ýÿŷ", z = "źżž",
        ae = "æ", oe = "œ", ss = "ß",
    }
    for plain, accented in pairs(groups) do
        for char in accented:gmatch("[%z\1-\127\194-\244][\128-\191]*") do accent_map[char] = plain end
    end
end

--- Case- and accent-insensitive form of a string, for matching only.
function CalibreWebIndex.foldText(text)
    if type(text) ~= "string" or text == "" then return "" end
    local ok, lowered = pcall(function() return require("ffi/utf8proc").lowercase(text) end)
    text = ok and lowered or text:lower()
    return (text:gsub("[\195-\200][\128-\191]", accent_map))
end

local search_fields = {
    title = "title", t = "title",
    author = "author", authors = "author", a = "author", by = "author",
    year = "year", y = "year",
    format = "format", fmt = "format", f = "format",
    status = "status", is = "status",
}

local status_aliases = {
    both = "both", ["local"] = "local", device = "local", remote = "remote", server = "remote",
    unknown = "unknown", ["?"] = "unknown",
}

--- Parses a search query into terms that must all match.
-- Supports quoted phrases and field prefixes: `author:`, `title:`, `year:` (also `1960-1970`),
-- `format:` and `status:` (both/local/remote/unknown).
function CalibreWebIndex.parseSearch(query)
    local terms = {}
    if type(query) ~= "string" then return terms end
    local pos = 1
    while true do
        local s, e, field, value
        s, e, field, value = query:find('^%s*(%a+):"([^"]*)"?', pos)
        if not s then s, e, value = query:find('^%s*"([^"]*)"?', pos) end
        if not s then s, e, field, value = query:find("^%s*(%a+):(%S+)", pos) end
        if not s then s, e, value = query:find("^%s*(%S+)", pos) end
        if not s then break end
        pos = e + 1
        local known = field and search_fields[field:lower()]
        if field and not known then
            -- Not a field prefix (e.g. "Re:Zero"): search the whole token
            value = field .. ":" .. value
        end
        local term = { field = known }
        if known == "year" then
            local from, to = value:match("^(%d%d%d%d)%-(%d%d%d%d)$")
            term.from = tonumber(from or value:match("^(%d%d%d%d)$"))
            term.to = tonumber(to) or term.from
            if not term.from then term = nil end
        elseif known == "status" then
            term.value = status_aliases[value:lower()]
            if not term.value then term = nil end
        else
            term.value = CalibreWebIndex.foldText(value)
            if term.value == "" then term = nil end
        end
        if term then table.insert(terms, term) end
    end
    return terms
end

local function rowFormats(row)
    local formats = {}
    for format in pairs(row.remote and row.remote.formats or {}) do formats[format:lower()] = true end
    for __, path in ipairs(row.local_paths or {}) do
        local suffix = path:match("%.([^./]+)$")
        if suffix then formats[suffix:lower()] = true end
    end
    return formats
end

--- Whether a presence row matches every parsed search term.
function CalibreWebIndex.matchSearch(row, terms)
    if #terms == 0 then return true end
    local cache = {}
    local function folded(name)
        if cache[name] == nil then
            if name == "title" then
                cache[name] = CalibreWebIndex.foldText(row.title)
            elseif name == "author" then
                cache[name] = CalibreWebIndex.foldText(table.concat(row.authors or {}, " "))
            else
                local parts = { row.title or "", table.concat(row.authors or {}, " ") }
                if row.remote and row.remote.year then table.insert(parts, tostring(row.remote.year)) end
                for format in pairs(rowFormats(row)) do table.insert(parts, format) end
                for __, path in ipairs(row.local_paths or {}) do
                    table.insert(parts, select(2, util.splitFilePathName(path)))
                end
                cache[name] = CalibreWebIndex.foldText(table.concat(parts, " "))
            end
        end
        return cache[name]
    end
    for __, term in ipairs(terms) do
        local ok
        if term.field == "year" then
            local year = row.remote and row.remote.year
            ok = year ~= nil and year >= term.from and year <= term.to
        elseif term.field == "format" then
            ok = rowFormats(row)[term.value] == true
        elseif term.field == "status" then
            ok = row.status == term.value
        else
            ok = folded(term.field or "any"):find(term.value, 1, true) ~= nil
        end
        if not ok then return false end
    end
    return true
end

-- Presence ---------------------------------------------------------------------------------------

--- Normalizes a title for candidate matching (never for automatic linking).
function CalibreWebIndex.normalizeTitle(title)
    if type(title) ~= "string" then return "" end
    title = title:lower():gsub("[%c%p%s]+", "")
    return title
end

--- Best-effort title of a local file without opening it.
function CalibreWebIndex.localTitle(path, entry)
    if entry and entry.title and entry.title ~= "" then return entry.title end
    local _, file_name = util.splitFilePathName(path)
    local stem = util.splitFileNameSuffix(file_name)
    stem = stem:gsub("%s*%(%d+%)$", "")
    -- Calibre-Web names downloads "Title - Author"
    return stem:match("^(.-)%s+%-%s+.+$") or stem
end

local function rootAccessible(path, inventory)
    if inventory then
        for root, status in pairs(inventory.roots or {}) do
            if isUnder(path, root) then return status ~= "missing" and lfs.attributes(root, "mode") == "directory" end
        end
    end
    -- Not under any known root: assume it's reachable if its parent folder is
    local dir = util.splitFilePathName(path)
    return lfs.attributes(dir ~= "" and dir or ".", "mode") == "directory"
end

--- Derives a presence row for every remote book and every local file.
-- @tparam table opts { snapshot=, partial_snapshot=, inventory=, account=, now= }
-- @treturn table rows, table summary
function CalibreWebIndex.derive(opts)
    local now = opts.now or os.time()
    local account = opts.account or { mappings = {}, pending_uploads = {} }
    local snapshot = opts.snapshot
    local inventory = opts.inventory
    local remote_books = {}
    for key, book in pairs(snapshot and snapshot.books or {}) do remote_books[key] = book end
    -- A partial refresh can only add positive evidence
    for key, book in pairs(opts.partial_snapshot and opts.partial_snapshot.books or {}) do remote_books[key] = book end

    local remote_complete = snapshot ~= nil and snapshot.complete == true
    local remote_stale = remote_complete and (now - (snapshot.fetched_at or 0)) > CalibreWebIndex.stale_after
    local remote_can_prove_absence = remote_complete and not remote_stale
    local local_can_prove_absence = inventory ~= nil and inventory.complete == true

    local local_files = {}
    for path, entry in pairs(inventory and inventory.files or {}) do local_files[path] = entry end
    for path, entry in pairs(opts.partial_inventory and opts.partial_inventory.files or {}) do local_files[path] = entry end

    local mapped_paths = {}
    for _, mapping in pairs(account.mappings) do
        for path in pairs(mapping.files) do mapped_paths[path] = true end
    end

    local remote_by_title, local_by_title = {}, {}
    for key, book in pairs(remote_books) do
        if not account.mappings[key] then
            local t = CalibreWebIndex.normalizeTitle(book.title)
            if #t >= 3 then
                remote_by_title[t] = remote_by_title[t] or {}
                table.insert(remote_by_title[t], key)
            end
        end
    end
    for path, entry in pairs(local_files) do
        if not mapped_paths[path] then
            local t = CalibreWebIndex.normalizeTitle(CalibreWebIndex.localTitle(path, entry))
            if #t >= 3 then
                local_by_title[t] = local_by_title[t] or {}
                table.insert(local_by_title[t], path)
            end
        end
    end

    local function status(remote_state, local_state)
        if remote_state == true and local_state == true then return CalibreWebIndex.STATUS_BOTH end
        if remote_state == true and local_state == false then return CalibreWebIndex.STATUS_REMOTE end
        if remote_state == false and local_state == true then return CalibreWebIndex.STATUS_LOCAL end
        return CalibreWebIndex.STATUS_UNKNOWN
    end

    local rows = {}
    local seen_remote = {}

    for key, mapping in pairs(account.mappings) do
        local book = remote_books[key]
        seen_remote[key] = true
        local present, uncertain = {}, false
        for path in pairs(mapping.files) do
            if lfs.attributes(path, "mode") == "file" then
                table.insert(present, path)
            elseif not rootAccessible(path, inventory) then
                -- e.g. SD card removed: we can't tell whether the file still exists
                uncertain = true
            end
        end
        local local_state
        if #present > 0 then local_state = true elseif uncertain then local_state = nil else local_state = false end
        local remote_state
        if book then remote_state = true elseif remote_can_prove_absence then remote_state = false end
        table.sort(present)
        table.insert(rows, {
            key = key,
            remote = book,
            mapping = mapping,
            title = book and book.title or mapping.title,
            authors = book and book.authors or mapping.authors or {},
            local_paths = present,
            status = status(remote_state, local_state),
            stale = remote_stale,
            reason = local_state == nil and "storage_unavailable"
                or (remote_state == nil and "remote_unverified") or nil,
        })
    end

    for key, book in pairs(remote_books) do
        if not seen_remote[key] then
            local candidates = local_by_title[CalibreWebIndex.normalizeTitle(book.title)]
            local local_state
            if candidates then local_state = nil elseif local_can_prove_absence then local_state = false end
            table.insert(rows, {
                key = key,
                remote = book,
                title = book.title,
                authors = book.authors,
                local_paths = {},
                local_candidates = candidates,
                status = status(true, local_state),
                stale = remote_stale,
                reason = candidates and "possible_local_copy" or (local_state == nil and "scan_incomplete") or nil,
            })
        end
    end

    for path, entry in pairs(local_files) do
        local exists = lfs.attributes(path, "mode") == "file"
        local storage_missing = not exists and not rootAccessible(path, inventory)
        if not mapped_paths[path] and (exists or storage_missing) then
            local pending = account.pending_uploads[path]
            local candidates = remote_by_title[CalibreWebIndex.normalizeTitle(CalibreWebIndex.localTitle(path, entry))]
            local remote_state
            if pending or candidates then
                remote_state = nil
            elseif remote_can_prove_absence then
                remote_state = false
            end
            table.insert(rows, {
                key = "local:" .. path,
                title = CalibreWebIndex.localTitle(path, entry),
                authors = entry.authors or {},
                local_paths = exists and { path } or {},
                remote_candidates = candidates,
                pending_upload = pending,
                status = status(remote_state, exists or nil),
                stale = remote_stale,
                reason = (storage_missing and "storage_unavailable")
                    or (pending and ("upload_" .. pending.status))
                    or (candidates and "possible_remote_copy")
                    or (remote_state == nil and "remote_unverified") or nil,
            })
        end
    end

    local summary = { total = #rows, both = 0, ["local"] = 0, remote = 0, unknown = 0 }
    for _, row in ipairs(rows) do summary[row.status] = summary[row.status] + 1 end
    summary.remote_complete = remote_complete
    summary.remote_stale = remote_stale
    summary.local_complete = local_can_prove_absence
    return rows, summary
end

return CalibreWebIndex
