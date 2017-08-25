-- need low-level mechnism to detect android to avoid recursive dependency
local isAndroid, android = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")

local DataStorage = {}

local data_dir
function DataStorage:getDataDir()
    if data_dir then return data_dir end

    if isAndroid then
        data_dir = android.externalStorage() .. "/koreader"
    elseif os.getenv("UBUNTU_APPLICATION_ISOLATION") then
        local app_id = os.getenv("APP_ID")
        local package_name = app_id:match("^(.-)_")
        -- confinded ubuntu app has write access to this dir
        data_dir = os.getenv("XDG_DATA_HOME") .. "/" .. package_name
    else
        data_dir = "."
    end
    if lfs.attributes(data_dir, "mode") ~= "directory" then
        lfs.mkdir(data_dir)
    end

    return data_dir
end

function DataStorage:getHistoryDir()
    return self:getDataDir() .. "/history"
end

function DataStorage:getSettingsDir()
    return self:getDataDir() .. "/settings"
end

local function initDataDir()
    local sub_data_dirs = {
        "cache", "clipboard", "data", "data/dict", "history",
        "ota", "screenshots", "settings",
    }
    for _, dir in ipairs(sub_data_dirs) do
        local sub_data_dir = DataStorage:getDataDir() .. "/" .. dir
        if lfs.attributes(sub_data_dir, "mode") ~= "directory" then
            lfs.mkdir(sub_data_dir)
        end
    end
end

initDataDir()

return DataStorage
