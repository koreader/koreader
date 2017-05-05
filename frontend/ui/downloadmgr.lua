--[[--
This module displays a PathChooser widget to choose a download directory.

It can be used as a callback on a button or menu item.

Example:
    callback = function()
        require("ui/downloadmgr"):new{
            title = _("Choose download directory"),
            onConfirm = function(path)
                logger.dbg("set download directory to", path)
                G_reader_settings:saveSetting("download_dir", path)
                UIManager:nextTick(function()
                    -- reinitialize dialog
                end)
            end,
    }:chooseDir()
]]

local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local util = require("ffi/util")
local _ = require("gettext")

local DownloadMgr = {
    title = _("Long press to choose download directory"),
    onConfirm = function() end,
}

function DownloadMgr:new(from_o)
    local o = from_o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Displays a PathChooser widget for picking a (download) directory.
-- @treturn string path chosen by the user
function DownloadMgr:chooseDir()
    local lastdir = G_reader_settings:readSetting("lastdir")
    local download_dir = G_reader_settings:readSetting("download_dir")
    local path_chooser = PathChooser:new{
        title = self.title,
        height = Screen:getHeight(),
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
