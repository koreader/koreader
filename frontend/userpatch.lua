--[[--
Allows applying developer patches while running KOReader.

The contents in `koreader/patches/` are applied on calling `userpatch.applyPatches(priority)`.
--]]--

local isAndroid, android = pcall(require, "android")

local userpatch = {
    -- priorities for user patches,
    early_once = "0",  -- to be started early on startup (once after an update)
    early = "1",       -- to be started early on startup (always, but after an `early_once`)
    late = "2",        -- to be started after UIManager is ready (always)
                       -- 3-7 are reserved for later use
    before_exit = "8", -- to be started a bit before exit before settings are saved (always)
    on_exit = "9",     -- to be started right before exit (always)

    -- hash table for patch execution status
    -- key: name of the patch
    -- value: true (success), false (failure), nil (not executed)
    execution_status = {},

    -- the patch function itself
    applyPatches = function(priority) end, -- to be overwritten, if the device allows it.
}

if isAndroid and android.prop.flavor == "fdroid" then
    return userpatch -- allows to use applyPatches as a no-op on F-Droid flavor
end

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local sort = require("sort")
local DataStorage = require("datastorage")

-- the directory KOReader is installed in (and runs from)
local package_dir = lfs.currentdir()
-- the directory where KOReader stores user data
local data_dir = DataStorage:getDataDir()

--- Run lua patches
-- Execution order order is alphanum-sort for humans version 4: `1-patch.lua` is executed before `10-patch.lua`
-- (see http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua)
-- string directory ... to scan through (flat no recursion)
-- string priority ... only files starting with `priority` followed by digits and a '-' will be processed.
-- return true if a patch was executed
local function runUserPatchTasks(dir, priority)
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

    table.sort(patches, sort.natsort_cmp())

    for i, entry in ipairs(patches) do
        local fullpath = dir .. "/" .. entry
        if lfs.attributes(fullpath, "mode") == "file" then
            if fullpath:match("%.lua$") then -- execute patch-files first
                logger.info("Applying patch:", fullpath)
                local ok, err = pcall(dofile, fullpath)
                userpatch.execution_status[entry] = ok
                if not ok then
                    logger.warn("Patching failed:", err)
                    -- Only show InfoMessage, when UIManager is working
                    if priority >= userpatch.late and priority < userpatch.before_exit then
                        -- Only developers (advanced users) will use this mechanism.
                        -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                        local UIManager = require("ui/uimanager")
                        local InfoMessage = require("ui/widget/infomessage")
                        UIManager:show(InfoMessage:new{text = "Error applying patch:\n" .. fullpath}) -- no translate
                    end
                end
            end
        end
    end
    return true
end

--- This function applies lua patches from `/koreader/patches`
---- @string priority ... one of the defined priorities in the userpatch hashtable
function userpatch.applyPatches(priority)
    local patch_dir = data_dir .. "/patches"
    local update_once_marker = package_dir .. "/update_once.marker"
    local update_once_pending = lfs.attributes(update_once_marker, "mode") == "file"

    if priority >= userpatch.early or update_once_pending then
        local executed_something = runUserPatchTasks(patch_dir, priority)
        if executed_something and update_once_pending then
            -- Only delete update once marker if `early_once` updates have been applied.
            os.remove(update_once_marker) -- Prevent another execution on a further starts.
        end
    end
end

return userpatch
