--[[--
Fetches OPDS cover images in a background subprocess, and caches them on disk.

A zero-length cache file marks a cover that will never be available.
--]]

local DataStorage = require("datastorage")
local RenderImage = require("ui/renderimage")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local mime = require("mime")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")

local MAX_COVER_SIZE = 4 * 1024 * 1024
local CACHE_MAX_AGE = 30 * 24 * 60 * 60
local CHECK_INTERVAL = 1

local OPDSCoverLoader = {
    cache_dir = DataStorage:getDataDir() .. "/cache/opdscovers/",
    subprocesses_pids = {},
    subprocesses_collector = nil,
}

function OPDSCoverLoader:_ensureCacheDir()
    if self.cache_dir_ready then return true end
    if lfs.attributes(self.cache_dir, "mode") == "directory" or util.makePath(self.cache_dir) then
        self.cache_dir_ready = true
        return true
    end
    logger.warn("OPDSCoverLoader: could not create cache directory", self.cache_dir)
    return false
end

function OPDSCoverLoader:getCachePath(cover_url)
    return self.cache_dir .. md5(cover_url)
end

local DEFAULT_PORTS = { http = "80", https = "443" }

local function getOrigin(some_url)
    local parsed = some_url and url.parse(some_url)
    if not parsed or not parsed.scheme or not parsed.host then
        return nil
    end
    local scheme = parsed.scheme:lower()
    return scheme .. "://" .. parsed.host:lower() .. ":" .. (parsed.port or DEFAULT_PORTS[scheme] or "")
end

local function isDataUri(cover_url)
    return cover_url:sub(1, 5) == "data:"
end

local function decodeDataUri(uri)
    local meta, payload = uri:match("^data:([^,]*),(.*)$")
    if not payload or payload == "" then
        return nil
    end
    if not meta:lower():find("base64", 1, true) then
        return nil
    end
    -- Parentheses needed: gsub's count would switch unb64 to chunked mode
    local data = mime.unb64((payload:gsub("%s", "")))
    if not data or data == "" then
        return nil
    end
    return data
end

local function scaleToFit(bb, max_w, max_h)
    local w, h = bb:getWidth(), bb:getHeight()
    if w == 0 or h == 0 then
        bb:free()
        return false
    end
    local scale_factor = math.min(max_w / w, max_h / h)
    if scale_factor < 1 then
        bb = RenderImage:scaleBlitBuffer(bb, math.floor(w * scale_factor + 0.5),
            math.floor(h * scale_factor + 0.5), true)
    end
    return bb
end

-- Returns nil if the cover has not been fetched yet, false if it is unavailable.
function OPDSCoverLoader:getCoverBB(cover_url, max_w, max_h)
    if isDataUri(cover_url) then
        local data = decodeDataUri(cover_url)
        if not data then
            logger.dbg("OPDSCoverLoader: could not decode data: URI")
            return false
        end
        local bb = RenderImage:renderImageData(data, #data, false)
        return bb and scaleToFit(bb, max_w, max_h) or false
    end

    local path = self:getCachePath(cover_url)
    local attr = lfs.attributes(path)
    if not attr then
        return nil
    end
    if attr.size == 0 then
        return false
    end

    local bb = RenderImage:renderImageFile(path, false)
    if not bb then
        logger.dbg("OPDSCoverLoader: could not decode cached cover", cover_url)
        -- Mark it as unavailable, so we don't decode it again
        util.removeFile(path)
        local f = io.open(path, "w")
        if f then f:close() end
        return false
    end
    return scaleToFit(bb, max_w, max_h)
end

function OPDSCoverLoader:isPending(cover_url)
    if isDataUri(cover_url) then
        return false
    end
    return lfs.attributes(self:getCachePath(cover_url)) == nil
end

function OPDSCoverLoader:isFetching()
    return #self.subprocesses_pids > 0
end

-- Runs in the subprocess. On failure, also returns whether it is a permanent one.
function OPDSCoverLoader:_fetchCover(cover_url, username, password)
    local path = self:getCachePath(cover_url)
    local tmp_path = path .. ".tmp"
    local parsed = url.parse(cover_url)
    if not parsed or (parsed.scheme ~= "http" and parsed.scheme ~= "https") then
        logger.dbg("OPDSCoverLoader: unsupported protocol for", cover_url)
        return false, true
    end

    local sink = {}
    local bytes = 0
    local too_large = false
    local limited_sink = function(chunk, err)
        if chunk then
            bytes = bytes + #chunk
            if bytes > MAX_COVER_SIZE then
                too_large = true
                return nil, "cover too large"
            end
            table.insert(sink, chunk)
        end
        return 1, err
    end

    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code = socket.skip(1, http.request {
        url      = cover_url,
        headers  = {
            ["Accept-Encoding"] = "identity",
        },
        sink     = limited_sink,
        user     = username,
        password = password,
    })
    socketutil:reset_timeout()

    if code == 200 and bytes > 0 and not too_large then
        local file = io.open(tmp_path, "wb")
        if not file then return false, false end
        file:write(table.concat(sink))
        file:close()
        -- Rename only once fully written, so the parent never sees a partial file.
        return os.rename(tmp_path, path) and true or false, false
    end

    logger.dbg("OPDSCoverLoader: failed to fetch", cover_url, code)
    -- Anything else (no network, timeout, 401, 5xx…) may work on a later attempt.
    local permanent = too_large or code == 404 or code == 410 or (code == 200 and bytes == 0)
    return false, permanent
end

-- Credentials are only sent to covers served from the same origin as catalog_url.
function OPDSCoverLoader:fetchInBackground(covers, username, password, catalog_url)
    if not self:_ensureCacheDir() then
        return false
    end
    local wanted = {}
    for _, cover_url in ipairs(covers) do
        if self:isPending(cover_url) then
            table.insert(wanted, cover_url)
        end
    end
    if #wanted == 0 then
        return false
    end
    self:stop()

    local catalog_origin = getOrigin(catalog_url)
    local task = function()
        for _, cover_url in ipairs(wanted) do
            local ok, permanent
            if catalog_origin and getOrigin(cover_url) == catalog_origin then
                ok, permanent = self:_fetchCover(cover_url, username, password)
            else
                ok, permanent = self:_fetchCover(cover_url)
            end
            if not ok and permanent then
                local file = io.open(self:getCachePath(cover_url), "w")
                if file then file:close() end
            end
        end
    end

    local pid = ffiUtil.runInSubProcess(task)
    if not pid then
        logger.warn("OPDSCoverLoader: failed to fork cover download subprocess")
        return false
    end
    table.insert(self.subprocesses_pids, pid)
    -- Balanced by the allowStandby() issued when we reap this pid.
    UIManager:preventStandby()
    self:_scheduleCollector()
    return true
end

function OPDSCoverLoader:_collectSubprocesses()
    self.subprocesses_collector = nil
    for i = #self.subprocesses_pids, 1, -1 do
        if ffiUtil.isSubProcessDone(self.subprocesses_pids[i]) then
            table.remove(self.subprocesses_pids, i)
            UIManager:allowStandby()
        end
    end
    if #self.subprocesses_pids > 0 then
        self:_scheduleCollector()
    end
end

function OPDSCoverLoader:_scheduleCollector()
    if self.subprocesses_collector then return end
    self.subprocesses_collector = function()
        self:_collectSubprocesses()
    end
    UIManager:scheduleIn(CHECK_INTERVAL, self.subprocesses_collector)
end

function OPDSCoverLoader:stop()
    for i = 1, #self.subprocesses_pids do
        ffiUtil.terminateSubProcess(self.subprocesses_pids[i])
    end
    -- They still need to be reaped, which _collectSubprocesses() will do.
    if #self.subprocesses_pids > 0 then
        self:_scheduleCollector()
    end
end

function OPDSCoverLoader:cleanUpCache()
    if lfs.attributes(self.cache_dir, "mode") ~= "directory" then return end
    local now = os.time()
    local ok, iter, dir_obj = pcall(lfs.dir, self.cache_dir)
    if not ok then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local path = self.cache_dir .. entry
            local attr = lfs.attributes(path)
            if attr and attr.mode == "file" then
                if entry:sub(-4) == ".tmp" or now - attr.modification > CACHE_MAX_AGE then
                    util.removeFile(path)
                end
            end
        end
    end
end

return OPDSCoverLoader
