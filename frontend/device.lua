local isAndroid, android = pcall(require, "android")
local util = require("ffi/util")

local function probeDevice()
    if util.isSDL() then
        return require("device/sdl/device")
    end

    if isAndroid then
        return require("device/android/device")
    end

    local kindle_sn = io.open("/proc/usid", "r")
    if kindle_sn then
        kindle_sn:close()
        return require("device/kindle/device")
    end

    local kg_test_stat = lfs.attributes("/bin/kobo_config.sh")
    if kg_test_stat then
        return require("device/kobo/device")
    end

    local pbook_test_stat = lfs.attributes("/ebrmain")
    if pbook_test_stat then
        return require("device/pocketbook/device")
    end

    -- add new ports here:
    if --[[ implement a proper test instead --]] false then
        return require("device/newport/device")
    end

    error("did not find a hardware abstraction for this platform")
end

local dev = probeDevice()
dev:init()
return dev
