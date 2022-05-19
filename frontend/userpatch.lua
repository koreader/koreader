--[[--
Allows applying developer patches and shell scripts while running KOReader.

The contents in `koreader/userpatches/` are applied on calling `userpatch.applyPatches(priority)`.
--]]--

local isAndroid, android = pcall(require, "android")

local userpatch =
    {   -- priorities for user patches,
        early_afterupdate = "0", -- to be started early on startup (once after an update)
        early = "1",             -- to be started early on startup (always, but after an `early_afterupdate`)
        late = "2",              -- to be started after UIManager is ready (always)
                                 -- 3-7 are reserved for later use
        before_exit = "8",       -- to be started a bit before exit before settings are saved (always)
        on_exit = "9",           -- to be started right before exit (always)

        applyPatches = function(priority) end, -- to be overwritten, if the device allows it.
    }

if isAndroid and android.prop.flavor == "fdroid" then
    return userpatch
end

------------------------------------------------------------------------------------

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

if home_dir == nil or package_dir == nil then
    return userpatch -- live patching is not supported
end

logger.info("Live update using package_dir:", package_dir, "; home_dir:", home_dir)

-- A wrapper for os.execute, can not use ffi/util early before setupkoenv.
local function execute(...)
    local command = {}
    for i, v in ipairs({...}) do
        table.insert(command, "'")
        table.insert(command, tostring(v))
        table.insert(command, "' ")
    end
    return os.execute(table.concat(command))
end

--- Run user shell scripts or lua patches
-- Execution order order is alphanum-sort for humans version 4:
-- http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
-- string directory ... to scan through
-- string priority ... only files starting with `priority` followed by digits and a '-' will be processed.
-- string parent ... parent directory
local function runLiveUpdateTasks(dir, priority)
    local patches = {}
    for entry in lfs.dir(dir) do
        local mode = lfs.attributes(dir .. "/" .. entry, "mode")
        if entry and mode == "file" and entry:match("^" .. priority .. "%d*%-") then
            table.insert(patches, entry)
        end
    end

    local function addLeadingZeroes(d)
        local dec, n = string.match(d, "(%.?)0*(.+)")
        return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n)
    end
    local sorting = function(a, b)
        return tostring(a):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#b)
            < tostring(b):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#a)
    end

    table.sort(patches, sorting)

    for i, entry in ipairs(patches) do
        local fullpath = dir .. "/" .. entry
        local mode = lfs.attributes(fullpath, "mode")
        if mode == "file" then
            if fullpath:match("%.sh$") then -- execute shell scripts
                logger.info("Live update apply:", fullpath)
                local retval = execute("sh", fullpath, home_dir .. "/koreader", package_dir)
                logger.info("Live update script returned:", retval)
            elseif fullpath:match("%.lua$") then -- execute patch-files
                logger.info("Live update apply:", fullpath)
                local ok, err = pcall(dofile, fullpath)
                if not ok then
                    logger.warn("Live update", err)
                    if priority >= userpatch.late then -- Only show InfoMessage, when late during startup.
                        -- Only developers (advanced users) will use this mechanism.
                        -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                        local UIManager = require("ui/uimanager")
                        local _ = require("gettext")
                        local T = require("ffi/util").template
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{text = T(_("Error loading patch:\n%1"), fullpath)})
                    end
                end
            end
        end
    end
end

--- This function executes sripts and applies lua patches from `/koreader/userscripts`
---- @string priority ... one of "early\_afterupdate", "early", "late", "before\_exit", "on\_exit"
function userpatch.applyPatches(priority)
    -- patches and scripts get applied at every start of koreader, no migration here
    local patch_dir = home_dir .. "/koreader/userpatches"

    if priority == userpatch.early then
        -- Move an existing `koreader/patch.lua` to `koreader/userpatches/0000-patch.lua` (->will be excuted in early_afterupdate)
        if lfs.attributes(home_dir .. "/koreader/patch.lua", "mode") == "file" then
            if lfs.attributes(patch_dir, "mode") == nil then
                if not lfs.mkdir(patch_dir, "mode") then
                    logger.err("Live update error creating directory", patch_dir)
                end
            end
            os.rename(home_dir .. "/koreader/patch.lua", patch_dir .. "/0000-patch.lua")
        end
    end

    local first_start_after_update
    local afterupdate_marker = package_dir .. "/koreader/afterupdate.marker"
    if lfs.attributes(afterupdate_marker, "mode") == "file" then
        first_start_after_update = true
        os.remove(afterupdate_marker) -- Prevent another execution on a further starts.
    end

    if priority >= userpatch.early or first_start_after_update then
        runLiveUpdateTasks(patch_dir, priority)
    end
end

return userpatch
