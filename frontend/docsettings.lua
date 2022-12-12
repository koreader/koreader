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
--
-- Sidecar directory is the file without _last_ suffix.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn string path to the sidecar directory (e.g., `/foo/bar.sdr`)
function DocSettings:getSidecarDir(doc_path)
    if doc_path == nil or doc_path == '' then return '' end
    local file_without_suffix = doc_path:match("(.*)%.")
    if file_without_suffix then
        return file_without_suffix..".sdr"
    end
    return doc_path..".sdr"
end

--- Returns path to `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn string path to `/foo/bar.sdr/metadata.lua` file
function DocSettings:getSidecarFile(doc_path)
    if doc_path == nil or doc_path == '' then return '' end
    -- If the file does not have a suffix or we are working on a directory, we
    -- should ignore the suffix part in metadata file path.
    local suffix = doc_path:match(".*%.(.+)")
    if suffix == nil then
        suffix = ''
    end
    return self:getSidecarDir(doc_path) .. "/metadata." .. suffix .. ".lua"
end

--- Returns `true` if there is a `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn bool
function DocSettings:hasSidecarFile(doc_path)
    return lfs.attributes(self:getSidecarFile(doc_path), "mode") == "file"
end

function DocSettings:getHistoryPath(fullpath)
    return HISTORY_DIR .. "/[" .. fullpath:gsub("(.*/)([^/]+)", "%1] %2"):gsub("/", "#") .. ".lua"
end

function DocSettings:getPathFromHistory(hist_name)
    if hist_name == nil or hist_name == '' then return '' end
    if hist_name:sub(-4) ~= ".lua" then return '' end -- ignore .lua.old backups
    -- 1. select everything included in brackets
    local s = string.match(hist_name,"%b[]")
    if s == nil or s == '' then return '' end
    -- 2. crop the bracket-sign from both sides
    -- 3. and finally replace decorative signs '#' to dir-char '/'
    return string.gsub(string.sub(s, 2, -3), "#", "/")
end

function DocSettings:getNameFromHistory(hist_name)
    if hist_name == nil or hist_name == '' then return '' end
    if hist_name:sub(-4) ~= ".lua" then return '' end -- ignore .lua.old backups
    local s = string.match(hist_name, "%b[]")
    if s == nil or s == '' then return '' end
    -- at first, search for path length
    -- and return the rest of string without 4 last characters (".lua")
    return string.sub(hist_name, string.len(s)+2, -5)
end

function DocSettings:getLastSaveTime(doc_path)
    local attr = lfs.attributes(self:getSidecarFile(doc_path))
    if attr and attr.mode == "file" then
        return attr.modification
    end
end

function DocSettings:ensureSidecar(sidecar)
    if lfs.attributes(sidecar, "mode") ~= "directory" then
        lfs.mkdir(sidecar)
    end
end

--- Opens a document's individual settings (font, margin, dictionary, etc.)
-- @string docfile path to the document (e.g., `/foo/bar.pdf`)
-- @treturn DocSettings object
function DocSettings:open(docfile)
    --- @todo (zijiehe): Remove history_path, use only sidecar.

    -- NOTE: Beware, our new instance is new, but self is still DocSettings!
    local new = DocSettings:extend{}
    new.history_file = new:getHistoryPath(docfile)

    local sidecar = new:getSidecarDir(docfile)
    new.sidecar = sidecar
    DocSettings:ensureSidecar(sidecar)
    -- If there is a file which has a same name as the sidecar directory,
    -- or the file system is read-only, we should not waste time to read it.
    if lfs.attributes(sidecar, "mode") == "directory" then
        -- New sidecar file name is metadata.{file last suffix}.lua.
        -- So we can handle two files with only different suffixes.
        new.sidecar_file = new:getSidecarFile(docfile)
        new.legacy_sidecar_file = sidecar.."/"..
                                  ffiutil.basename(docfile)..".lua"
    end

    -- Candidates list, in order of priority:
    local candidates_list = {
        -- New sidecar file
        new.sidecar_file or "",
        -- Backup file of new sidecar file
        new.sidecar_file and (new.sidecar_file .. ".old") or "",
        -- Legacy sidecar file
        new.legacy_sidecar_file or "",
        -- Legacy history folder
        new.history_file,
        -- Backup file in legacy history folder
        new.history_file .. ".old",
        -- Legacy kpdfview setting
        docfile..".kpdfview.lua",
    }
    -- We get back an array of tables for *existing* candidates, sorted MRU first (insertion order breaks ties).
    local candidates = buildCandidates(candidates_list)

    local ok, stored, filepath
    for _, t in ipairs(candidates) do
        local candidate_path = t.path
        -- Ignore empty files
        if lfs.attributes(candidate_path, "size") > 0 then
            ok, stored = pcall(dofile, candidate_path)
            -- Ignore empty tables
            if ok and next(stored) ~= nil then
                logger.dbg("DocSettings: data is read from", candidate_path)
                filepath = candidate_path
                break
            end
        end
        logger.dbg("DocSettings:", candidate_path, "is invalid, removed.")
        os.remove(candidate_path)
    end
    if ok and stored then
        new.data = stored
        new.candidates = candidates
        new.filepath = filepath
    else
        new.data = {}
    end

    return new
end

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush()
    -- write serialized version of the data table into one of
    --  i) sidecar directory in the same directory of the document or
    -- ii) history directory in root directory of KOReader
    if not self.history_file and not self.sidecar_file then
        return
    end

    -- If we can write to sidecar_file, we do not need to write to history_file anymore.
    local serials = {}
    if self.sidecar_file then
        table.insert(serials, self.sidecar_file)
    end
    if self.history_file then
        table.insert(serials, self.history_file)
    end
    self:ensureSidecar(self.sidecar)
    local s_out = dump(self.data)
    for _, f in ipairs(serials) do
        local directory_updated = false
        if lfs.attributes(f, "mode") == "file" then
            -- As an additional safety measure (to the ffiutil.fsync* calls used below),
            -- we only backup the file to .old when it has not been modified in the last 60 seconds.
            -- This should ensure in the case the fsync calls are not supported
            -- that the OS may have itself sync'ed that file content in the meantime.
            local mtime = lfs.attributes(f, "modification")
            if mtime < os.time() - 60 then
                logger.dbg("DocSettings: Renamed", f, "to", f .. ".old")
                os.rename(f, f .. ".old")
                directory_updated = true -- fsync directory content too below
            end
        end
        logger.dbg("DocSettings: Writing to", f)
        local f_out = io.open(f, "w")
        if f_out ~= nil then
            f_out:write("-- we can read Lua syntax here!\nreturn ")
            f_out:write(s_out)
            f_out:write("\n")
            ffiutil.fsyncOpenedFile(f_out) -- force flush to the storage device
            f_out:close()

            if self.candidates ~= nil
            and G_reader_settings:nilOrFalse("preserve_legacy_docsetting") then
                for _, t in ipairs(self.candidates) do
                    local candidate_path = t.path
                    if candidate_path ~= f and candidate_path ~= f .. ".old" then
                        logger.dbg("DocSettings: Removed legacy file", candidate_path)
                        os.remove(candidate_path)
                        -- We should not remove sidecar folder, as it may
                        -- contain Kindle history files.
                    end
                end
            end

            if directory_updated then
                -- Ensure the file renaming is flushed to storage device
                ffiutil.fsyncDirectory(f)
            end
            break
        end
    end
end

function DocSettings:getFilePath()
    return self.filepath
end

--- Purges (removes) sidecar directory.
function DocSettings:purge(full)
    -- Remove any of the old ones we may consider as candidates in DocSettings:open()
    if self.history_file then
        os.remove(self.history_file)
        os.remove(self.history_file .. ".old")
    end
    if self.legacy_sidecar_file then
        os.remove(self.legacy_sidecar_file)
    end
    if lfs.attributes(self.sidecar, "mode") == "directory" then
        if full then
            -- Asked to remove all the content of this .sdr directory, whether it's ours or not
            ffiutil.purgeDir(self.sidecar)
        else
            -- Only remove the files we know we may have created with our usual names.
            for f in lfs.dir(self.sidecar) do
                local fullpath = self.sidecar.."/"..f
                local to_remove = false
                if lfs.attributes(fullpath, "mode") == "file" then
                    -- Currently, we only create a single file in there,
                    -- named metadata.suffix.lua (ie. metadata.epub.lua),
                    -- with possibly backups named metadata.epub.lua.old and
                    -- metadata.epub.lua.old_dom20180528,
                    -- so all sharing the same base: self.sidecar_file
                    if util.stringStartsWith(fullpath, self.sidecar_file) then
                        to_remove = true
                    end
                end
                if to_remove then
                    os.remove(fullpath)
                    logger.dbg("DocSettings: purged:", fullpath)
                end
            end
            -- If the sidecar folder ends up empty, os.remove() can delete it.
            -- Otherwise, the following statement has no effect.
            os.remove(self.sidecar)
        end
    end
    -- We should have meet the candidate we used and remove it above.
    -- But in case we didn't, remove it.
    if self.filepath and lfs.attributes(self.filepath, "mode") == "file" then
        os.remove(self.filepath)
    end
    self.data = {}
end

return DocSettings
