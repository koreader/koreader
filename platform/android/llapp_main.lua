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

local android = require("android")
local lfs = require("libs/libkoreader-lfs")

local shell_scripts = {}

local function getUserScripts(path)
    shell_scripts = {} -- zero list, as getUserScripts could be called multiple times
    local ret = lfs.attributes(path)
    if ret == nil then
        android.LOGI("no script folder " .. path .. " found!")
        return
    end
    
    if ret.mode == "directory" then
        android.LOGI("script folder " .. path .. " found!")
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                local fullpath = path .. "/" .. entry
                if lfs.attributes(fullpath).mode ~= "directory" then
                    if fullpath:sub(-#".sh") == ".sh" then  -- only include files ending in ".sh"
                        table.insert(shell_scripts, fullpath)
                    end
                else
                    getUserScripts(path) -- recurse into next directory
                end
            end
        end
    end
end


-- scripts executed once after an update of koreader
local user_dir = android.getExternalStoragePath() .. "/koreader"
local afterupdate_marker = android.dir .. "/scripts.afterupdate"

android.LOGI("checking update_marker: " .. afterupdate_marker)
local start_afterupdate = lfs.attributes( afterupdate_marker )
if start_afterupdate == nil then
    getUserScripts(user_dir .. "/scripts.afterupdate" )
    android.LOGI("running after an update of koreader:")
    for _, script in ipairs(shell_scripts) do
        local ret = os.execute("/system/bin/sh " .. script .. " " .. user_dir .. " " .. android.dir   )
        if ret == 0 then
            android.LOGI("script " .. script  .. " executed succesfully")
        else
            android.LOGW("failed to execute " .. script)
        end
    end
    android.LOGI("setting afterupdate marker")
    android.execute("touch", afterupdate_marker )
end

getUserScripts(user_dir .. "/scripts.always" )
android.LOGI("running always after start:")
for _, script in ipairs(shell_scripts) do
    local ret = os.execute("/system/bin/sh " .. script .. " " .. user_dir .. " " .. android.dir   )
    if ret == 0 then
        android.LOGI("script " .. script  .. " executed succesfully")
    else
        android.LOGW("failed to execute " .. script)
    end
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
