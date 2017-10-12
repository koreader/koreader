--[[--
This module is responsible for reading and writing `metadata.lua` files
in the so-called sidecar directory
([Wikipedia definition](https://en.wikipedia.org/wiki/Sidecar_file)).
]]

local DataStorage = require("datastorage")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local purgeDir = require("ffi/util").purgeDir

local DocSettings = {}

local HISTORY_DIR = DataStorage:getHistoryDir()

local function buildCandidate(file_path)
    -- Ignore empty files.
    if lfs.attributes(file_path, "mode") == "file" then
        return { file_path, lfs.attributes(file_path, "modification") }
    else
        return nil
    end
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
    return HISTORY_DIR .. "/[" .. fullpath:gsub("(.*/)([^/]+)","%1] %2"):gsub("/","#") .. ".lua"
end

function DocSettings:getPathFromHistory(hist_name)
    if hist_name == nil or hist_name == '' then return '' end
    -- 1. select everything included in brackets
    local s = string.match(hist_name,"%b[]")
    if s == nil or s == '' then return '' end
    -- 2. crop the bracket-sign from both sides
    -- 3. and finally replace decorative signs '#' to dir-char '/'
    return string.gsub(string.sub(s,2,-3),"#","/")
end

function DocSettings:getNameFromHistory(hist_name)
    if hist_name == nil or hist_name == '' then return '' end
    local s = string.match(hist_name, "%b[]")
    if s == nil or s == '' then return '' end
    -- at first, search for path length
    -- and return the rest of string without 4 last characters (".lua")
    return string.sub(hist_name, string.len(s)+2, -5)
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
    -- TODO(zijiehe): Remove history_path, use only sidecar.
    local new = {}
    new.history_file = self:getHistoryPath(docfile)

    local sidecar = self:getSidecarDir(docfile)
    new.sidecar = sidecar
    DocSettings:ensureSidecar(sidecar)
    -- If there is a file which has a same name as the sidecar directory, or
    -- the file system is read-only, we should not waste time to read it.
    if lfs.attributes(sidecar, "mode") == "directory" then
        -- New sidecar file name is metadata.{file last suffix}.lua. So we
        -- can handle two files with only different suffixes.
        new.sidecar_file = self:getSidecarFile(docfile)
        new.legacy_sidecar_file = sidecar.."/"..
                                  docfile:match("([^%/]+%..+)")..".lua"
    end

    local candidates = {}
    -- New sidecar file
    table.insert(candidates, buildCandidate(new.sidecar_file))
    -- Backup file of new sidecar file
    table.insert(candidates, buildCandidate(new.sidecar_file .. ".old"))
    -- Legacy sidecar file
    table.insert(candidates, buildCandidate(new.legacy_sidecar_file))
    -- Legacy history folder
    table.insert(candidates, buildCandidate(new.history_file))
    -- Backup file in legacy history folder
    table.insert(candidates, buildCandidate(new.history_file .. ".old"))
    -- Legacy kpdfview setting
    table.insert(candidates, buildCandidate(docfile..".kpdfview.lua"))
    table.sort(candidates, function(l, r)
                               if l == nil then
                                   return false
                               elseif r == nil then
                                   return true
                               else
                                   return l[2] > r[2]
                               end
                           end)
    local ok, stored
    for _, k in pairs(candidates) do
        -- Ignore empty files
        if lfs.attributes(k[1], "size") > 0 then
            ok, stored = pcall(dofile, k[1])
            -- Ignore the empty table.
            if ok and next(stored) ~= nil then
                logger.dbg("data is read from ", k[1])
                break
            end
        end
        logger.dbg(k[1], " is invalid, remove.")
        os.remove(k[1])
    end
    if ok and stored then
        new.data = stored
        new.candidates = candidates
    else
        new.data = {}
    end

    return setmetatable(new, {__index = DocSettings})
end

--- Reads a setting.
function DocSettings:readSetting(key)
    return self.data[key]
end

--- Saves a setting.
function DocSettings:saveSetting(key, value)
    self.data[key] = value
end

--- Deletes a setting.
function DocSettings:delSetting(key)
    self.data[key] = nil
end

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush()
    -- write serialized version of the data table into one of
    --  i) sidecar directory in the same directory of the document or
    -- ii) history directory in root directory of KOReader
    if not self.history_file and not self.sidecar_file then
        return
    end

    -- If we can write to sidecar_file, we do not need to write to history_file
    -- anymore.
    local serials = { self.sidecar_file, self.history_file }
    self:ensureSidecar(self.sidecar)
    local s_out = dump(self.data)
    os.setlocale('C', 'numeric')
    for _, f in pairs(serials) do
        if lfs.attributes(f, "mode") == "file" then
            logger.dbg("Rename ", f, " to ", f .. ".old")
            os.rename(f, f .. ".old")
        end
        logger.dbg("Write to ", f)
        local f_out = io.open(f, "w")
        if f_out ~= nil then
            f_out:write("-- we can read Lua syntax here!\nreturn ")
            f_out:write(s_out)
            f_out:write("\n")
            f_out:close()

            if self.candidates ~= nil
            and not G_reader_settings:readSetting(
                        "preserve_legacy_docsetting") then
                for _, k in pairs(self.candidates) do
                    if k[1] ~= f and k[1] ~= f .. ".old" then
                        logger.dbg("Remove legacy file ", k[1])
                        os.remove(k[1])
                        -- We should not remove sidecar folder, as it may
                        -- contain Kindle history files.
                    end
                end
            end

            break
        end
    end
end

function DocSettings:close()
    self:flush()
end

--- Purges (removes) sidecar directory.
function DocSettings:purge()
    if self.history_file then
        os.remove(self.history_file)
    end
    if lfs.attributes(self.sidecar, "mode") == "directory" then
        purgeDir(self.sidecar)
    end
    self.data = {}
end

return DocSettings
