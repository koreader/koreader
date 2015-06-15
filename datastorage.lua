-- need low-level mechnism to detect android to avoid recursive dependency
local isAndroid = pcall(require, "android")

local DataStorage = {}

function DataStorage:getDataDir()
    if isAndroid then
        return "/sdcard/koreader/"
    else
        return "./"
    end
end

return DataStorage
