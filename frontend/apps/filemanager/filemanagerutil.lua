--[[--
This module contains miscellaneous helper functions for FileManager
]]

local Device = require("device")
local DocSettings = require("docsettings")
local util = require("ffi/util")
local _ = require("gettext")

local filemanagerutil = {}

function filemanagerutil.getDefaultDir()
    if Device:isAndroid() then
        return Device.external_storage
    elseif Device:isCervantes() then
        return "/mnt/public"
    elseif Device:isKindle() then
        return "/mnt/us/documents"
    elseif Device:isKobo() then
        return "/mnt/onboard"
    else
        return "."
    end
end

function filemanagerutil.abbreviate(path)
    if not path then return "" end
    if G_reader_settings:nilOrTrue("shorten_home_dir") then
        local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        if path == home_dir then
            return _("Home")
        end
        local len = home_dir:len()
        local start = path:sub(1, len)
        if start == home_dir then
            return path:sub(len+2)
        end
    end
    return path
end

-- Purge doc settings in sidecar directory,
function filemanagerutil.purgeSettings(file)
    local file_abs_path = util.realpath(file)
    if file_abs_path then
        os.remove(DocSettings:getSidecarFile(file_abs_path))
        -- Also remove backup, otherwise it will be used if we re-open this document
        -- (it also allows for the sidecar folder to be empty and removed)
        os.remove(DocSettings:getSidecarFile(file_abs_path)..".old")
        -- If the sidecar folder is empty, os.remove() can delete it.
        -- Otherwise, the following statement has no effect.
        os.remove(DocSettings:getSidecarDir(file_abs_path))
    end
end

-- Remove from history (and update lastfile to an existing file)
-- if autoremove_deleted_items_from_history is enabled
function filemanagerutil.removeFileFromHistoryIfWanted(file)
    if G_reader_settings:readSetting("autoremove_deleted_items_from_history") then
        local readhistory = require("readhistory")
        readhistory:removeItemByPath(file)
        filemanagerutil.ensureLastFileExists()
    end
end

-- Update lastfile setting to the most recent one in history
-- that still exists
function filemanagerutil.ensureLastFileExists()
    local last_existing_file = nil
    local readhistory = require("readhistory")
    for i=1, #readhistory.hist do
        if lfs.attributes(readhistory.hist[i].file, "mode") == "file" then
            last_existing_file = readhistory.hist[i].file
            break
        end
    end
    G_reader_settings:saveSetting("lastfile", last_existing_file)
end

return filemanagerutil
