local android = require("android")
android.dl.library_path = android.dl.library_path .. ":" .. android.dir .. "/libs"

local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local C = ffi.C

-- check uri of the intent that starts this application
local file = android.getIntent()

if file ~= nil then
    android.LOGI("intent file path " .. file)
end

-- path to primary external storage partition
local path = android.getExternalStoragePath()

-- run koreader patch before koreader startup
pcall(dofile, path.."/koreader/patch.lua")

-- Set proper permission for binaries.
--- @todo Take care of this on extraction instead.
-- Cf. <https://github.com/koreader/koreader/issues/5347#issuecomment-529476693>.
android.execute("chmod", "755", "./sdcv")
android.execute("chmod", "755", "./tar")

-- set TESSDATA_PREFIX env var
C.setenv("TESSDATA_PREFIX", path.."/koreader/data", 1)

-- create fake command-line arguments
-- luacheck: ignore 121
if android.isDebuggable() then
    arg = {"-d", file or path}
else
    arg = {file or path}
end

dofile(android.dir.."/reader.lua")
