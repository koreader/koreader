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

local is_hash_location_enabled
local hash_path_cache = {}

function DocSettings.isHashLocationEnabled()
    if is_hash_location_enabled == nil then
        is_hash_location_enabled = lfs.attributes(DOCSETTINGS_HASH_DIR, "mode") == "directory"
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
        if file_path ~= "" and lfs.attributes(file_path, "mode") == "file" then
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
        local hsh = hash_path_cache[doc_path]
        if not hsh then
            local file = io.open(doc_path, 'rb')
            if not file then return path .. ".sdr" end
            hsh = util.partialMD5(file)
            file:close()
            hash_path_cache[doc_path] = hsh
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

--- Returns path to `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn string path to `/foo/bar.sdr/metadata.lua` file
function DocSettings:getSidecarFile(doc_path, force_location)
    if doc_path == nil or doc_path == "" then return "" end
    -- If the file does not have a suffix or we are working on a directory, we
    -- should ignore the suffix part in metadata file path.
    local suffix = doc_path:match(".*%.(.+)") or ""
    return self:getSidecarDir(doc_path, force_location) .. "/metadata." .. suffix .. ".lua"
end

--- Returns `true` if there is a `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn bool
function DocSettings:hasSidecarFile(doc_path)
    return self:getDocSidecarFile(doc_path) and true or false
end

--- Returns path of `metadata.lua` file if it exists, or nil.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @bool no_legacy set to true to skip check of the legacy history file
-- @treturn string
function DocSettings:getDocSidecarFile(doc_path, no_legacy)
    local sidecar_file = self:getSidecarFile(doc_path, "doc")
    if lfs.attributes(sidecar_file, "mode") == "file" then
        return sidecar_file
    end
    sidecar_file = self:getSidecarFile(doc_path, "dir")
    if lfs.attributes(sidecar_file, "mode") == "file" then
        return sidecar_file
    end
    -- Calculate partial hash and check for hash-based files only if there are files to check
    if DocSettings.isHashLocationEnabled() then
        sidecar_file = self:getSidecarFile(doc_path, "hash")
        if lfs.attributes(sidecar_file, "mode") == "file" then
            return sidecar_file
        end
    end
    if not no_legacy then
        sidecar_file = self:getHistoryPath(doc_path)
        if lfs.attributes(sidecar_file, "mode") == "file" then
            return sidecar_file
        end
    end
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

--- Returns the directory and full filepath of a hash-ID-based sidecar metadata store
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
function DocSettings:getSidecarHashDirAndFilepath(doc_path)
    -- Getting PDF ID from trailer via mupdf has not been implemented - everything uses partial MD5
    local path = self:getSidecarDir(doc_path, "hash")
    local filetype = doc_path:match(".+%.(%w+)$")
    if not filetype or filetype == "" then
        return "", ""
    end
    local hash_file = "metadata." .. filetype .. ".lua"
    local hash_filepath = path .. "/" .. hash_file
    return path, hash_filepath
end

--- Opens a document's individual settings (font, margin, dictionary, etc.)
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn DocSettings object
function DocSettings:open(doc_path)
    -- NOTE: Beware, our new instance is new, but self is still DocSettings!
    local new = DocSettings:extend{}

    new.doc_sidecar_dir = new:getSidecarDir(doc_path, "doc")
    new.doc_sidecar_file = new:getSidecarFile(doc_path, "doc")
    local doc_sidecar_file, legacy_sidecar_file
    if lfs.attributes(new.doc_sidecar_dir, "mode") == "directory" then
        doc_sidecar_file = new.doc_sidecar_file
        legacy_sidecar_file = new.doc_sidecar_dir .. "/" .. ffiutil.basename(doc_path) .. ".lua"
    end
    new.dir_sidecar_dir = new:getSidecarDir(doc_path, "dir")
    new.dir_sidecar_file = new:getSidecarFile(doc_path, "dir")
    local dir_sidecar_file
    if lfs.attributes(new.dir_sidecar_dir, "mode") == "directory" then
        dir_sidecar_file = new.dir_sidecar_file
    end
    local history_file = new:getHistoryPath(doc_path)

    local hash_sidecar_dir, hash_sidecar_file
    if DocSettings.isHashLocationEnabled() then
        hash_sidecar_dir, hash_sidecar_file =
                new:getSidecarHashDirAndFilepath(doc_path)
        new.hash_sidecar_dir = hash_sidecar_dir
        new.hash_sidecar_file = hash_sidecar_file
    end

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
        -- Hash or PDF fingerprint-based sidecar file lookup
        hash_sidecar_file or "",
        -- Backup file of hash or PDF fingerprint-based sidecar file lookup
        hash_sidecar_file and (new.hash_sidecar_file .. ".old") or "",
        -- Legacy history folder
        history_file,
        -- Backup file in legacy history folder
        history_file .. ".old",
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

local function writeToFile(data, file)
    file:write("-- we can read Lua syntax here!\nreturn ")
    file:write(data)
    file:write("\n")
    ffiutil.fsyncOpenedFile(file) -- force flush to the storage device
    file:close()
end

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush(data, no_custom_metadata)
    -- Depending on the settings, doc_settings are saved to the book folder or
    -- to koreader/docsettings folder. The latter is also a fallback for read-only book storage.
    local serials
    local preferred_metdata_storage = G_reader_settings:readSetting("document_metadata_folder", "doc")
    if preferred_metdata_storage == "doc" then
        serials = { {self.doc_sidecar_dir, self.doc_sidecar_file},
              {self.dir_sidecar_dir, self.dir_sidecar_file}, }
    elseif preferred_metdata_storage == "dir" then
        serials = { {self.dir_sidecar_dir, self.dir_sidecar_file}, }
    elseif preferred_metdata_storage == "hash" then
        if self.hash_sidecar_dir == nil or self.hash_sidecar_file == nil then
            self.hash_sidecar_dir, self.hash_sidecar_file =
                    self:getSidecarHashDirAndFilepath(self.data.doc_path)
        end
        serials = { {self.hash_sidecar_dir, self.hash_sidecar_file } }
    end

    local s_out = dump(data or self.data, nil, true)
    for _, s in ipairs(serials) do
        local sidecar_dir, sidecar_file = unpack(s)
        util.makePath(sidecar_dir)
        local directory_updated = false
        if lfs.attributes(sidecar_file, "mode") == "file" then
            -- As an additional safety measure (to the ffiutil.fsync* calls used below),
            -- we only backup the file to .old when it has not been modified in the last 60 seconds.
            -- This should ensure in the case the fsync calls are not supported
            -- that the OS may have itself sync'ed that file content in the meantime.
            local mtime = lfs.attributes(sidecar_file, "modification")
            if mtime < os.time() - 60 then
                logger.dbg("DocSettings: Renamed", sidecar_file, "to", sidecar_file .. ".old")
                os.rename(sidecar_file, sidecar_file .. ".old")
                directory_updated = true -- fsync directory content too below
            end
        end
        logger.dbg("DocSettings: Writing to", sidecar_file)
        local f_out = io.open(sidecar_file, "w")
        if f_out ~= nil then
            writeToFile(s_out, f_out)

            if directory_updated then
                -- Ensure the file renaming is flushed to storage device
                ffiutil.fsyncDirectory(sidecar_file)
            end

            -- move custom cover file and custom metadata file to the metadata file location
            if not no_custom_metadata then
                local metadata_file, filepath, filename
                -- custom cover
                metadata_file = self:getCoverFile()
                if metadata_file then
                    filepath, filename = util.splitFilePathName(metadata_file)
                    if filepath ~= sidecar_dir .. "/" then
                        ffiutil.copyFile(metadata_file, sidecar_dir .. "/" .. filename)
                        os.remove(metadata_file)
                        self:getCoverFile(true) -- reset cache
                    end
                end
                -- custom metadata
                metadata_file = self:getCustomMetadataFile()
                if metadata_file then
                    filepath, filename = util.splitFilePathName(metadata_file)
                    if filepath ~= sidecar_dir .. "/" then
                        ffiutil.copyFile(metadata_file, sidecar_dir .. "/" .. filename)
                        os.remove(metadata_file)
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
        custom_cover_file    = self:getCoverFile()
        custom_metadata_file = self:getCustomMetadataFile()
    end
    if data_to_purge == nil then
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
            if lfs.attributes(candidate_path, "mode") == "file" then
                if (not sidecar_to_keep)
                        or (candidate_path ~= sidecar_to_keep and candidate_path ~= sidecar_to_keep .. ".old") then
                    os.remove(candidate_path)
                    logger.dbg("DocSettings: purged:", candidate_path)
                end
            end
        end
    end

    if data_to_purge.custom_cover_file then
        os.remove(data_to_purge.custom_cover_file)
        self:getCoverFile(true) -- reset cache
    end
    if data_to_purge.custom_metadata_file then
        os.remove(data_to_purge.custom_metadata_file)
    end

    if data_to_purge.doc_settings or data_to_purge.custom_cover_file or data_to_purge.custom_metadata_file then
        -- remove sidecar dirs iff empty
        if lfs.attributes(self.doc_sidecar_dir, "mode") == "directory" then
            os.remove(self.doc_sidecar_dir) -- keep parent folders
        end
        if lfs.attributes(self.dir_sidecar_dir, "mode") == "directory" then
            util.removePath(self.dir_sidecar_dir) -- remove empty parent folders
        end
        if self.hash_sidecar_dir and lfs.attributes(self.hash_sidecar_dir, "mode") == "directory" then
            util.removePath(self.hash_sidecar_dir) -- remove empty parent folders
        end
    end
    DocSettings.setIsHashLocationEnabled(nil) -- reset this in case last hash book is purged
end

--- Removes empty sidecar dir.
function DocSettings:removeSidecarDir(doc_path, sidecar_dir)
    if sidecar_dir == self:getSidecarDir(doc_path, "doc") then
        os.remove(sidecar_dir)
    else
        util.removePath(sidecar_dir)
    end
end

--- Updates sdr location for file rename/copy/move/delete operations.
function DocSettings:updateLocation(doc_path, new_doc_path, copy)
    local doc_settings, new_sidecar_dir, cover_file
    if G_reader_settings:readSetting("document_metadata_folder") == "hash" then
        -- none of these operations (except delete) changes the hash -> no location change
        if not new_doc_path then
            doc_settings = DocSettings:open(doc_path)
            local cache_file_path = doc_settings:readSetting("cache_file_path")
            if cache_file_path then os.remove(cache_file_path) end
            cover_file = doc_settings:getCoverFile()
            doc_settings:purge()
        end
    else
        -- update metadata
        if DocSettings:hasSidecarFile(doc_path) then
            doc_settings = DocSettings:open(doc_path)
            if new_doc_path then
                local new_doc_settings = DocSettings:open(new_doc_path)
                -- save doc settings to the new location, no custom metadata yet
                new_sidecar_dir = new_doc_settings:flush(doc_settings.data, true)
            else
                local cache_file_path = doc_settings:readSetting("cache_file_path")
                if cache_file_path then
                    os.remove(cache_file_path)
                end
            end
        end

        -- update custom metadata
        if not doc_settings then
            doc_settings = DocSettings:open(doc_path)
        end
        cover_file = doc_settings:getCoverFile()
        if new_doc_path then
            -- custom cover
            if cover_file then
                if not new_sidecar_dir then
                    new_sidecar_dir = DocSettings:getSidecarDir(new_doc_path)
                    util.makePath(new_sidecar_dir)
                end
                local _, filename = util.splitFilePathName(cover_file)
                ffiutil.copyFile(cover_file, new_sidecar_dir .. "/" .. filename)
            end
            -- custom metadata
            local metadata_file = self:getCustomMetadataFile(doc_path)
            if metadata_file then
                if not new_sidecar_dir then
                    new_sidecar_dir = DocSettings:getSidecarDir(new_doc_path)
                    util.makePath(new_sidecar_dir)
                end
                ffiutil.copyFile(metadata_file, new_sidecar_dir .. "/" .. custom_metadata_filename)
            end
        end

        if not copy then
            doc_settings:purge()
        end
    end

    if cover_file then -- after purge because purge uses cover file cache
        doc_settings:getCoverFile(true) -- reset cache
    end
end

-- custom cover

local function findCoverFileInDir(dir)
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
function DocSettings:findCoverFile(doc_path)
    doc_path = doc_path or self.data.doc_path
    local location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    local sidecar_dir = self:getSidecarDir(doc_path, location)
    local cover_file = findCoverFileInDir(sidecar_dir)
    if cover_file then return cover_file end
    local candidates = {"doc", "dir"}
    if DocSettings.isHashLocationEnabled() then
        table.insert(candidates, "hash")
    end
    for _, mode in ipairs(candidates) do
        if mode ~= location then
            sidecar_dir = self:getSidecarDir(doc_path, mode)
            cover_file = findCoverFileInDir(sidecar_dir)
            if cover_file then return cover_file end
        end
    end
end

function DocSettings:getCoverFile(reset_cache)
    if reset_cache then
        self.cover_file = nil
    else
        if self.cover_file == nil then -- fill empty cache
            self.cover_file = self:findCoverFile() or false
        end
        return self.cover_file
    end
end

function DocSettings:getCustomCandidateSidecarDirs(doc_path)
    local sidecar_file = self:getDocSidecarFile(doc_path, true) -- new locations only
    if sidecar_file then -- book was opened, write custom metadata to its sidecar dir
        local sidecar_dir = util.splitFilePathName(sidecar_file):sub(1, -2)
        return { sidecar_dir }
    end
    -- new book, create sidecar dir in accordance with sdr location setting
    local dir_sidecar_dir = self:getSidecarDir(doc_path, "dir")
    local preferred_metadata_storage = G_reader_settings:readSetting("document_metadata_folder", "doc")
    if preferred_metadata_storage == "doc" then
        local doc_sidecar_dir = self:getSidecarDir(doc_path, "doc")
        return { doc_sidecar_dir, dir_sidecar_dir } -- fallback in case of readonly book storage
    elseif preferred_metadata_storage == "hash" then
        local hash_sidecar_dir = self:getSidecarDir(doc_path, "hash")
        return { hash_sidecar_dir }
    end
    return { dir_sidecar_dir }
end

function DocSettings:flushCustomCover(doc_path, image_file)
    local sidecar_dirs = self:getCustomCandidateSidecarDirs(doc_path)
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
function DocSettings:getCustomMetadataFile(doc_path)
    doc_path = doc_path or self.data.doc_path

    local candidates = {"doc", "dir"}
    if DocSettings.isHashLocationEnabled() then
        table.insert(candidates, "hash")
    end
    for _, mode in ipairs(candidates) do
        local file = self:getSidecarDir(doc_path, mode) .. "/" .. custom_metadata_filename
        if lfs.attributes(file, "mode") == "file" then
            return file
        end
    end
end

function DocSettings:openCustomMetadata(custom_metadata_file)
    local new = DocSettings:extend{}
    local ok, stored
    if custom_metadata_file then
        ok, stored = pcall(dofile, custom_metadata_file)
    end
    if ok and next(stored) ~= nil then
        new.data = stored
    else
        new.data = {}
    end
    new.custom_metadata_file = custom_metadata_file
    return new
end

function DocSettings:flushCustomMetadata(doc_path)
    local sidecar_dirs = self:getCustomCandidateSidecarDirs(doc_path)
    local new_sidecar_dir
    local s_out = dump(self.data, nil, true)
    for _, sidecar_dir in ipairs(sidecar_dirs) do
        util.makePath(sidecar_dir)
        local f_out = io.open(sidecar_dir .. "/" .. custom_metadata_filename, "w")
        if f_out ~= nil then
            writeToFile(s_out, f_out)
            new_sidecar_dir = sidecar_dir .. "/"
            break
        end
    end
    -- remove old custom metadata file if it was in alternative location
    if self.custom_metadata_file then
        local old_sidecar_dir = util.splitFilePathName(self.custom_metadata_file)
        if old_sidecar_dir ~= new_sidecar_dir then
            os.remove(self.custom_metadata_file)
            self:removeSidecarDir(doc_path, old_sidecar_dir)
        end
    end
end

-- hash-based SDR storage
local function getSdrsInDir(path)
    -- Get all the metadata.filetype.lua files under directory path.
    -- Derived from readerdictionary.getIfosInDir()
    local sdrs = {}
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if ok then
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." then
                local fullpath = path .. "/" .. name
                local attributes = lfs.attributes(fullpath)
                if attributes ~= nil then
                    if attributes.mode == "directory" then
                        local dirifos = getSdrsInDir(fullpath) -- recurse
                        for _, ifo in pairs(dirifos) do
                            table.insert(sdrs, ifo)
                        end
                    elseif name:match("metadata%..+%.lua$") then
                        table.insert(sdrs, fullpath)
                    end
                end
            end
        end
    end
    return sdrs
end

function DocSettings.getHashDirSdrInfos()
    local sdrs = getSdrsInDir(DOCSETTINGS_HASH_DIR)
    local title_author_strs = {}
    for _, sdr in ipairs(sdrs) do
        -- Ignore empty files
        if lfs.attributes(sdr, "size") > 0 then
            local ok, stored
            ok, stored = pcall(dofile, sdr)
            -- Ignore empty tables
            if ok and next(stored) ~= nil then
                local info_str, custom_authors
                local sdr_path = sdr:sub(1, sdr:match(".*/()") - 1) -- SDR path
                local custom_metadata_file = sdr_path .. custom_metadata_filename
                if custom_metadata_file then
                    local custom = DocSettings:openCustomMetadata(custom_metadata_file)
                    local custom_props = custom:readSetting("custom_props")
                    if custom_props then
                        if custom_props.title then info_str = custom_props.title end
                        if custom_props.authors then custom_authors = custom_props.authors end
                    end
                end
                if not info_str then info_str = stored.doc_props.title end
                if not info_str then info_str = "untitled document" end
                if custom_authors then
                    info_str = info_str .. ", author: " .. custom_authors
                elseif stored.doc_props.authors then
                     info_str = info_str .. ", author: " .. stored.doc_props.authors
                end
                if stored.stats then
                    if stored.stats.highlights > 0 then
                        info_str = info_str .. ", highlights: " .. stored.stats.highlights
                    end
                    if stored.stats.notes > 0 then
                        info_str = info_str .. ", notes: " .. stored.stats.notes
                    end
                end
                info_str = info_str .. ", path: " .. sdr:sub(sdr:find("/", 3) + 1)
                table.insert(title_author_strs, info_str)
            else
                table.insert(title_author_strs, "error " .. sdr)
            end
        else
            table.insert(title_author_strs, "zero-size file " .. sdr)
        end
    end
    return title_author_strs
end

return DocSettings
