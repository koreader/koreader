--[[--
This module contains miscellaneous helper functions for FileManager
]]

local Device = require("device")

local filemanagerutil = {}

function filemanagerutil.getDefaultDir()
    if Device:isKindle() then
        return "/mnt/us/documents"
    elseif Device:isKobo() then
        return "/mnt/onboard"
    elseif Device:isAndroid() then
        return "/sdcard"
    else
        return "."
    end
end

function filemanagerutil.abbreviate(path)
    local home_dir_name = G_reader_settings:readSetting("home_dir_display_name")
    if home_dir_name ~= nil then
        local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        local len = home_dir:len()
        local start = path:sub(1, len)
        if start == home_dir then
            return home_dir_name .. path:sub(len+1)
        end
    end
    return path
end

return filemanagerutil
