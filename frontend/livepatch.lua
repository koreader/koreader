--[[--
Allows to apply developer patches on KOReader startup.
--]]--

local Device = require("device")

if Device:canApplyPatches() then -- check if not FDroid flavor
    local util = require("util")
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")

    local home_dir = Device.home_dir -- on Android this is the path on the external storage
    local package_dir = Device.package_dir or home_dir -- this is the directory KOReader is installed in

    if home_dir == nil then
        return -- not supported
    end

    -- run user shell scripts or recursive migration of user data
    local function runLiveUpdateTasks(dir, migration, parent)
        if not parent then
            logger.info("Live update directory found:", dir)
        end
        for entry in lfs.dir(dir) do
            if entry and entry ~= "." and entry ~= ".." then
                local fullpath = dir .. "/" .. entry
                local mode = lfs.attributes(fullpath).mode
                if mode == "file" and migration then
                    if entry ~= "migrate" and not fullpath:match("%.sh$") then
                        local destdir = parent and package_dir .. "/" .. parent or package_dir
                        -- we cannot create new directories on asset storage.
                        -- trying to do that crashes the VM with error=13, Permission Denied
                        util.execute("cp", fullpath, destdir .. "/" .. entry)
                    end
                elseif mode == "file" and fullpath:match("%.sh$") then
                    util.execute("sh", fullpath, home_dir .. "/koreader", package_dir)
                elseif mode == "file" and fullpath:match("%.lua$") then
                    local ok, err = pcall(dofile, fullpath)
                    if not ok then
                        -- Only developers (advanced users) will use this mechanism.
                        -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                        logger.warn("Live update", err)
                        local UIManager = require("ui/uimanager")
                        local _ = require("gettext")
                        local T = require("ffi/util").template
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{text = T(_("Error loading patch:\n%1"), fullpath)})
                    else
                        logger.info("Live update applied:", fullpath)
                    end
                elseif mode == "directory" then
                    runLiveUpdateTasks(fullpath, migration, parent and parent .. "/" .. entry or entry) -- recurse into next directory
                end
            end
        end
    end

    -- run scripts once after an update of koreader,
    -- it can also trigger a recursive migration of user data
    local run_once_scripts = home_dir .. "/koreader/scripts.afterupdate"
    if lfs.attributes(run_once_scripts, "mode") == "directory" then
        local afterupdate_marker = package_dir .. "/afterupdate.marker"
        if lfs.attributes(afterupdate_marker, "mode") ~= nil then
            if lfs.attributes(run_once_scripts .. "/migrate", "mode") ~= nil then
                logger.info("after-update: running migration")
                runLiveUpdateTasks(run_once_scripts, true)
            else
                logger.info("after-update: running shell scripts")
                runLiveUpdateTasks(run_once_scripts)
            end
            util.execute("rm", afterupdate_marker)
        end
    end

    -- scripts executed every start of koreader, no migration here
    local run_always_scripts = home_dir .. "/koreader/scripts.always"
    if lfs.attributes(run_always_scripts, "mode") == "directory" then
        runLiveUpdateTasks(run_always_scripts)
    end
    -- patches applied at every start of koreader, no miration here
    local patch_dir = home_dir .. "/koreader/patches"
    if lfs.attributes(patch_dir, "mode") == "directory" then
        runLiveUpdateTasks(patch_dir)
    end
end
