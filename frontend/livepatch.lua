--[[--
Allows to apply developer patches, shell scripts an file migration during KOReader startup.

The contents in `koreader/userpatches/` are applied on calling `livepatch.applyPatches(priority)`.
--]]--

local isAndroid, android = pcall(require, "android")

local livepatch =
    {   -- priorities for user patches
        early_afterupdate = "0",
        early = "1",
        late = "2",
    }

-- The following functins will be overwritten, if the device allows it.
function livepatch.applyPatches() end

if isAndroid and android.prop.flavor == "fdroid" then
    return livepatch
end

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

-- Run user shell scripts or lua patches
-- string directory ... to scan through
-- char priority ... only files starting with that char will be processed
-- string parent ... parent directory
local function runLiveUpdateTasks(dir, priority)
    local patches = {}
    for entry in lfs.dir(dir) do
        local mode = lfs.attributes(dir .. "/" .. entry, "mode")
        if entry and mode == "file" and entry:match("^" .. priority .. "%d*%-") then
            table.insert(patches, entry)
        end
    end

    -- adapted from: http://notebook.kulchenko.com/algorithms/alphanumeric-natural-sorting-for-humans-in-lua
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
        local mode = lfs.attributes(fullpath).mode
        if mode == "file" and fullpath:match("%.sh$") then -- execute shell scripts
            execute("sh", fullpath, home_dir .. "/koreader", package_dir)
        elseif mode == "file" and fullpath:match("%.lua$")
            and not fullpath:match("early%-patch%.lua$") then -- execute patch-files
            local ok, err = pcall(dofile, fullpath)
            if not ok then
                logger.warn("Live update", err)
                if priority > livepatch.early then -- Only show InfoMessage, when late during startup.
                    -- Only developers (advanced users) will use this mechanism.
                    -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                    local UIManager = require("ui/uimanager")
                    local _ = require("gettext")
                    local T = require("ffi/util").template
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{text = T(_("Error loading patch:\n%1"), fullpath)})
                end
            else
                logger.info("Live update applied:", fullpath)
            end
        end
    end
end

--- This function works on the contents of `home_dir/koreader/scripts.late` (except `early-patch.lua`)
function livepatch.applyPatches(priority)
    -- patches and scripts get applied at every start of koreader, no migration here
    local patch_dir = home_dir .. "/koreader/userpatches"

    if priority == livepatch.early then
        -- Move an existing `koreader/patch.lua` to `koreader/userpatches/0000-patch.lua`
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
        os.remove(afterupdate_marker) -- Prevent another execution on a further starts.
        first_start_after_update = true
    end

    if priority >= livepatch.early or first_start_after_update then
        runLiveUpdateTasks(patch_dir, priority)
    end
end

return livepatch
