--[[--
Allows to apply developer patches on KOReader startup.
--]]--

local Device = require("device")

if Device:canApplyPatches() then
    -- Run KOReader patches placed in the patches directory (flat, no subdir).
    -- (https://github.com/koreader/koreader/pull/9058#issuecomment-1120240470, thanks to @poire-z)
    local DataStorage = require("datastorage")
    local patch_dir = DataStorage:getDataDir() .. "/patches"
    local patch_dir_attributes = lfs.attributes(patch_dir)
    if patch_dir_attributes and patch_dir_attributes.mode == "directory" then
        local logger = require("logger")
        logger.info("Patch directory found")
        for entry in lfs.dir(patch_dir) do
            local patch = patch_dir .. "/" .. entry
            local patch_attributes = lfs.attributes(patch)
            if patch_attributes and patch_attributes.mode == "file" and patch:match("%.lua$") then
                local ok, err = pcall(dofile, patch)
                if not ok then
                    -- Only developers (advanced users) will use this mechanism.
                    -- A warning on a patch failure after an OTA update will simplify troubleshooting.
                    logger.warn("Patch", err)
                    local UIManager = require("ui/uimanager")
                    local _ = require("gettext")
                    local T = require("ffi/util").template
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{text = T(_("Error loading patch:\n%1"), patch)})
                else
                    logger.info("Patch applied:", patch)
                end
            elseif patch_attributes and patch_attributes.mode == "directory" and not patch:match("%.%.?$") then
                logger.warn("Patch subdirectories are not supported:", patch)
            end
        end
    end
end
