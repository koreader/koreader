local android = require("android")
android.dl.library_path = android.dl.library_path .. ":" .. android.dir .. "/libs"

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

-- run user shell scripts
local function runUserScripts(dir)
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local fullpath = dir .. "/" .. entry
            local mode = lfs.attributes(fullpath).mode
            if mode == "file" and fullpath:match(".sh$") then
                android.execute("sh", fullpath, path .. "/koreader", android.dir)
            elseif mode == "directory" then
                runUserScripts(fullpath) -- recurse into next directory
            end
        end
    end
end

-- scripts executed once after an update of koreader
local run_once_scripts = path .. "/koreader/scripts.afterupdate"
if lfs.attributes(run_once_scripts, "mode") == "directory" then
    local afterupdate_marker = android.dir .. "/afterupdate.marker"
    if lfs.attributes(afterupdate_marker, "mode") ~= nil then
         runUserScripts(run_once_scripts)
         android.execute("rm", afterupdate_marker)
     end
 end

-- scripts executed every start of koreader
local run_always_scripts = path .. "/koreader/scripts.always"
if lfs.attributes(run_always_scripts, "mode") == "directory" then
    runUserScripts(run_always_scripts)
 end
 
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
