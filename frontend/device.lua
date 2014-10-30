local isAndroid, android = pcall(require, "android")
local util = require("ffi/util")

local function probeDevice()
    if util.isEmulated() then
        return require("device/emulator/device")
    end

    if isAndroid then
        return require("device/android/device")
    end

    local kindle_sn = io.open("/proc/usid", "r")
    if kindle_sn then
        kindle_sn:close()
        return require("device/kindle/device")
    end

    local kg_test_fd = lfs.attributes("/bin/kobo_config.sh")
    if kg_test_fd then
        return require("device/kobo/device")
    end

    error("did not find a hardware abstraction for this platform")
end

local dev = probeDevice()
dev:init()
return dev
