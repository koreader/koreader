local util = require("ffi/util")
local Version = require("version")

local function probeDevice()
    local platform = Version:getCurrentPlatform()
    if platform then
        if platform:sub(1, #"android") == "android" then
            return require("device/android/device")
        elseif platform:sub(1, #"cervantes") == "cervantes" then
            return require("device/cervantes/device")
        elseif platform:sub(1, #"kindle") == "kindle" then
            return require("device/kindle/device")
        elseif platform:sub(1, #"kobo") == "kobo" then
            return require("device/kobo/device")
        elseif platform:sub(1, #"bookeen") == "bookeen" then
            return require("device/bookeen/device")
        elseif platform:sub(1, #"pocketbook") == "pocketbook" then
            return require("device/pocketbook/device")
        elseif platform:sub(1, #"sony-prstux") == "sony-prstux" then
            return require("device/sony-prstux/device")
        end
    end
    if util.loadSDL3() then
        return require("device/sdl/device")
    end
    error("Could not find hardware abstraction for this platform. If you are trying to run the emulator, please ensure SDL is installed.")
end

local dev = probeDevice()
dev:init()
return dev
