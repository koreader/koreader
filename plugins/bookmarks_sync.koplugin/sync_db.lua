local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local dump = require("dump")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local random = require("random")
local util = require("util")
local Utf8Proc = require("ffi/utf8proc")

local SyncDB = {}

local PENDING_SETTING = "bookmarks_sync_pending"
local CURSOR_SETTING = "bookmarks_sync_log_cursor"
local SHARED_SETTING = "bookmarks_sync_shared_path"
local SYNC_CONFLICT_RE = "%.sync%-conflict%-%d+%-%d+%-%w+"

local function ensureDir(path)
    if not path or path == "" then return false end
    if lfs.attributes(path, "mode") == "directory" then return true end
    return util.makePath(path) and true or false
end

local function pathJoin(...)
    return table.concat({ ... }, "/")
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeAll(path, data)
    local dir = path:match("(.+)/[^/]+$")
    if dir then ensureDir(dir) end
    local f, err = io.open(path, "wb")
    if not f then
        logger.warn("bookmarks_sync: cannot write", path, err)
        return false
    end
    f:write(data or "")
    f:close()
    return true
end

local function listDir(path)
    local items = {}
    if lfs.attributes(path, "mode") ~= "directory" then return items end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            table.insert(items, name)
        end
    end
    table.sort(items)
    return items
end

local function isSyncConflictName(name)
    return type(name) == "string" and name:find(SYNC_CONFLICT_RE) ~= nil
end

local function stripSyncConflict(name)
    if not name then return name end
    return name:gsub(SYNC_CONFLICT_RE, "")
end

function SyncDB.getLocalRoot()
    local root = pathJoin(DataStorage:getFullDataDir(), "bookmarks_sync")
    ensureDir(root)
    return root
end

function SyncDB.getSharedRoot()
    local path = G_reader_settings:readSetting(SHARED_SETTING)
    if path and path ~= "" and lfs.attributes(path, "mode") == "directory" then
        return path
    end
    return nil
end

function SyncDB.setSharedRoot(path)
    if path and path ~= "" then
        G_reader_settings:saveSetting(SHARED_SETTING, path)
    else
        G_reader_settings:delSetting(SHARED_SETTING)
    end
end

function SyncDB.getCursor()
    return tonumber(G_reader_settings:readSetting(CURSOR_SETTING)) or 0
end

function SyncDB.setCursor(n)
    G_reader_settings:saveSetting(CURSOR_SETTING, tonumber(n) or 0)
end

local function loadPending()
    return G_reader_settings:readSetting(PENDING_SETTING) or {}
end

local function savePending(list)
    G_reader_settings:saveSetting(PENDING_SETTING, list)
end

local function queuePending(rel_path)
    if not rel_path then return end
    local pending = loadPending()
    for _, p in ipairs(pending) do
        if p == rel_path then return end
    end
    table.insert(pending, rel_path)
    savePending(pending)
end

function SyncDB.getBaseName(filepath)
    if not filepath then return "" end
    local _, filename = util.splitFilePathName(filepath)
    if not filename then return "" end
    return util.trim(filename:gsub("%.[^%.]+$", ""))
end

function SyncDB.normalizeName(name)
    if not name or name == "" then return "" end
    local s = Utf8Proc.lowercase(name)
    s = s:gsub("ё", "е")
    s = s:gsub("%s*%(%d+%)%s*$", "")
    s = s:gsub("%s+", " ")
    s = util.trim(s)
    -- Safe directory component
    s = s:gsub("[/\\%z]", "_")
    return s
end

function SyncDB.safeMarkId(mark_id)
    if not mark_id then return nil end
    return tostring(mark_id):gsub(":", "-"):gsub("%s+", "_")
end

function SyncDB.readLua(path)
    if not path or lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok, data = pcall(dofile, path)
    if ok and type(data) == "table" then return data end
    return nil
end

function SyncDB.writeLua(path, data)
    if not path or type(data) ~= "table" then return false end
    local dir = path:match("(.+)/[^/]+$")
    if dir then ensureDir(dir) end
    return util.writeToFile(dump(data, nil, true), path, true, true, true) and true or false
end

function SyncDB.touchLink(path)
    if lfs.attributes(path, "mode") == "file" then return true end
    return writeAll(path, "")
end

local function bookDir(root, book_id)
    return pathJoin(root, "book", book_id)
end

function SyncDB.markPath(root, book_id, mark_id)
    return pathJoin(bookDir(root, book_id), "mark", SyncDB.safeMarkId(mark_id) .. ".lua")
end

function SyncDB.goneDir(root, book_id)
    return pathJoin(bookDir(root, book_id), "gone")
end

function SyncDB.backDir(root, book_id)
    return pathJoin(bookDir(root, book_id), "back")
end

function SyncDB.seenDir(root, book_id, device_id)
    return pathJoin(bookDir(root, book_id), "seen", device_id)
end

function SyncDB.redirectPath(root, book_id)
    return pathJoin(bookDir(root, book_id), "redirect")
end

function SyncDB.mergeLoc(dst, src)
    dst = dst or {}
    if type(src) ~= "table" then return dst end
    for fp, loc in pairs(src) do
        if type(loc) == "table" and not dst[fp] then
            dst[fp] = loc
        elseif type(loc) == "table" and type(dst[fp]) == "table" then
            -- Prefer existing local coordinates; only fill missing keys.
            for k, v in pairs(loc) do
                if dst[fp][k] == nil then
                    dst[fp][k] = v
                end
            end
        end
    end
    return dst
end

function SyncDB.fieldsDiffer(a, b, keys)
    if not a or not b then return a ~= b end
    for _, key in ipairs(keys) do
        local va, vb = a[key], b[key]
        if (va or "") ~= (vb or "") then
            return true
        end
    end
    return false
end

local CONTENT_KEYS = { "exact", "prefix", "suffix", "notes", "note", "color", "drawer", "progress" }

function SyncDB.mergeMarkData(local_data, remote_data)
    local_data = local_data or {}
    remote_data = remote_data or {}
    local merged = {}
    for k, v in pairs(local_data) do
        merged[k] = v
    end
    merged.loc = SyncDB.mergeLoc(local_data.loc and util.tableDeepCopy(local_data.loc) or {}, remote_data.loc)
    local conflict = SyncDB.fieldsDiffer(local_data, remote_data, CONTENT_KEYS)
    return merged, conflict, local_data, remote_data
end

--- Parse journal filename: "<num>" or "<num>-<device_id>"
function SyncDB.parseLogName(name)
    if not name or isSyncConflictName(name) then
        local base = stripSyncConflict(name or "")
        if base == "" then return nil end
        name = base
    end
    local num, device = name:match("^(%d+)%-(.+)$")
    if num then
        return tonumber(num), device, name
    end
    num = name:match("^(%d+)$")
    if num then
        return tonumber(num), nil, name
    end
    return nil
end

function SyncDB.listLogEntries(root)
    local log_dir = pathJoin(root, "log")
    local entries = {}
    for _, name in ipairs(listDir(log_dir)) do
        local path = pathJoin(log_dir, name)
        if lfs.attributes(path, "mode") == "file" then
            local num, device, key = SyncDB.parseLogName(name)
            if num then
                table.insert(entries, {
                    num = num,
                    device = device,
                    name = name,
                    key = key,
                    path = path,
                    is_conflict = isSyncConflictName(name),
                    rel = "log/" .. name,
                })
            end
        end
    end
    table.sort(entries, function(a, b)
        if a.num ~= b.num then return a.num < b.num end
        return (a.device or "") < (b.device or "")
    end)
    return entries
end

function SyncDB.getMaxJournalNumber(root)
    local max_n = 0
    for _, entry in ipairs(SyncDB.listLogEntries(root)) do
        if entry.num > max_n then max_n = entry.num end
    end
    return max_n
end

function SyncDB.readLogEntry(path)
    local data = readAll(path)
    if not data then return nil end
    return util.trim(data)
end

local function nextJournalNumber(root)
    return SyncDB.getMaxJournalNumber(root) + 1
end

--- Append a journal record and optionally create the file named by rel_path.
-- @return journal_number
function SyncDB.appendJournal(root, rel_path, device_id)
    local num = nextJournalNumber(root)
    local log_name = tostring(num)
    -- If the plain number already exists (race after pull), disambiguate.
    if lfs.attributes(pathJoin(root, "log", log_name), "mode") == "file" then
        log_name = num .. "-" .. (device_id or "device")
    end
    local log_rel = "log/" .. log_name
    local log_path = pathJoin(root, log_rel)
    ensureDir(pathJoin(root, "log"))
    writeAll(log_path, rel_path or "")
    return num, log_rel
end

local function createLink(root, rel_dir, name, device_id, journalize)
    local rel = pathJoin(rel_dir, name)
    local full = pathJoin(root, rel)
    if lfs.attributes(full, "mode") == "file" then
        return false, nil
    end
    ensureDir(pathJoin(root, rel_dir))
    SyncDB.touchLink(full)
    local num
    if journalize ~= false then
        local log_rel
        num, log_rel = SyncDB.appendJournal(root, rel, device_id)
        queuePending(rel)
        queuePending(log_rel)
    end
    return true, num
end

function SyncDB.resolveRedirect(root, book_id, seen)
    seen = seen or {}
    if not book_id or seen[book_id] then return book_id end
    seen[book_id] = true
    local redirect = readAll(SyncDB.redirectPath(root, book_id))
    if redirect and redirect ~= "" then
        redirect = util.trim(redirect)
        if redirect ~= "" and redirect ~= book_id then
            return SyncDB.resolveRedirect(root, redirect, seen)
        end
    end
    return book_id
end

function SyncDB.setRedirect(root, from_id, to_id, device_id)
    if not from_id or not to_id or from_id == to_id then return end
    local path = SyncDB.redirectPath(root, from_id)
    if lfs.attributes(path, "mode") == "file" then return end
    writeAll(path, to_id)
    local rel = "book/" .. from_id .. "/redirect"
    local num, log_rel = SyncDB.appendJournal(root, rel, device_id)
    queuePending(rel)
    queuePending(log_rel)
end

local function bookIdsForName(root, norm_name)
    local dir = pathJoin(root, "by-name", norm_name)
    local ids = {}
    for _, name in ipairs(listDir(dir)) do
        if not isSyncConflictName(name) and lfs.attributes(pathJoin(dir, name), "mode") == "file" then
            table.insert(ids, name)
        end
    end
    return ids
end

local function bookIdForFp(root, fp)
    local dir = pathJoin(root, "by-fp", fp)
    for _, name in ipairs(listDir(dir)) do
        if not isSyncConflictName(name) and lfs.attributes(pathJoin(dir, name), "mode") == "file" then
            return SyncDB.resolveRedirect(root, name)
        end
    end
    return nil
end

--- Smaller journal number among by-name links wins.
local function canonicalByJournal(root, norm_name, ids)
    local best_id, best_num
    local log_entries = SyncDB.listLogEntries(root)
    local link_num = {}
    for _, entry in ipairs(log_entries) do
        local rel = SyncDB.readLogEntry(entry.path)
        if rel then
            local id = rel:match("^by%-name/" .. norm_name:gsub("(%W)", "%%%1") .. "/(.+)$")
            if id and not link_num[id] then
                link_num[id] = entry.num
            end
        end
    end
    for _, id in ipairs(ids) do
        local n = link_num[id] or math.huge
        if not best_num or n < best_num or (n == best_num and id < best_id) then
            best_num = n
            best_id = id
        end
    end
    return best_id or ids[1]
end

function SyncDB.relatedBookIds(root, book_id)
    book_id = SyncDB.resolveRedirect(root, book_id)
    local ids = { book_id }
    local seen = { [book_id] = true }
    -- Collect ids that redirect to this canonical id.
    local book_root = pathJoin(root, "book")
    for _, id in ipairs(listDir(book_root)) do
        if not seen[id] then
            local target = SyncDB.resolveRedirect(root, id)
            if target == book_id then
                table.insert(ids, id)
                seen[id] = true
            end
        end
    end
    return ids
end

--- Resolve or create book_id for an open document.
-- @return book_id, partial_md5, format, is_new_fingerprint
function SyncDB.resolveBook(doc_path, device_id, root)
    root = root or SyncDB.getLocalRoot()
    local fp = util.partialMD5(doc_path)
    if not fp then
        logger.warn("bookmarks_sync: partialMD5 failed for", doc_path)
        return nil
    end
    local format = (doc_path:match("%.([^.]+)$") or ""):lower()
    local base = SyncDB.getBaseName(doc_path)
    local norm = SyncDB.normalizeName(base)

    local existing = bookIdForFp(root, fp)
    if existing then
        return existing, fp, format, false
    end

    local ids = norm ~= "" and bookIdsForName(root, norm) or {}
    local book_id
    local is_new_fp = true
    if #ids == 0 then
        book_id = random.uuid()
    elseif #ids == 1 then
        book_id = SyncDB.resolveRedirect(root, ids[1])
    else
        book_id = SyncDB.resolveRedirect(root, canonicalByJournal(root, norm, ids))
        for _, id in ipairs(ids) do
            local resolved = SyncDB.resolveRedirect(root, id)
            if resolved ~= book_id then
                SyncDB.setRedirect(root, id, book_id, device_id)
            end
        end
    end

    createLink(root, "by-fp/" .. fp, book_id, device_id, true)
    if norm ~= "" then
        createLink(root, "by-name/" .. norm, book_id, device_id, true)
    end
    ensureDir(pathJoin(bookDir(root, book_id), "mark"))
    return book_id, fp, format, is_new_fp
end

function SyncDB.readMark(root, book_id, mark_id)
    return SyncDB.readLua(SyncDB.markPath(root, book_id, mark_id))
end

local function marksEqual(a, b)
    if not a or not b then return a == b end
    if SyncDB.fieldsDiffer(a, b, CONTENT_KEYS) then return false end
    if (a.datetime or "") ~= (b.datetime or "") then return false end
    local la, lb = a.loc or {}, b.loc or {}
    local keys = {}
    for k in pairs(la) do keys[k] = true end
    for k in pairs(lb) do keys[k] = true end
    for k in pairs(keys) do
        local xa, xb = la[k], lb[k]
        if type(xa) ~= "table" or type(xb) ~= "table" then
            if xa ~= xb then return false end
        else
            for _, field in ipairs({ "format", "pos0", "pos1", "page", "pageno" }) do
                if tostring(xa[field] or "") ~= tostring(xb[field] or "") then
                    return false
                end
            end
        end
    end
    return true
end

function SyncDB.writeMark(root, book_id, mark_data, device_id, journalize)
    if not mark_data or not mark_data.datetime then return false end
    book_id = SyncDB.resolveRedirect(root, book_id)
    local path = SyncDB.markPath(root, book_id, mark_data.datetime)
    local existing = SyncDB.readLua(path)
    local to_write = util.tableDeepCopy(mark_data)
    if existing then
        to_write.loc = SyncDB.mergeLoc(existing.loc and util.tableDeepCopy(existing.loc) or {}, mark_data.loc)
    end
    if marksEqual(existing, to_write) then
        return true
    end
    if not SyncDB.writeLua(path, to_write) then return false end
    local rel = "book/" .. book_id .. "/mark/" .. SyncDB.safeMarkId(mark_data.datetime) .. ".lua"
    if journalize ~= false then
        local num, log_rel = SyncDB.appendJournal(root, rel, device_id)
        queuePending(rel)
        queuePending(log_rel)
    else
        queuePending(rel)
    end
    return true
end

--- Upsert mark content from local annotation export.
function SyncDB.upsertMarkFromAnnotation(root, book_id, mark_data, device_id)
    book_id = SyncDB.resolveRedirect(root, book_id)
    local path = SyncDB.markPath(root, book_id, mark_data.datetime)
    local existing = SyncDB.readLua(path) or {}
    local out = util.tableDeepCopy(existing)
    for _, key in ipairs(CONTENT_KEYS) do
        if mark_data[key] ~= nil then
            out[key] = mark_data[key]
        end
    end
    out.datetime = mark_data.datetime
    out.loc = SyncDB.mergeLoc(existing.loc or {}, mark_data.loc)
    return SyncDB.writeMark(root, book_id, out, device_id, true)
end

local function parseStampName(name, mark_id)
    -- <safe_mark_id>--<number>
    local safe = SyncDB.safeMarkId(mark_id)
    if not safe then return nil end
    local pattern = "^" .. safe:gsub("(%W)", "%%%1") .. "%-%-(%d+)$"
    local num = name:match(pattern)
    return tonumber(num)
end

function SyncDB.latestGoneNumber(root, book_id, mark_id)
    local max_n = 0
    for _, id in ipairs(SyncDB.relatedBookIds(root, book_id)) do
        for _, name in ipairs(listDir(SyncDB.goneDir(root, id))) do
            if not isSyncConflictName(name) then
                local n = parseStampName(name, mark_id)
                if n and n > max_n then max_n = n end
            end
        end
    end
    return max_n
end

function SyncDB.latestBackNumber(root, book_id, mark_id)
    local max_n = 0
    for _, id in ipairs(SyncDB.relatedBookIds(root, book_id)) do
        for _, name in ipairs(listDir(SyncDB.backDir(root, id))) do
            if not isSyncConflictName(name) then
                local n = parseStampName(name, mark_id)
                if n and n > max_n then max_n = n end
            end
        end
    end
    return max_n
end

function SyncDB.isMarkGone(root, book_id, mark_id)
    local gone = SyncDB.latestGoneNumber(root, book_id, mark_id)
    local back = SyncDB.latestBackNumber(root, book_id, mark_id)
    if gone == 0 and back == 0 then return false end
    if gone == back then return nil end -- ambiguous, needs user choice
    return gone > back
end

function SyncDB.markGone(root, book_id, mark_id, device_id)
    book_id = SyncDB.resolveRedirect(root, book_id)
    local num = nextJournalNumber(root)
    local name = SyncDB.safeMarkId(mark_id) .. "--" .. tostring(num)
    local rel = "book/" .. book_id .. "/gone/" .. name
    SyncDB.touchLink(pathJoin(root, rel))
    local _, log_rel = SyncDB.appendJournal(root, rel, device_id)
    queuePending(rel)
    queuePending(log_rel)
    return num
end

function SyncDB.markBack(root, book_id, mark_id, device_id)
    book_id = SyncDB.resolveRedirect(root, book_id)
    local num = nextJournalNumber(root)
    local name = SyncDB.safeMarkId(mark_id) .. "--" .. tostring(num)
    local rel = "book/" .. book_id .. "/back/" .. name
    SyncDB.touchLink(pathJoin(root, rel))
    local _, log_rel = SyncDB.appendJournal(root, rel, device_id)
    queuePending(rel)
    queuePending(log_rel)
    return num
end

function SyncDB.latestSeenNumber(root, book_id, mark_id, device_id, partial_md5)
    local max_n = 0
    local safe = SyncDB.safeMarkId(mark_id)
    local suffix = "--" .. partial_md5 .. "--"
    for _, id in ipairs(SyncDB.relatedBookIds(root, book_id)) do
        for _, name in ipairs(listDir(SyncDB.seenDir(root, id, device_id))) do
            if not isSyncConflictName(name) and name:sub(1, #safe) == safe and name:find(suffix, 1, true) then
                local n = tonumber(name:match("%-%-(%d+)$"))
                if n and n > max_n then max_n = n end
            end
        end
    end
    return max_n
end

function SyncDB.isSeen(root, book_id, mark_id, device_id, partial_md5)
    return SyncDB.latestSeenNumber(root, book_id, mark_id, device_id, partial_md5) > 0
end

function SyncDB.needsReanchor(root, book_id, mark_id, device_id, partial_md5)
    local seen = SyncDB.latestSeenNumber(root, book_id, mark_id, device_id, partial_md5)
    local back = SyncDB.latestBackNumber(root, book_id, mark_id)
    if SyncDB.isMarkGone(root, book_id, mark_id) then return false end
    if seen == 0 then return true end
    return back > seen
end

function SyncDB.markSeen(root, book_id, mark_id, device_id, partial_md5)
    book_id = SyncDB.resolveRedirect(root, book_id)
    local num = nextJournalNumber(root)
    local name = SyncDB.safeMarkId(mark_id) .. "--" .. partial_md5 .. "--" .. tostring(num)
    local rel = "book/" .. book_id .. "/seen/" .. device_id .. "/" .. name
    SyncDB.touchLink(pathJoin(root, rel))
    local _, log_rel = SyncDB.appendJournal(root, rel, device_id)
    queuePending(rel)
    queuePending(log_rel)
    return num
end

function SyncDB.listMarks(root, book_id)
    local marks = {}
    local by_id = {}
    for _, id in ipairs(SyncDB.relatedBookIds(root, book_id)) do
        local mark_dir = pathJoin(bookDir(root, id), "mark")
        for _, name in ipairs(listDir(mark_dir)) do
            if name:sub(-4) == ".lua" and not isSyncConflictName(name) then
                local data = SyncDB.readLua(pathJoin(mark_dir, name))
                if data and data.datetime and not by_id[data.datetime] then
                    by_id[data.datetime] = data
                    table.insert(marks, data)
                end
            end
        end
    end
    return marks
end

function SyncDB.listGoneMarks(root, book_id)
    local result = {}
    for _, mark in ipairs(SyncDB.listMarks(root, book_id)) do
        if SyncDB.isMarkGone(root, book_id, mark.datetime) then
            table.insert(result, mark)
        end
    end
    return result
end

function SyncDB.findConflictCopies(root, rel_path)
    local dir, base = rel_path:match("(.+)/([^/]+)$")
    if not dir then
        dir, base = "", rel_path
    end
    local full_dir = dir == "" and root or pathJoin(root, dir)
    local copies = {}
    for _, name in ipairs(listDir(full_dir)) do
        if isSyncConflictName(name) and stripSyncConflict(name) == base then
            table.insert(copies, pathJoin(full_dir, name))
        end
    end
    return copies
end

local function samePath(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local ok_a, ra = pcall(function() return ffiUtil.realpath(a) end)
    local ok_b, rb = pcall(function() return ffiUtil.realpath(b) end)
    if ok_a and ok_b and ra and rb then
        return ra == rb
    end
    return false
end

local function copyFile(src, dst)
    ensureDir(dst:match("(.+)/[^/]+$"))
    local ok, err = pcall(function()
        return ffiUtil.copyFile(src, dst)
    end)
    if ok and err == nil then return true end
    -- Fallback: byte copy
    local data = readAll(src)
    if not data then return false end
    return writeAll(dst, data)
end

local function applyImmutableFile(local_root, shared_root, rel)
    local src = pathJoin(shared_root, rel)
    local dst = pathJoin(local_root, rel)
    if lfs.attributes(src, "mode") ~= "file" then return end
    if lfs.attributes(dst, "mode") == "file" then return end
    copyFile(src, dst)
end

local function applyMarkFile(local_root, shared_root, rel, conflicts)
    local src = pathJoin(shared_root, rel)
    local dst = pathJoin(local_root, rel)
    if lfs.attributes(src, "mode") ~= "file" then return end
    local remote = SyncDB.readLua(src)
    if not remote then return end
    local conflict_files = SyncDB.findConflictCopies(shared_root, rel)
    for _, cpath in ipairs(conflict_files) do
        local cdata = SyncDB.readLua(cpath)
        if cdata then
            remote.loc = SyncDB.mergeLoc(remote.loc or {}, cdata.loc)
            if SyncDB.fieldsDiffer(remote, cdata, CONTENT_KEYS) then
                table.insert(conflicts, {
                    kind = "mark",
                    rel = rel,
                    local_data = remote,
                    remote_data = cdata,
                    conflict_path = cpath,
                })
            end
        end
    end
    if lfs.attributes(dst, "mode") ~= "file" then
        SyncDB.writeLua(dst, remote)
        return
    end
    local local_data = SyncDB.readLua(dst) or {}
    local merged, conflict, a, b = SyncDB.mergeMarkData(local_data, remote)
    if conflict then
        table.insert(conflicts, {
            kind = "mark",
            rel = rel,
            local_data = a,
            remote_data = b,
        })
        -- Keep previous local content, only merge locs for now.
        local keep = util.tableDeepCopy(local_data)
        keep.loc = merged.loc
        SyncDB.writeLua(dst, keep)
    else
        SyncDB.writeLua(dst, merged)
    end
end

--- Pull shared journal entries into local store.
-- conflict_cb(conflict) -> "local"|"remote"|nil  (nil keeps previous / skips advancing for that item)
function SyncDB.pullShared(device_id, conflict_cb)
    local local_root = SyncDB.getLocalRoot()
    local shared_root = SyncDB.getSharedRoot()
    if not shared_root then
        return false, "no_shared"
    end
    if samePath(local_root, shared_root) then
        -- Shared folder is the local store itself; only resolve conflict copies.
        for _, id in ipairs(listDir(pathJoin(local_root, "book"))) do
            local mark_dir = pathJoin(local_root, "book", id, "mark")
            for _, name in ipairs(listDir(mark_dir)) do
                if name:sub(-4) == ".lua" and not isSyncConflictName(name) then
                    local rel = "book/" .. id .. "/mark/" .. name
                    for _, cpath in ipairs(SyncDB.findConflictCopies(local_root, rel)) do
                        local main = SyncDB.readLua(pathJoin(local_root, rel))
                        local other = SyncDB.readLua(cpath)
                        if main and other then
                            local merged_loc = SyncDB.mergeLoc(
                                main.loc and util.tableDeepCopy(main.loc) or {},
                                other.loc
                            )
                            if SyncDB.fieldsDiffer(main, other, CONTENT_KEYS) then
                                local choice = conflict_cb and conflict_cb({
                                    kind = "mark",
                                    rel = rel,
                                    local_data = main,
                                    remote_data = other,
                                    conflict_path = cpath,
                                })
                                local chosen = choice == "remote" and other or main
                                chosen.loc = merged_loc
                                SyncDB.writeLua(pathJoin(local_root, rel), chosen)
                                if choice then
                                    os.remove(cpath)
                                    local _, log_rel = SyncDB.appendJournal(local_root, rel, device_id)
                                    queuePending(rel)
                                    queuePending(log_rel)
                                end
                            else
                                main.loc = merged_loc
                                SyncDB.writeLua(pathJoin(local_root, rel), main)
                                os.remove(cpath)
                            end
                        end
                    end
                end
            end
        end
        -- Drop conflict copies of immutable/log files after reading both.
        for _, entry in ipairs(SyncDB.listLogEntries(local_root)) do
            if entry.is_conflict then
                os.remove(entry.path)
            end
        end
        SyncDB.setCursor(SyncDB.getMaxJournalNumber(local_root))
        return true, "same_root"
    end

    local cursor = SyncDB.getCursor()
    local conflicts = {}
    local max_applied = cursor
    for _, entry in ipairs(SyncDB.listLogEntries(shared_root)) do
        if entry.num > cursor then
            local rel = SyncDB.readLogEntry(entry.path)
            if rel and rel ~= "" then
                if rel:match("^book/.+/mark/.+%.lua$") then
                    applyMarkFile(local_root, shared_root, rel, conflicts)
                else
                    applyImmutableFile(local_root, shared_root, rel)
                end
            end
            -- Always ingest conflict-siblings of log entries without asking.
            if entry.is_conflict then
                -- already parsed via listLogEntries; remove after apply
            end
            if entry.num > max_applied then max_applied = entry.num end
        end
    end

    for _, conflict in ipairs(conflicts) do
        local choice = conflict_cb and conflict_cb(conflict) or nil
        if choice == "local" or choice == "remote" then
            local chosen = choice == "local" and conflict.local_data or conflict.remote_data
            chosen.loc = SyncDB.mergeLoc(
                (conflict.local_data and conflict.local_data.loc) or {},
                (conflict.remote_data and conflict.remote_data.loc) or {}
            )
            SyncDB.writeLua(pathJoin(local_root, conflict.rel), chosen)
            if conflict.conflict_path then
                os.remove(conflict.conflict_path)
            end
            -- Mirror resolution into shared after choice.
            SyncDB.writeLua(pathJoin(shared_root, conflict.rel), chosen)
            if conflict.conflict_path then
                local shared_conflict = conflict.conflict_path:gsub(
                    "^" .. local_root:gsub("(%W)", "%%%1"),
                    shared_root
                )
                -- conflict_path may already be under shared_root
                if lfs.attributes(conflict.conflict_path, "mode") == "file" then
                    os.remove(conflict.conflict_path)
                end
            end
            local num = SyncDB.appendJournal(shared_root, conflict.rel, device_id)
            SyncDB.appendJournal(local_root, conflict.rel, device_id)
            if num > max_applied then max_applied = num end
        end
    end

    -- Remove shared log conflict copies after both were read.
    for _, entry in ipairs(SyncDB.listLogEntries(shared_root)) do
        if entry.is_conflict and entry.num > cursor then
            os.remove(entry.path)
        end
    end

    SyncDB.setCursor(max_applied)
    return true, max_applied
end

--- Push pending local paths into the shared folder with new journal numbers.
function SyncDB.pushShared(device_id)
    local local_root = SyncDB.getLocalRoot()
    local shared_root = SyncDB.getSharedRoot()
    if not shared_root then
        return false, "no_shared"
    end
    if samePath(local_root, shared_root) then
        savePending({})
        SyncDB.setCursor(SyncDB.getMaxJournalNumber(local_root))
        return true, "same_root"
    end

    local pending = loadPending()
    local remain = {}
    for _, rel in ipairs(pending) do
        if rel:match("^log/") then
            -- Local-only journal crumbs; shared gets its own numbers below.
        else
            local src = pathJoin(local_root, rel)
            if lfs.attributes(src, "mode") == "file" then
                local dst = pathJoin(shared_root, rel)
                if rel:match("^book/.+/mark/.+%.lua$") and lfs.attributes(dst, "mode") == "file" then
                    local local_data = SyncDB.readLua(src)
                    local remote = SyncDB.readLua(dst)
                    local merged = local_data
                    if local_data and remote then
                        merged = util.tableDeepCopy(local_data)
                        merged.loc = SyncDB.mergeLoc(remote.loc or {}, local_data.loc)
                    end
                    SyncDB.writeLua(dst, merged or local_data)
                elseif lfs.attributes(dst, "mode") ~= "file" then
                    copyFile(src, dst)
                end
                local num = SyncDB.appendJournal(shared_root, rel, device_id)
                if num > SyncDB.getCursor() then
                    SyncDB.setCursor(num)
                end
            else
                table.insert(remain, rel)
            end
        end
    end
    savePending(remain)
    return true, #pending - #remain
end

function SyncDB.syncShared(device_id, conflict_cb)
    local ok, err = SyncDB.pullShared(device_id, conflict_cb)
    if not ok then return false, err end
    return SyncDB.pushShared(device_id)
end

--- One-time migration from sidecar bookmarks_sync.lua
function SyncDB.migrateSidecar(doc_path, device_id)
    local sdr = DocSettings:getSidecarDir(doc_path)
    if not sdr then return false end
    local sidecar = sdr .. "/bookmarks_sync.lua"
    if lfs.attributes(sidecar, "mode") ~= "file" then return false end
    local migrated_flag = sdr .. "/bookmarks_sync.migrated"
    if lfs.attributes(migrated_flag, "mode") == "file" then return false end

    local settings = require("luasettings"):open(sidecar)
    local bookmarks = settings:readSetting("bookmarks") or {}
    local root = SyncDB.getLocalRoot()
    local book_id, fp, format = SyncDB.resolveBook(doc_path, device_id, root)
    if not book_id then return false end

    for _, bm in ipairs(bookmarks) do
        if bm.datetime then
            local mark = {
                datetime = bm.datetime,
                exact = bm.exact,
                prefix = bm.prefix,
                suffix = bm.suffix,
                notes = bm.notes or bm.note,
                color = bm.color,
                drawer = bm.drawer,
                progress = bm.progress,
                loc = {},
            }
            SyncDB.upsertMarkFromAnnotation(root, book_id, mark, device_id)
            if bm.deleted then
                SyncDB.markGone(root, book_id, bm.datetime, device_id)
            end
            if bm.synced_to and bm.synced_to[device_id] then
                for fmt, done in pairs(bm.synced_to[device_id]) do
                    if done and fmt == format then
                        SyncDB.markSeen(root, book_id, bm.datetime, device_id, fp)
                    end
                end
            end
        end
    end
    writeAll(migrated_flag, "1")
    logger.info("bookmarks_sync: migrated sidecar for", doc_path)
    return true
end

-- Keep old API stubs used during transition
function SyncDB.getSyncFilePath(doc_path)
    local sdr_dir = DocSettings:getSidecarDir(doc_path)
    if not sdr_dir then return nil end
    return sdr_dir .. "/bookmarks_sync.lua"
end

function SyncDB.loadBookSync(doc_path)
    local filepath = SyncDB.getSyncFilePath(doc_path)
    if not filepath or lfs.attributes(filepath, "mode") ~= "file" then
        return nil
    end
    local settings = require("luasettings"):open(filepath)
    return {
        book_id = settings:readSetting("book_id"),
        current_basename = settings:readSetting("current_basename"),
        basenames_history = settings:readSetting("basenames_history") or {},
        bookmarks = settings:readSetting("bookmarks") or {},
    }
end

return SyncDB
