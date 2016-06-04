local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local dump = require("dump")
local purgeDir = require("ffi/util").purgeDir

local DocSettings = {}

local history_dir = DataStorage:getHistoryDir()

local function buildCandidate(file_path)
    if lfs.attributes(file_path, "mode") == "file" then
        return { file_path, lfs.attributes(file_path, "modification") }
    else
        return nil
    end
end

-- Sidecar directory is the file without _last_ suffix.
function DocSettings:getSidecarDir(doc_path)
    return doc_path:match("(.*)%.")..".sdr"
end

function DocSettings:getHistoryPath(fullpath)
    return history_dir .. "/[" .. fullpath:gsub("(.*/)([^/]+)","%1] %2"):gsub("/","#") .. ".lua"
end

function DocSettings:getPathFromHistory(hist_name)
    -- 1. select everything included in brackets
    local s = string.match(hist_name,"%b[]")
    -- 2. crop the bracket-sign from both sides
    -- 3. and finally replace decorative signs '#' to dir-char '/'
    return string.gsub(string.sub(s,2,-3),"#","/")
end

function DocSettings:getNameFromHistory(hist_name)
    -- at first, search for path length
    local s = string.len(string.match(hist_name,"%b[]"))
    -- and return the rest of string without 4 last characters (".lua")
    return string.sub(hist_name, s+2, -5)
end

function DocSettings:purgeDocSettings(doc_path)
    purgeDir(self:getSidecarDir(doc_path))
    os.remove(self:getHistoryPath(doc_path))
end

function DocSettings:open(docfile)
    -- TODO(zijiehe): Remove history_path, use only sidecar.
    local new = { data = {} }
    local ok, stored
    if docfile == ".reader" then
        -- we handle reader setting as special case
        new.history_file = DataStorage:getDataDir() .. "/settings.reader.lua"

        ok, stored = pcall(dofile, new.history_file)
    else
        new.history_file = self:getHistoryPath(docfile)

        local sidecar = self:getSidecarDir(docfile)
        if lfs.attributes(sidecar, "mode") ~= "directory" then
            lfs.mkdir(sidecar)
        end
        -- If there is a file which has a same name as the sidecar directory, or
        -- the file system is read-only, we should not waste time to read it.
        if lfs.attributes(sidecar, "mode") == "directory" then
            -- New sidecar file name is metadata.{file last suffix}.lua. So we
            -- can handle two files with only different suffixes.
            new.sidecar_file = sidecar.."/metadata."..
                               docfile:match(".*%.(.*)")..".lua"
        end

        new.candidates = {}
        -- New sidecar file
        table.insert(new.candidates, buildCandidate(new.sidecar_file));
        -- Legacy sidecar file
        table.insert(new.candidates, buildCandidate(
            self:getSidecarDir(docfile).."/"..
            docfile:match(".*%/(.*)")..".lua"))
        -- Legacy history folder
        table.insert(new.candidates, buildCandidate(new.history_file));
        -- Legacy kpdfview setting
        table.insert(new.candidates, buildCandidate(docfile..".kpdfview.lua"));
        table.sort(new.candidates, function(l, r)
                                       if l == nil then
                                           return false
                                       elseif r == nil then
                                           return true
                                       else
                                           return l[2] > r[2]
                                       end
                                   end)
        for _, k in pairs(new.candidates) do
            ok, stored = pcall(dofile, k[1])
            if ok then
                break
            end
        end
    end
    if ok and stored then
        new.data = stored
    end

    return setmetatable(new, { __index = DocSettings})
end

function DocSettings:readSetting(key)
    return self.data[key]
end

function DocSettings:saveSetting(key, value)
    self.data[key] = value
end

function DocSettings:delSetting(key)
    self.data[key] = nil
end

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
    local s_out = dump(self.data)
    os.setlocale('C', 'numeric')
    for _, f in pairs(serials) do
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
                    if k[1] ~= f then
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

function DocSettings:clear()
    if self.history_file then
        os.remove(self.history_file)
    end
    if self.sidecar_file then
        os.remove(self.sidecar_file)
    end
end

return DocSettings
