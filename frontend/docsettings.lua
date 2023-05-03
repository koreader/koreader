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

local DocSettings = LuaSettings:extend{
    cover_ext = { "png", "jpg", "jpeg", "gif", "tif", "tiff", "svg" },
}

local HISTORY_DIR = DataStorage:getHistoryDir()
local DOCSETTINGS_DIR = DataStorage:getDocSettingsDir()

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
-- @treturn string path to the sidecar directory (e.g., `/foo/bar.sdr`)
function DocSettings:getSidecarDir(doc_path, force_location)
    if doc_path == nil or doc_path == "" then return "" end
    local path = doc_path:match("(.*)%.") or doc_path -- file path without the last suffix
    local location = force_location or G_reader_settings:readSetting("document_metadata_folder", "doc")
    if location == "dir" then
        path = DOCSETTINGS_DIR..path
    end
    return path..".sdr"
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

--- Returns path of `metadata.lua` file if it exists, or nil.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @bool no_legacy set to true to skip check of the legacy history file
-- @treturn string
function DocSettings:hasSidecarFile(doc_path, no_legacy)
    local sidecar_file = self:getSidecarFile(doc_path, "doc")
    if lfs.attributes(sidecar_file, "mode") == "file" then
        return sidecar_file
    end
    sidecar_file = self:getSidecarFile(doc_path, "dir")
    if lfs.attributes(sidecar_file, "mode") == "file" then
        return sidecar_file
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

--- Returns path to book custom cover file if it exists, or nil.
function DocSettings:findCoverFile(doc_path)
    local location = G_reader_settings:readSetting("document_metadata_folder", "doc")
    local sidecar_dir = self:getSidecarDir(doc_path, location)
    local cover_file = self:_findCoverFileInDir(sidecar_dir)
    if not cover_file then
        location = location == "doc" and "dir" or "doc"
        sidecar_dir = self:getSidecarDir(doc_path, location)
        cover_file = self:_findCoverFileInDir(sidecar_dir)
    end
    return cover_file
end

function DocSettings:_findCoverFileInDir(dir)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for f in iter, dir_obj do
            for _, ext in ipairs(self.cover_ext) do
                if f == "cover." .. ext then
                    return dir .. "/" .. f
                end
            end
        end
    end
end

function DocSettings:getCoverFile(reset_cache)
    if reset_cache then
        self.cover_file = nil
    else
        if self.cover_file == nil then
            self.cover_file = DocSettings:findCoverFile(self.data.doc_path) or false
        end
        return self.cover_file
    end
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
        legacy_sidecar_file = new.doc_sidecar_dir.."/"..ffiutil.basename(doc_path)..".lua"
    end
    new.dir_sidecar_dir = new:getSidecarDir(doc_path, "dir")
    new.dir_sidecar_file = new:getSidecarFile(doc_path, "dir")
    local dir_sidecar_file
    if lfs.attributes(new.dir_sidecar_dir, "mode") == "directory" then
        dir_sidecar_file = new.dir_sidecar_file
    end
    local history_file = new:getHistoryPath(doc_path)

    -- Candidates list, in order of priority:
    local candidates_list = {
        -- New sidecar file in doc folder
        doc_sidecar_file or "",
        -- Backup file of new sidecar file in doc folder
        doc_sidecar_file and (doc_sidecar_file..".old") or "",
        -- Legacy sidecar file
        legacy_sidecar_file or "",
        -- New sidecar file in docsettings folder
        dir_sidecar_file or "",
        -- Backup file of new sidecar file in docsettings folder
        dir_sidecar_file and (dir_sidecar_file..".old") or "",
        -- Legacy history folder
        history_file,
        -- Backup file in legacy history folder
        history_file..".old",
        -- Legacy kpdfview setting
        doc_path..".kpdfview.lua",
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

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush(data, no_cover)
    -- Depending on the settings, doc_settings are saved to the book folder or
    -- to koreader/docsettings folder. The latter is also a fallback for read-only book storage.
    local serials = G_reader_settings:readSetting("document_metadata_folder", "doc") == "doc"
        and { {self.doc_sidecar_dir, self.doc_sidecar_file},
              {self.dir_sidecar_dir, self.dir_sidecar_file}, }
         or { {self.dir_sidecar_dir, self.dir_sidecar_file}, }

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
            f_out:write("-- we can read Lua syntax here!\nreturn ")
            f_out:write(s_out)
            f_out:write("\n")
            ffiutil.fsyncOpenedFile(f_out) -- force flush to the storage device
            f_out:close()

            if directory_updated then
                -- Ensure the file renaming is flushed to storage device
                ffiutil.fsyncDirectory(sidecar_file)
            end

            -- move cover file to the metadata file location
            if not no_cover then
                local cover_file = self:getCoverFile()
                if cover_file and util.splitFilePathName(cover_file) ~= sidecar_dir then
                    ffiutil.copyFile(cover_file, sidecar_dir)
                    os.remove(cover_file)
                    self:getCoverFile(true) -- reset cache
                end
            end

            self:purge(sidecar_file) -- remove old candidates and empty sidecar folders

            return sidecar_dir
        end
    end
end

--- Purges (removes) sidecar directory.
function DocSettings:purge(sidecar_to_keep)
    -- Remove any of the old ones we may consider as candidates in DocSettings:open()
    if self.candidates then
        for _, t in ipairs(self.candidates) do
            local candidate_path = t.path
            if lfs.attributes(candidate_path, "mode") == "file" then
                if (not sidecar_to_keep)
                        or (candidate_path ~= sidecar_to_keep and candidate_path ~= sidecar_to_keep..".old") then
                    os.remove(candidate_path)
                    logger.dbg("DocSettings: purged:", candidate_path)
                end
            end
        end
    end

    local custom_metadata_purged
    if not sidecar_to_keep then
        local cover_file = self:getCoverFile()
        if cover_file then
            os.remove(cover_file)
            self:getCoverFile(true) -- reset cache
            custom_metadata_purged = true
        end
    end
    if lfs.attributes(self.doc_sidecar_dir, "mode") == "directory" then
        os.remove(self.doc_sidecar_dir) -- keep parent folders
    end
    if lfs.attributes(self.dir_sidecar_dir, "mode") == "directory" then
        util.removePath(self.dir_sidecar_dir) -- remove empty parent folders
    end

    return custom_metadata_purged
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
    local doc_settings, new_sidecar_dir

    -- update metadata
    if self:hasSidecarFile(doc_path) then
        doc_settings = DocSettings:open(doc_path)
        if new_doc_path then
            local new_doc_settings = DocSettings:open(new_doc_path)
            -- save doc settings to the new location, no cover file yet
            new_sidecar_dir = new_doc_settings:flush(doc_settings.data, true)
        else
            local cache_file_path = doc_settings:readSetting("cache_file_path")
            if cache_file_path then
                os.remove(cache_file_path)
            end
        end
    end

    -- update cover file
    if not doc_settings then
        doc_settings = DocSettings:open(doc_path)
    end
    local cover_file = doc_settings:getCoverFile()
    if cover_file and new_doc_path then
        if not new_sidecar_dir then
            new_sidecar_dir = self:getSidecarDir(new_doc_path)
            util.makePath(new_sidecar_dir)
        end
        local _, filename = util.splitFilePathName(cover_file)
        ffiutil.copyFile(cover_file, new_sidecar_dir .. "/" .. filename)
    end

    if not copy then
        doc_settings:purge()
    end
    if cover_file then
        doc_settings:getCoverFile(true) -- reset cache
    end
end

return DocSettings
