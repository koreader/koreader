--[[--
Allows applying developer patches while running KOReader.

The contents in `koreader/userpatches/` are applied on calling `userpatch.applyPatches(priority)`.
--]]--

local isAndroid, android = pcall(require, "android")

local userpatch =
    {   -- priorities for user patches,
        early_once = "0",  -- to be started early on startup (once after an update)
        early = "1",       -- to be started early on startup (always, but after an `early_once`)
        late = "2",        -- to be started after UIManager is ready (always)
                           -- 3-7 are reserved for later use
        before_exit = "8", -- to be started a bit before exit before settings are saved (always)
        on_exit = "9",     -- to be started right before exit (always)

        applyPatches = function(priority) end, -- to be overwritten, if the device allows it.
    }

if isAndroid and android.prop.flavor == "fdroid" then
    return userpatch -- allows to use applyPatches as a no-op on F-Droid flavor
end

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local DataStorage = require("datastorage")

-- the directory KOReader is installed in (and runs from)
local package_dir = lfs.currentdir()
-- the directory where KOReader stores user data (on SDL we may set `XDG_DOCUMENTS_DIR=~/koreader/`)
local data_dir = os.getenv("XDG_DOCUMENTS_DIR") or DataStorage:getDataDir() or package_dir

--- Run lua patches
-- Execution order order is alphanum-sort for humans version 4: `1-patch.lua` is executed before `10-patch.lua`
-- (see http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua)
-- string directory ... to scan through (flat no recursion)
-- string priority ... only files starting with `priority` followed by digits and a '-' will be processed.
-- return true if a patch was executed
local function runLiveUpdateTasks(dir, priority, update_once_pending, update_once_marker)
    if lfs.attributes(dir, "mode") ~= "directory" then
        return
    end

    local patches = {}
    for entry in lfs.dir(dir) do
        local mode = lfs.attributes(dir .. "/" .. entry, "mode")
        if entry and mode == "file" and entry:match("^" .. priority .. "%d*%-") then
            table.insert(patches, entry)
        end
    end

    if #patches == 0 then
        return -- nothing to do
    end

    local function addLeadingZeroes(d)
        local dec, n = string.match(d, "(%.?)0*(.+)")
        return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n)
    end
    local function sorting(a, b)
        return tostring(a):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#b)
            < tostring(b):gsub("%.?%d+", addLeadingZeroes)..("%3d"):format(#a)
    end

    table.sort(patches, sorting)

    for i, entry in ipairs(patches) do
        local fullpath = dir .. "/" .. entry
        if lfs.attributes(fullpath, "mode") == "file" then
            if fullpath:match("%.lua$") then -- execute patch-files first
                logger.info("Live update apply:", fullpath)
                local ok, err = pcall(dofile, fullpath)
                if not ok then
                    logger.warn("Live update", err)
                    if priority >= userpatch.late then -- Only show InfoMessage, when late during startup.
                        -- Only developers (advanced users) will use this mechanism.
                        -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                        local UIManager = require("ui/uimanager")
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{text = "Error loading patch:\n" .. fullpath}) -- no translate
                    end
                end
            end
        end
    end
    return true
end

--- This function applies lua patches from `/koreader/userpatches`
---- @string priority ... one of "early\_once", "early", "late", "before\_exit", "on\_exit"
function userpatch.applyPatches(priority)
    local patch_dir = data_dir .. "/userpatches"

    if priority == userpatch.early then
        -- Move an existing `koreader/patch.lua` to `koreader/userpatches/1-patch.lua` (-> will be excuted in `early`)
        if lfs.attributes(data_dir .. "/patch.lua", "mode") == "file" then
            if lfs.attributes(patch_dir, "mode") == nil then
                if not lfs.mkdir(patch_dir, "mode") then
                    logger.err("Live update error creating directory", patch_dir)
                end
            end
            os.rename(data_dir .. "/patch.lua", patch_dir .. "/" .. userpatch.early .. "-patch.lua")
        end
    end

    local update_once_marker = package_dir .. "/update_once.marker"
    local update_once_pending = lfs.attributes(update_once_marker, "mode") == "file"

    if priority >= userpatch.early or update_once_pending then
        local executed_something = runLiveUpdateTasks(patch_dir, priority)
        if executed_something and update_once_pending then
            -- Only delete update once marker if `early_once` updates have been applied.
            os.remove(update_once_marker) -- Prevent another execution on a further starts.
        end
    end
end

return userpatch
