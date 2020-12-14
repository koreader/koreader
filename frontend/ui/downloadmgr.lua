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
    end
]]

local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local util = require("ffi/util")
local _ = require("gettext")

local DownloadMgr = {
    -- title = _("Long press to choose download directory"),
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
function DownloadMgr:chooseDir(dir)
    local path
    if not dir then
        local lastdir = G_reader_settings:readSetting("lastdir")
        local download_dir = G_reader_settings:readSetting("download_dir")
        path = download_dir and util.realpath(download_dir .. "/..") or lastdir
    else
        path = dir
    end
    local path_chooser = PathChooser:new{
        title = self.title or true, -- use default title if none provided
        select_directory = true,
        select_file = false,
        show_files = false,
        height = Screen:getHeight(),
        path = path,
        onConfirm = function(dir_path)
            self.onConfirm(dir_path)
        end
    }
    UIManager:show(path_chooser)
end

return DownloadMgr
