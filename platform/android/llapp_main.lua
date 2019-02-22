local A = require("android")
A.dl.library_path = A.dl.library_path .. ":" .. A.dir .. "/libs"
A.log_name = 'KOReader'

local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    char *getenv(const char *name);
    int putenv(const char *envvar);
]]

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
C.putenv("TESSDATA_PREFIX=/sdcard/koreader/data")

-- create fake command-line arguments
arg = {"-d", file or "/sdcard"}
dofile(A.dir.."/reader.lua")
