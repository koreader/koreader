local android = require("android")
android.dl.library_path = android.dl.library_path .. ":" .. android.dir .. "/libs"

local ffi = require("ffi")
local dummy = require("ffi/posix_h")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")

-- check uri of the intent that starts this application
local file = android.getIntent()

if file ~= nil then
    android.LOGI("intent file path " .. file)
end

-- path to primary external storage partition
local path = android.getExternalStoragePath()

-- execute user scripts before patch.lua

local shell_scripts = {}

local function getUserScripts(path)
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            local fullpath = path .. "/" .. entry
            if lfs.attributes(fullpath).mode ~= "directory" then
                if fullpath:match(".sh$") then  -- only include files ending in ".sh"
                    table.insert(shell_scripts, fullpath)
                end
            else
                getUserScripts(fullpath) -- recurse into next directory
            end
        end
    end
end

local function runUserScripts(scripts)
    for _, script in ipairs(scripts) do
        --local ret = os.execute("/system/bin/sh " .. script .. " " .. path .. "/koreader " .. android.dir)
        ret = android.execute("/system/bin/sh", script, path .. "/koreader", android_dir)
        if ret == 0 then
            android.LOGI("script " .. script  .. " executed succesfully")
        else
            android.LOGW("failed to execute " .. script)
        end
    end
end

-- scripts executed once after an update of koreader
local run_once_scripts = path .. "/koreader/scripts.afterupdate"
if lfs.attributes(run_once_scripts, "mode") == "directory" then
    local afterupdate_marker = android.dir .. "/afterupdate.marker"
    if lfs.attributes(afterupdate_marker, "mode") == "file" then
        getUserScripts(run_once_scripts)
        runUserScripts(shell_scripts)
        android.LOGI(string.format("Executed %d afterupdate scripts from %s", #shell_scripts, run_once_scripts))
        shell_scripts = {} -- clear table
        android.execute("rm", afterupdate_marker)
    end
end

-- scripts executed every start of koreader
local run_always_scripts = path .. "/koreader/scripts.always"
if lfs.attributes(run_always_scripts, "mode") == "directory" then
    getUserScripts(run_always_scripts)
    runUserScripts(shell_scripts)
    android.LOGI(string.format("Executed %d scripts from %s", #shell_scripts, run_always_scripts))
    shell_scripts = {} -- clear table
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
