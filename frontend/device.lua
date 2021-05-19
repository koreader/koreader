local isAndroid, _ = pcall(require, "android")
local lfs = require("libs/libkoreader-lfs")
local util = require("ffi/util")

local function probeDevice()
    if isAndroid then
        util.noSDL()
        return require("device/android/device")
    end

    local kindle_test_stat = lfs.attributes("/proc/usid")
    if kindle_test_stat then
        util.noSDL()
        return require("device/kindle/device")
    end

    local kobo_test_stat = lfs.attributes("/bin/kobo_config.sh")
    if kobo_test_stat then
        util.noSDL()
        return require("device/kobo/device")
    end

    local pbook_test_stat = lfs.attributes("/ebrmain")
    if pbook_test_stat then
        util.noSDL()
        return require("device/pocketbook/device")
    end

    local remarkable_test_stat = lfs.attributes("/usr/bin/xochitl")
    if remarkable_test_stat then
        util.noSDL()
        return require("device/remarkable/device")
    end

    local sony_prstux_test_stat = lfs.attributes("/etc/PRSTUX")
    if sony_prstux_test_stat then
        util.noSDL()
        return require("device/sony-prstux/device")
    end

    local cervantes_test_stat = lfs.attributes("/usr/bin/ntxinfo")
    if cervantes_test_stat then
        util.noSDL()
        return require("device/cervantes/device")
    end

    -- add new ports here:
    --
    -- if --[[ implement a proper test instead --]] false then
    --     util.noSDL()
    --     return require("device/newport/device")
    -- end

    if util.isSDL() then
        return require("device/sdl/device")
    end

    error("Could not find hardware abstraction for this platform. If you are trying to run the emulator, please ensure SDL is installed.")
end

local dev = probeDevice()
dev:init()
return dev
