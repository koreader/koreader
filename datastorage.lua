--- Used for getting the directory paths that KoReader uses.
-- @usage local DataStorage = require("datastorage")
-- @module datastorage

-- need low-level mechanism to detect android to avoid recursive dependency
local isAndroid, android = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")

local DataStorage = {}

local data_dir
local full_data_dir

--- Gets the path where configuration/data is stored for KoReader.
-- @treturn string Directory path
function DataStorage:getDataDir()
    if data_dir then return data_dir end

    if os.getenv("KO_HOME") then
        data_dir = os.getenv("KO_HOME")
    elseif isAndroid then
        data_dir = android.getExternalStoragePath() .. "/koreader"
    elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
        local app_id = os.getenv("APP_ID")
        local package_name = app_id:match("^(.-)_")
        -- confined ubuntu app has write access to this dir
        data_dir = string.format("%s/%s", os.getenv("XDG_DATA_HOME"), package_name)
    elseif os.getenv("APPIMAGE") or os.getenv("FLATPAK") or os.getenv("KO_MULTIUSER") then
        if os.getenv("XDG_CONFIG_HOME") then
            data_dir = string.format("%s/%s", os.getenv("XDG_CONFIG_HOME"), "koreader")
            if lfs.attributes(os.getenv("XDG_CONFIG_HOME"), "mode") ~= "directory" then
                lfs.mkdir(os.getenv("XDG_CONFIG_HOME"))
            end
        else
            local user_rw = string.format("%s/%s", os.getenv("HOME"), jit.os == "OSX" and "Library/Application Support" or ".config")
            if lfs.attributes(user_rw, "mode") ~= "directory" then
                lfs.mkdir(user_rw)
            end
            data_dir = string.format("%s/%s", user_rw, "koreader")
        end
    else
        data_dir = "."
    end
    if lfs.attributes(data_dir, "mode") ~= "directory" then
        local ok, err = lfs.mkdir(data_dir)
        if not ok then error(err .. " " .. data_dir) end
    end

    return data_dir
end

--- (Deprecated) Gets the path of where legacy/obsolete sidecar files are stored.
-- @treturn string Directory path
function DataStorage:getHistoryDir()
    return self:getDataDir() .. "/history"
end

--- Gets the path where @{luasettings} should be stored.
-- @treturn string Directory path
function DataStorage:getSettingsDir()
    return self:getDataDir() .. "/settings"
end

--- Gets the path of where @{docsettings}
-- (sidecar files) should be stored although this directory isn't guaranteed to exist.
-- @treturn string Directory path
function DataStorage:getDocSettingsDir()
    return self:getDataDir() .. "/docsettings"
end

--- Gets the path of where @{docsettings}
-- (sidecar files) should be stored although this directory isn't guaranteed to exist.
-- This is used instead of `DataStorage:getDocSettingsDir` when hashing is enabled.
-- @treturn string Directory path
function DataStorage:getDocSettingsHashDir()
    return self:getDataDir() .. "/hashdocsettings"
end

--- Gets the full configuration/data path.
-- @treturn string Directory path (e.g /mnt/onboard/.adds/koreader)
function DataStorage:getFullDataDir()
    if full_data_dir then return full_data_dir end

    if string.sub(self:getDataDir(), 1, 1) == "/" then
        full_data_dir = self:getDataDir()
    elseif self:getDataDir() == "." then
        full_data_dir = lfs.currentdir()
    end

    return full_data_dir
end

local function initDataDir()
    local sub_data_dirs = {
        "cache",
        "clipboard",
        "data",
        "data/dict",
        "data/tessdata",
        -- "docsettings", -- created when needed
        -- "hashdocsettings", -- created when needed
        -- "history", -- legacy/obsolete sidecar files
        "ota",
        -- "patches", -- must be created manually by the interested user
        "plugins",
        "screenshots",
        "settings",
        "styletweaks",
    }
    local datadir = DataStorage:getDataDir()
    for _, dir in ipairs(sub_data_dirs) do
        local sub_data_dir = string.format("%s/%s", datadir, dir)
        if lfs.attributes(sub_data_dir, "mode") ~= "directory" then
            lfs.mkdir(sub_data_dir)
        end
    end
end

initDataDir()

return DataStorage
