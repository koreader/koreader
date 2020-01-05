local CloudStorage = require("apps/cloudstorage/cloudstorage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local CloudMgr = {
    onConfirm = function() end,
}

function CloudMgr:new(from_o)
    local o = from_o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Displays a PathChooser for cloud drive for picking a (source) directory.
-- @treturn string path chosen by the user
function CloudMgr:chooseDir()
    local cloud_storage = CloudStorage:new{
        title = _("Long-press to select directory"),
        item = self.item,
        onConfirm = function(dir_path)
            self.onConfirm(dir_path)
        end,
    }
    UIManager:show(cloud_storage)
end

return CloudMgr
