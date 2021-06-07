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

-- run user shell scripts or recursive migration of user data
local function runUserScripts(dir, migration, parent)
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            local fullpath = dir .. "/" .. entry
            local mode = lfs.attributes(fullpath).mode
            if mode == "file" and migration then
                if entry ~= "migrate" and not fullpath:match(".sh$") then
                    local destdir = parent and android.dir .. "/" .. parent or android.dir
                    -- we cannot create new directories on asset storage.
                    -- trying to do that crashes the VM with error=13, Permission Denied
                    android.execute("cp", fullpath, destdir .."/".. entry)
                end
            elseif mode == "file" and fullpath:match(".sh$") then
                android.execute("sh", fullpath, path .. "/koreader", android.dir)
            elseif mode == "directory" then
                runUserScripts(fullpath, migration, parent and parent .. "/" .. entry or entry) -- recurse into next directory
            end
        end
    end
end

if android.prop.runtimeChanges then
    -- run scripts once after an update of koreader,
    -- it can also trigger a recursive migration of user data
    local run_once_scripts = path .. "/koreader/scripts.afterupdate"
    if lfs.attributes(run_once_scripts, "mode") == "directory" then
        local afterupdate_marker = android.dir .. "/afterupdate.marker"
        if lfs.attributes(afterupdate_marker, "mode") ~= nil then
             if lfs.attributes(run_once_scripts .. "/migrate", "mode") ~= nil then
                 android.LOGI("after-update: running migration")
                 runUserScripts(run_once_scripts, true)
             else
                 android.LOGI("after-update: running shell scripts")
                 runUserScripts(run_once_scripts)
             end
             android.execute("rm", afterupdate_marker)
        end
    end
    -- scripts executed every start of koreader, no migration here
    local run_always_scripts = path .. "/koreader/scripts.always"
    if lfs.attributes(run_always_scripts, "mode") == "directory" then
        runUserScripts(run_always_scripts)
    end
    -- run koreader patch before koreader startup
    pcall(dofile, path.."/koreader/patch.lua")
end

-- set TESSDATA_PREFIX env var
C.setenv("TESSDATA_PREFIX", path.."/koreader/data", 1)

-- create fake command-line arguments
-- luacheck: ignore 121
if android.isDebuggable() then
    arg = {"-d", file}
else
    arg = {file}
end

dofile(android.dir.."/reader.lua")
