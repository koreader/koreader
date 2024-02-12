--[[--
This module is responsible for reading and writing `metadata.lua` files
in the so-called sidecar directory
([Wikipedia definition](https://en.wikipedia.org/wiki/Sidecar_file)).
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local dump = require("dump")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local DocSettings = LuaSettings:extend{}

local HISTORY_DIR = DataStorage:getHistoryDir()
local DOCSETTINGS_DIR = DataStorage:getDocSettingsDir()
local DOCSETTINGS_HASH_DIR = DataStorage:getDocSettingsHashDir()
local custom_metadata_filename = "custom_metadata.lua"

function DocSettings.getSidecarStorage(location)
    if location == "dir" then
        return DOCSETTINGS_DIR
    elseif location == "hash" then
        return DOCSETTINGS_HASH_DIR
    end
end

local function isDir(dir)
    return lfs.attributes(dir, "mode") == "directory"
end

local function isFile(file)
    return lfs.attributes(file, "mode") == "file"
end

local is_history_location_enabled = isDir(HISTORY_DIR)

local doc_hash_cache = {}
local is_hash_location_enabled

function DocSettings.isHashLocationEnabled()
    if is_hash_location_enabled == nil then
        is_hash_location_enabled = isDir(DOCSETTINGS_HASH_DIR)
    end
    return is_hash_location_enabled
end

function DocSettings.setIsHashLocationEnabled(value)
    is_hash_location_enabled = value
end

local function buildCandidates(list)
    local candidates = {}
    local previous_entry_exists = false

    for i, file_path in ipairs(list) do
        -- Ignore missing files.
        if file_path ~= "" and isFile(file_path) then
            local mtime = lfs.attributes(file_path, "modification")
            -- NOTE: Extra trickery: if we're inserting a "backup" file, and its primary buddy exists,
            --       make sure it will *never* sort ahead of it by using the same mtime.
            --       This aims to avoid weird UTC/localtime issues when USBMS is involved,
            --       c.f., https://github.com/koreader/koreader/issues/9227#issuecomment-1345263324
            if file_path:sub(-4) == ".old" and previous_entry_exists then
                local primary_mtime = candidates[#candidates].mtime
                -- Only proceed with the switcheroo when necessary, and warn about it.
                if primary_mtime < mtime then
                    logger.warn("DocSettings: Backup", file_path, "is newer (", mtime, ") than its primary (", primary_mtime, "), fudging timestamps!")
                    -- Use the most recent timestamp for both (i.e., the backup's).
                    candidates[#candidates].mtime = mtime
                end
            end
            table.insert(candidates, {
                    path = file_path,
                    mtime = mtime,
                    prio = i,
                }
            )
            previous_entry_exists = true
        else
            previous_entry_exists = false
        end
    end

    -- MRU sort, tie breaker is insertion order (higher priority locations were inserted first).
    -- Iff a primary/backup pair of file both exist, of the two of them, the primary one *always* has priority,
    -- regardless of mtime (c.f., NOTE above).
    table.sort(candidates, function(l, r)
                               if l.mtime == r.mtime then
                                   return l.prio < r.prio
                               else
                                   return l.mtime > r.mtime
                               end
                           end)

    return candidates
end

local function getOrderedLocationCandidates()
    local preferred_location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    if preferred_location == "hash" then
        return { "hash", "doc", "dir" }
    end
    local candidates = preferred_location == "doc" and { "doc", "dir" } or { "dir", "doc" }
    if DocSettings.isHashLocationEnabled() then
        table.insert(candidates, "hash")
    end
    return candidates
end

--- Returns path to sidecar directory (`filename.sdr`).
-- Sidecar directory is the file without _last_ suffix.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @string force_location prefer e.g., "hash" or "dir" location over standard "doc", if available
-- @treturn string path to the sidecar directory (e.g., `/foo/bar.sdr`)
function DocSettings:getSidecarDir(doc_path, force_location)
    if doc_path == nil or doc_path == "" then return "" end
    local path = doc_path:match("(.*)%.") or doc_path -- file path without the last suffix
    local location = force_location or G_reader_settings:readSetting("document_metadata_folder", "doc")
    if location == "dir" then
        path = DOCSETTINGS_DIR .. path
    elseif location == "hash" then
        local hsh = doc_hash_cache[doc_path]
        if not hsh then
            hsh = util.partialMD5(doc_path)
            if not hsh then -- fallback to "doc"
                return path .. ".sdr"
            end
            doc_hash_cache[doc_path] = hsh
            logger.dbg("DocSettings: Caching new partial MD5 hash for", doc_path, "as", hsh)
        else
            logger.dbg("DocSettings: Using cached partial MD5 hash for", doc_path, "as", hsh)
        end
        -- converts b3fb8f4f8448160365087d6ca05c7fa2 to b3/ to avoid too many files in one dir
        local subpath = string.format("/%s/", hsh:sub(1, 2))
        path = DOCSETTINGS_HASH_DIR .. subpath .. hsh
    end
    return path .. ".sdr"
end

function DocSettings.getSidecarFilename(doc_path)
    local suffix = doc_path:match(".*%.(.+)") or "_"
    return "metadata." .. suffix .. ".lua"
end

--- Returns `true` if there is a `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn bool
function DocSettings:hasSidecarFile(doc_path)
    return self:findSidecarFile(doc_path) and true or false
end

--- Returns path of `metadata.lua` file if it exists, or nil.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @bool no_legacy set to true to skip check of the legacy history file
-- @treturn string (or nil on failure)
function DocSettings:findSidecarFile(doc_path, no_legacy)
    if doc_path == nil or doc_path == "" then return nil end
    local sidecar_filename = DocSettings.getSidecarFilename(doc_path)
    local sidecar_file
    for _, location in ipairs(getOrderedLocationCandidates()) do
        sidecar_file = self:getSidecarDir(doc_path, location) .. "/" .. sidecar_filename
        if isFile(sidecar_file) then
            return sidecar_file, location
        end
    end
    if is_history_location_enabled and not no_legacy then
        sidecar_file = self:getHistoryPath(doc_path)
        if isFile(sidecar_file) then
            return sidecar_file, "hist" -- for isSidecarFileNotInPreferredLocation() used in moveBookMetadata
        end
    end
end

function DocSettings.isSidecarFileNotInPreferredLocation(doc_path)
    local _, location = DocSettings:findSidecarFile(doc_path)
    return location and location ~= G_reader_settings:readSetting("document_metadata_folder", "doc")
end

function DocSettings:getHistoryPath(doc_path)
    if doc_path == nil or doc_path == "" then return "" end
    return HISTORY_DIR .. "/[" .. doc_path:gsub("(.*/)([^/]+)", "%1] %2"):gsub("/", "#") .. ".lua"
end

function DocSettings:getPathFromHistory(hist_name)
    if hist_name == nil or hist_name == "" then return "" end
    if hist_name:sub(-4) ~= ".lua" then return "" end -- ignore .lua.old backups
    -- 1. select everything included in brackets
    local s = string.match(hist_name,"%b[]")
    if s == nil or s == "" then return "" end
    -- 2. crop the bracket-sign from both sides
    -- 3. and finally replace decorative signs '#' to dir-char '/'
    return string.gsub(string.sub(s, 2, -3), "#", "/")
end

function DocSettings:getNameFromHistory(hist_name)
    if hist_name == nil or hist_name == "" then return "" end
    if hist_name:sub(-4) ~= ".lua" then return "" end -- ignore .lua.old backups
    local s = string.match(hist_name, "%b[]")
    if s == nil or s == "" then return "" end
    -- at first, search for path length
    -- and return the rest of string without 4 last characters (".lua")
    return string.sub(hist_name, string.len(s)+2, -5)
end

function DocSettings:getFileFromHistory(hist_name)
    local path = self:getPathFromHistory(hist_name)
    if path ~= "" then
        local name = self:getNameFromHistory(hist_name)
        if name ~= "" then
            return ffiutil.joinPath(path, name)
        end
    end
end

--- Opens a document's individual settings (font, margin, dictionary, etc.)
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn DocSettings object
function DocSettings:open(doc_path)
    -- NOTE: Beware, our new instance is new, but self is still DocSettings!
    local new = DocSettings:extend{}

    new.sidecar_filename = DocSettings.getSidecarFilename(doc_path)

    new.doc_sidecar_dir = new:getSidecarDir(doc_path, "doc")
    local doc_sidecar_file, legacy_sidecar_file
    if isDir(new.doc_sidecar_dir) then
        doc_sidecar_file = new.doc_sidecar_dir .. "/" .. new.sidecar_filename
        legacy_sidecar_file = new.doc_sidecar_dir .. "/" .. ffiutil.basename(doc_path) .. ".lua"
    end
    new.dir_sidecar_dir = new:getSidecarDir(doc_path, "dir")
    local dir_sidecar_file
    if isDir(new.dir_sidecar_dir) then
        dir_sidecar_file = new.dir_sidecar_dir .. "/" .. new.sidecar_filename
    end
    local hash_sidecar_file
    if DocSettings.isHashLocationEnabled() then
        new.hash_sidecar_dir = new:getSidecarDir(doc_path, "hash")
        hash_sidecar_file = new.hash_sidecar_dir .. "/" .. new.sidecar_filename
    end
    local history_file = is_history_location_enabled and new:getHistoryPath(doc_path)

    -- Candidates list, in order of priority:
    local candidates_list = {
        -- New sidecar file in doc folder
        doc_sidecar_file or "",
        -- Backup file of new sidecar file in doc folder
        doc_sidecar_file and (doc_sidecar_file .. ".old") or "",
        -- Legacy sidecar file
        legacy_sidecar_file or "",
        -- New sidecar file in docsettings folder
        dir_sidecar_file or "",
        -- Backup file of new sidecar file in docsettings folder
        dir_sidecar_file and (dir_sidecar_file .. ".old") or "",
        -- New sidecar file in hashdocsettings folder
        hash_sidecar_file or "",
        -- Backup file of new sidecar file in hashdocsettings folder
        hash_sidecar_file and (hash_sidecar_file .. ".old") or "",
        -- Legacy history folder
        history_file or "",
        -- Backup file in legacy history folder
        history_file and (history_file .. ".old") or "",
        -- Legacy kpdfview setting
        doc_path .. ".kpdfview.lua",
    }
    -- We get back an array of tables for *existing* candidates, sorted MRU first (insertion order breaks ties).
    local candidates = buildCandidates(candidates_list)

    local candidate_path, ok, stored
    for _, t in ipairs(candidates) do
        candidate_path = t.path
        -- Ignore empty files
        if lfs.attributes(candidate_path, "size") > 0 then
            ok, stored = pcall(dofile, candidate_path)
            -- Ignore empty tables
            if ok and next(stored) ~= nil then
                logger.dbg("DocSettings: data is read from", candidate_path)
                break
            end
        end
        logger.dbg("DocSettings:", candidate_path, "is invalid, removed.")
        os.remove(candidate_path)
    end
    if ok and stored then
        new.data = stored
        new.candidates = candidates
        new.source_candidate = candidate_path
    else
        new.data = {}
    end
    new.data.doc_path = doc_path

    return new
end

--- Light version of open(). Opens a sidecar file or a custom metadata file.
-- Returned object cannot be used to save changes to the sidecar file (flush()).
-- Must be used to save changes to the custom metadata file (flushCustomMetadata()).
function DocSettings.openSettingsFile(sidecar_file)
    local new = DocSettings:extend{}
    local ok, stored
    if sidecar_file then
        ok, stored = pcall(dofile, sidecar_file)
    end
    if ok and next(stored) ~= nil then
        new.data = stored
    else
        new.data = {}
    end
    new.sidecar_file = sidecar_file
    return new
end

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush(data, no_custom_metadata)
    data = data or self.data
    local sidecar_dirs
    local preferred_location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    if preferred_location == "doc" then
        sidecar_dirs = { self.doc_sidecar_dir,  self.dir_sidecar_dir } -- fallback for read-only book storage
    elseif preferred_location == "dir" then
        sidecar_dirs = { self.dir_sidecar_dir }
    elseif preferred_location == "hash" then
        if self.hash_sidecar_dir == nil then
            self.hash_sidecar_dir = self:getSidecarDir(data.doc_path, "hash")
        end
        sidecar_dirs = { self.hash_sidecar_dir }
    end

    local ser_data = dump(data, nil, true)
    for _, sidecar_dir in ipairs(sidecar_dirs) do
        local sidecar_dir_slash = sidecar_dir .. "/"
        local sidecar_file = sidecar_dir_slash .. self.sidecar_filename
        util.makePath(sidecar_dir)
        logger.dbg("DocSettings: Writing to", sidecar_file)
        local directory_updated = LuaSettings:backup(sidecar_file) -- "*.old"
        if util.writeToFile(ser_data, sidecar_file, true, true, directory_updated) then
            -- move custom cover file and custom metadata file to the metadata file location
            if not no_custom_metadata then
                local metadata_file, filepath, filename
                -- custom cover
                metadata_file = self:getCustomCoverFile()
                if metadata_file then
                    filepath, filename = util.splitFilePathName(metadata_file)
                    if filepath ~= sidecar_dir_slash then
                        ffiutil.copyFile(metadata_file, sidecar_dir_slash .. filename)
                        os.remove(metadata_file)
                        self:getCustomCoverFile(true) -- reset cache
                    end
                end
                -- custom metadata
                metadata_file = self:getCustomMetadataFile()
                if metadata_file then
                    filepath, filename = util.splitFilePathName(metadata_file)
                    if filepath ~= sidecar_dir_slash then
                        ffiutil.copyFile(metadata_file, sidecar_dir_slash .. filename)
                        os.remove(metadata_file)
                        self:getCustomMetadataFile(true) -- reset cache
                    end
                end
            end

            self:purge(sidecar_file) -- remove old candidates and empty sidecar folders

            return sidecar_dir
        end
    end
end

--- Purges (removes) sidecar directory.
function DocSettings:purge(sidecar_to_keep, data_to_purge)
    local custom_cover_file, custom_metadata_file
    if sidecar_to_keep == nil then
        custom_cover_file    = self:getCustomCoverFile()
        custom_metadata_file = self:getCustomMetadataFile()
    end
    if data_to_purge == nil then -- purge all
        data_to_purge = {
            doc_settings         = true,
            custom_cover_file    = custom_cover_file,
            custom_metadata_file = custom_metadata_file,
        }
    end

    -- Remove any of the old ones we may consider as candidates in DocSettings:open()
    if data_to_purge.doc_settings and self.candidates then
        for _, t in ipairs(self.candidates) do
            local candidate_path = t.path
            if isFile(candidate_path) then
                if (not sidecar_to_keep)
                        or (candidate_path ~= sidecar_to_keep and candidate_path ~= sidecar_to_keep .. ".old") then
                    os.remove(candidate_path)
                    logger.dbg("DocSettings: purged:", candidate_path)
                end
            end
        end
    end

    -- Remove custom
    if data_to_purge.custom_cover_file then
        os.remove(data_to_purge.custom_cover_file)
        self:getCustomCoverFile(true) -- reset cache
    end
    if data_to_purge.custom_metadata_file then
        os.remove(data_to_purge.custom_metadata_file)
        self:getCustomMetadataFile(true) -- reset cache
    end

    -- Remove empty sidecar dirs
    if data_to_purge.doc_settings or data_to_purge.custom_cover_file or data_to_purge.custom_metadata_file then
        for _, dir in ipairs({ self.doc_sidecar_dir, self.dir_sidecar_dir, self.hash_sidecar_dir }) do
            DocSettings.removeSidecarDir(dir)
        end
    end

    DocSettings.setIsHashLocationEnabled(nil) -- reset this in case last hash book is purged
end

--- Removes sidecar dir iff empty.
function DocSettings.removeSidecarDir(dir)
    if dir and isDir(dir) then
        if dir:match("^"..DOCSETTINGS_DIR) or dir:match("^"..DOCSETTINGS_HASH_DIR) then
            util.removePath(dir) -- remove empty parent folders
        else
            os.remove(dir) -- keep parent folders
        end
    end
end

--- Updates sdr location for file rename/copy/move/delete operations.
function DocSettings.updateLocation(doc_path, new_doc_path, copy)
    local has_sidecar_file = DocSettings:hasSidecarFile(doc_path)
    local custom_cover_file = DocSettings:findCustomCoverFile(doc_path)
    local custom_metadata_file = DocSettings:findCustomMetadataFile(doc_path)
    if not (has_sidecar_file or custom_cover_file or custom_metadata_file) then return end

    local doc_settings = DocSettings:open(doc_path)
    local do_purge

    if new_doc_path then -- copy/rename/move
        if G_reader_settings:readSetting("document_metadata_folder") ~= "hash" then -- keep hash location unchanged
            local new_sidecar_dir
            if has_sidecar_file then
                local new_doc_settings = DocSettings:open(new_doc_path)
                doc_settings.data.doc_path = new_doc_path
                new_sidecar_dir = new_doc_settings:flush(doc_settings.data, true) -- without custom
            end
            if not new_sidecar_dir then
                new_sidecar_dir = DocSettings:getSidecarDir(new_doc_path)
                util.makePath(new_sidecar_dir)
            end
            if custom_cover_file then
                local _, filename = util.splitFilePathName(custom_cover_file)
                ffiutil.copyFile(custom_cover_file, new_sidecar_dir .. "/" .. filename)
            end
            if custom_metadata_file then
                ffiutil.copyFile(custom_metadata_file, new_sidecar_dir .. "/" .. custom_metadata_filename)
            end
            do_purge = not copy
        end
    else -- delete
        if has_sidecar_file then
            local cache_file_path = doc_settings:readSetting("cache_file_path")
            if cache_file_path then
                os.remove(cache_file_path)
            end
        end
        do_purge = true
    end

    if do_purge then
        doc_settings.custom_cover_file = custom_cover_file -- cache
        doc_settings.custom_metadata_file = custom_metadata_file -- cache
        doc_settings:purge()
    end
end

-- custom section

function DocSettings:getCustomLocationCandidates(doc_path)
    local sidecar_dir
    local sidecar_file = self:findSidecarFile(doc_path, true) -- new locations only
    if sidecar_file then -- book was opened, write custom metadata to its sidecar dir
        sidecar_dir = util.splitFilePathName(sidecar_file):sub(1, -2)
        return { sidecar_dir }
    end
    -- new book, create sidecar dir in accordance with sdr location setting
    local preferred_location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    if preferred_location ~= "hash" then
        sidecar_dir = self:getSidecarDir(doc_path, "dir")
        if preferred_location == "doc" then
            local doc_sidecar_dir = self:getSidecarDir(doc_path, "doc")
            return { doc_sidecar_dir, sidecar_dir } -- fallback for read-only book storage
        end
    else -- "hash"
        sidecar_dir = self:getSidecarDir(doc_path, "hash")
    end
    return { sidecar_dir }
end

-- custom cover

local function findCustomCoverFileInDir(dir)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for f in iter, dir_obj do
            if util.splitFileNameSuffix(f) == "cover" then
                return dir .. "/" .. f
            end
        end
    end
end

--- Returns path to book custom cover file if it exists, or nil.
function DocSettings:findCustomCoverFile(doc_path)
    doc_path = doc_path or self.data.doc_path
    for _, location in ipairs(getOrderedLocationCandidates()) do
        local sidecar_dir = self:getSidecarDir(doc_path, location)
        local custom_cover_file = findCustomCoverFileInDir(sidecar_dir)
        if custom_cover_file then
            return custom_cover_file
        end
    end
end

function DocSettings:getCustomCoverFile(reset_cache)
    if reset_cache then
        self.custom_cover_file = nil
    else
        if self.custom_cover_file == nil then -- fill empty cache
            self.custom_cover_file = self:findCustomCoverFile() or false
        end
        return self.custom_cover_file
    end
end

function DocSettings:flushCustomCover(doc_path, image_file)
    local sidecar_dirs = self:getCustomLocationCandidates(doc_path)
    local new_cover_filename = "/cover." .. util.getFileNameSuffix(image_file):lower()
    for _, sidecar_dir in ipairs(sidecar_dirs) do
        util.makePath(sidecar_dir)
        local new_cover_file = sidecar_dir .. new_cover_filename
        if ffiutil.copyFile(image_file, new_cover_file) == nil then
            return true
        end
    end
end

-- custom metadata

--- Returns path to book custom metadata file if it exists, or nil.
function DocSettings:findCustomMetadataFile(doc_path)
    doc_path = doc_path or self.data.doc_path
    for _, location in ipairs(getOrderedLocationCandidates()) do
        local sidecar_dir = self:getSidecarDir(doc_path, location)
        local custom_metadata_file = sidecar_dir .. "/" .. custom_metadata_filename
        if isFile(custom_metadata_file) then
            return custom_metadata_file
        end
    end
end

function DocSettings:getCustomMetadataFile(reset_cache)
    if reset_cache then
        self.custom_metadata_file = nil
    else
        if self.custom_metadata_file == nil then -- fill empty cache
            self.custom_metadata_file = self:findCustomMetadataFile() or false
        end
        return self.custom_metadata_file
    end
end

function DocSettings:flushCustomMetadata(doc_path)
    local sidecar_dirs = self:getCustomLocationCandidates(doc_path)
    local s_out = dump(self.data, nil, true)
    for _, sidecar_dir in ipairs(sidecar_dirs) do
        util.makePath(sidecar_dir)
        local new_metadata_file = sidecar_dir .. "/" .. custom_metadata_filename
        if util.writeToFile(s_out, new_metadata_file, true, true) then
            return true
        end
    end
end

-- "hash" section

-- Returns the list of pairs {sidecar_file, custom_metadata_file}.
function DocSettings.findSidecarFilesInHashLocation()
    local res = {}
    local callback = function(fullpath, name)
        if name:match("metadata%..+%.lua$") then
            local sdr = { fullpath }
            local custom_metadata_file = fullpath:gsub(name, custom_metadata_filename)
            if isFile(custom_metadata_file) then
                table.insert(sdr, custom_metadata_file)
            end
            table.insert(res, sdr)
        end
    end
    util.findFiles(DOCSETTINGS_HASH_DIR, callback)
    return res
end

return DocSettings
