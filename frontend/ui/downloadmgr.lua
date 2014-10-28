local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")

local DownloadMgr = {
    title = _("Choose download directory"),
    onConfirm = function() end,
}

function DownloadMgr:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function DownloadMgr:chooseDir()
    local lastdir = G_reader_settings:readSetting("lastdir")
    local download_dir = G_reader_settings:readSetting("download_dir")
    local path_chooser = PathChooser:new{
        title = self.title,
        path = download_dir and (download_dir .. "/..") or lastdir,
        show_hidden = G_reader_settings:readSetting("show_hidden"),
        onConfirm = function(path)
            -- hack to remove additional parent
            if path:sub(-3, -1) == "/.." then
                path = path:sub(1, -4)
            end
            self.onConfirm(util.realpath(path))
        end
    }
    UIManager:show(path_chooser)
end

return DownloadMgr
