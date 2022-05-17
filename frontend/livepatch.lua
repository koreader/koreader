--[[--
Allows to apply developer patches, shell scripts an file migration during KOReader startup.

Process the contents of `koreader/scripts.always` (and `koreader/scripts.afterupdate` after an update) and apply
`koreader/patches/master-patch.lua` on calling `livepatch.eecuteScriptsAndMigrate()`.

The contents in `koreader/patches` are applied on calling `livepatch.applyPatches()`.
--]]--

local isAndroid, android = pcall(require, "android")

local livepatch = {}

-- The following functins will be overwritten, if the device allows it.
function livepatch.applyPatches() end
function livepatch.executeScriptsAndMigrate() end

if not (isAndroid and android.prop.flavor == "fdroid") then
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")

    -- We can not use util.lua so early during startup.
    local function removeTrailingSlash(str)
        if str:sub(-1, -1) == "/" then
            return str:sub(1, -2)
        end
        return str
    end
    -- the directory KOReader is installed in (and runs from)
    local package_dir = removeTrailingSlash(lfs.currentdir():match("^.*/"))
    -- the directory where KOReader stores user data (on SDL we may set `XDG_DOCUMENTS_DIR=~/koreader/`)
    local home_dir = removeTrailingSlash(isAndroid and android.getExternalStoragePath() or
        os.getenv("XDG_DOCUMENTS_DIR") or package_dir)

    logger.info("Live update trying package_dir:", package_dir, "; home_dir:", home_dir)

    if home_dir == nil or package_dir == nil then
        return livepatch -- live patching is not supported
    end

    -- A wrapper for os.execute, can not use ffi/util early before setupkoenv.
    local function execute(...)
        local command = ""
        for i, v in ipairs({...}) do
            command = command .. "'" .. tostring(v) .. "' "
        end
        os.execute(command)
    end

    -- Run user shell scripts or recursive migration of user data.
    -- Skip the special files `migrate` and `master-patch.lua`.
    -- string directory ... to scan through
    -- bool bare ... don't use UIManager and Co.
    -- bool migration ... migrate directory contents
    -- string parent ... parent directory
    local function runLiveUpdateTasks(dir, bare, migration, parent)
        if not parent then
            logger.info("Live update directory found:", dir)
        end
        for entry in lfs.dir(dir) do
            if entry and entry ~= "." and entry ~= ".." then
                local fullpath = dir .. "/" .. entry
                local mode = lfs.attributes(fullpath).mode
                if mode == "file" and migration then -- copy any file except `migrate` and shell scripts
                    if entry ~= "migrate" and not fullpath:match("%.sh$") then
                        local destdir = parent and package_dir .. "/" .. parent or package_dir
                        -- we cannot create new directories on asset storage.
                        -- trying to do that crashes the VM with error=13, Permission Denied
                        execute("cp", fullpath, destdir .. "/" .. entry)
                    end
                elseif mode == "file" and fullpath:match("%.sh$") then -- execute shell scripts
                    execute("sh", fullpath, home_dir .. "/koreader", package_dir)
                elseif mode == "file" and fullpath:match("%.lua$")
                    and not fullpath:match("master%-patch%.lua$") then -- execute patch-files
                    local ok, err = pcall(dofile, fullpath)
                    if not ok then
                        logger.warn("Live update", err)
                        if not bare then -- Only show InfoMessage, when late during startup.
                            -- Only developers (advanced users) will use this mechanism.
                            -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                            local UIManager = require("ui/uimanager")
                            local _ = require("gettext")
                            local baseUtil = require("ffi/util")
                            local T = baseUtil.template
                            local InfoMessage = require("ui/widget/infomessage")
                            UIManager:show(InfoMessage:new{text = T(_("Error loading patch:\n%1"), fullpath)})
                        end
                    else
                        logger.info("Live update applied:", fullpath)
                    end
                elseif mode == "directory" then -- recurse deeper
                    -- recurse into next directory
                    runLiveUpdateTasks(fullpath, bare, migration, parent and parent .. "/" .. entry or entry)
                end
            end
        end
    end

    --- This function works on the contents of `home_dir/koreader/patches` (except `master-patch.lua`)
    function livepatch.applyPatches()
        -- patches, scripts and migration get applied at every start of koreader, no migration here
        local patch_dir = home_dir .. "/koreader/patches"
        if lfs.attributes(patch_dir, "mode") == "directory" then
            runLiveUpdateTasks(patch_dir, false)
        end
    end

    --- This function migrates user files, executes shell scripts and patch files (except `master-patch.lua`) in
    -- `home_dir/koreader/[scripts.afterupdate|scripts.always`.
    -- If an older `patch.lua` is found it is moved to `patches/master-patch.lua`. This has to be done here,
    -- as onetime_migration gets called to late.
    function livepatch.executeScriptsAndMigrate()
        local run_once_scripts = home_dir .. "/koreader/scripts.afterupdate"
        if lfs.attributes(run_once_scripts, "mode") == "directory" then
            local afterupdate_marker = package_dir .. "/koreader/afterupdate.marker"
            if lfs.attributes(afterupdate_marker, "mode") == "file" then
                local migrate = lfs.attributes(run_once_scripts .. "/migrate", "mode") ~= nil
                logger.info("after-update: running", migrate and "migration" or "shell scripts")
                runLiveUpdateTasks(run_once_scripts, true, migrate)
                execute("rm", afterupdate_marker) -- Prevent another execution on a further starts.
            end
        end

        -- scripts and patches executed every start of koreader, no migration here
        local run_always_scripts = home_dir .. "/koreader/scripts.always"
        if lfs.attributes(run_always_scripts, "mode") == "directory" then
            runLiveUpdateTasks(run_always_scripts, true)
        end

        -- Move an existing `koreader/patch.lua` to `koreader/patches/master-patch.lua`
        if lfs.attributes(home_dir .. "/koreader/patch.lua", "mode") == "file" then
            execute("mv", home_dir .. "/koreader/patch.lua", home_dir .. "/koreader/patches/master-patch.lua")
        end
        -- run `koreader/patches/master-patch.lua`
        pcall(dofile, home_dir .. "/koreader/patches/master-patch.lua")
    end
end

return livepatch
