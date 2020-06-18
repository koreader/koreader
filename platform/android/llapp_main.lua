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

-- execute user scripts before patch.lua
local lfs = require("libs/libkoreader-lfs")

local user_dir = path .. "/koreader"
local afterupdate_marker = android.dir .. "/afterupdate.marker"
local run_once_scripts = user_dir .. "/scripts.afterupdate"
local run_always_scripts = user_dir .. "/scripts.always"

local shell_scripts = {}

local function getUserScripts(path)
    local ret = lfs.attributes(path)
    if ret.mode == "directory" then
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
end

local function runUserScripts(scripts)
    for _, script in ipairs(scripts) do
        local ret = os.execute("/system/bin/sh " .. script .. " " .. user_dir .. " " .. android.dir)
        if ret == 0 then
            android.LOGI("script " .. script  .. " executed succesfully")
        else
            android.LOGW("failed to execute " .. script)
        end
    end
end

-- scripts executed once after an update of koreader
android.LOGI("checking and running scripts on update, if necessary.")
if lfs.attributes(run_once_scripts, "mode") == "directory" then
    if lfs.attributes(afterupdate_marker, "mode") == "file" then
        shell_scripts = {} -- clear table
        getUserScripts(run_once_scripts)
        runUserScripts(shell_scripts)
        android.LOGI(string.format("Executed %d afterupdate scripts from %s", #shell_scripts, run_once_scripts))
        android.execute("/system/bin/rm", afterupdate_marker)
        android.LOGI("Afterupdate marker " .. afterupdate_marker .." removed") 
    end
end

if lfs.attributes(run_always_scripts, "mode") == "directory" then
    shell_scripts = {} -- clear table
    getUserScripts(run_always_scripts)
    runUserScripts(shell_scripts)
    android.LOGI(string.format("Executed %d scripts from %s", #shell_scripts, run_always_scripts))
end

shell_scripts = {} --clean up

-- run koreader patch before koreader startup
pcall(dofile, path.."/koreader/patch.lua")

-- Set proper permission for binaries.
--- @todo Take care of this on extraction instead.
-- Cf. <https://github.com/koreader/koreader/issues/5347#issuecomment-529476693>.
android.execute("/system/bin/chmod", "755", "./sdcv")
android.execute("/system/bin/chmod", "755", "./tar")

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
