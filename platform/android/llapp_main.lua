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

-- create fake command-line arguments
-- luacheck: ignore 121
if android.isDebuggable() then
    arg = {"-d", file}
else
    arg = {file}
end

dofile(android.dir.."/reader.lua")
