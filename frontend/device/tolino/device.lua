-- local Generic = require("device/generic/device")
-- local Geom = require("ui/geometry")
-- local WakeupMgr = require("device/wakeupmgr")
-- local ffiUtil = require("ffi/util")
-- local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
-- local util = require("util")
-- local _ = require("gettext")
local A, android = pcall(require, "android")  -- luacheck: ignore
local AndroidDevice = require("device/android/device")

-- We're going to need a few <linux/fb.h> & <linux/input.h> constants...
-- local ffi = require("ffi")
-- local C = ffi.C
-- require("ffi/linux_fb_h")
-- require("ffi/linux_input_h")
-- require("ffi/posix_h")

local function yes() return true end
local function no() return false end

local TolinoDevice = AndroidDevice:new{
    model = "Tolino"
}

function TolinoDevice:init()
    AndroidDevice.init(self)
    self.input.event_map = require("device/tolino/event_map")
end

-- Tolino Vision 5
local TolinoVision5 = TolinoDevice:new{
    model = "Tolino_vision_5",
    hasEinkScreen = yes
}

if android.prop.hardwareType == "E70K00" then
    return TolinoVision5
else
    logger.warn("unrecognized Tolino model ".. android.prop.product.hardwareType.. " using android generic")
    return AndroidDevice
end
