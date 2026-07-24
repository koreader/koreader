local android = require("android")

-- setup Lua paths, and ffi helper / override
require("setupkoenv")

local lfs = require("libs/libkoreader-lfs")
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

-- MuPDF looks up its fallback fonts (eg. noto/NotoSans-Regular.ttf, used to render the
-- HTML dictionary popup) relative to $FONTDIR, defaulting to "./fonts" when unset (see
-- base/thirdparty/mupdf/external_fonts.patch). Point it at android.dir/fonts, where the
-- app's bundled "fonts" dir gets extracted on install -- guaranteed present, no
-- external-storage access required.
C.setenv("FONTDIR", android.dir .. "/fonts", 1)

-- create fake command-line arguments
-- luacheck: ignore 121
if android.isDebuggable() then
    arg = {"-d", file}
else
    arg = {file}
end

dofile(android.dir.."/reader.lua")
