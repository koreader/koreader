local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"
A.log_name = 'KOReader'

local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local C = ffi.C

-- check uri of the intent that starts this application
local file = A.getIntent()

if file ~= nil then
    A.LOGI("intent file path " .. file)
end

-- (Disabled, since we hide navbar on start now no need for this hack)
-- run koreader patch before koreader startup
pcall(dofile, "/sdcard/koreader/patch.lua")

-- set proper permission for sdcv
A.execute("chmod", "755", "./sdcv")
A.execute("chmod", "755", "./tar")
A.execute("chmod", "755", "./zsync")

-- set TESSDATA_PREFIX env var
C.setenv("TESSDATA_PREFIX", "/sdcard/koreader/data", 1)

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
