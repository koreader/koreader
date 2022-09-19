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
local util = require("ffi/util")
local _ = require("gettext")

local DownloadMgr = {
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
    if dir then
        path = dir
    else
        local lastdir = G_reader_settings:readSetting("lastdir")
        local download_dir = G_reader_settings:readSetting("download_dir")
        path = download_dir and util.realpath(download_dir .. "/..") or lastdir
    end
    local path_chooser = PathChooser:new{
        select_file = false,
        show_files = false,
        path = path,
        onConfirm = function(dir_path)
            self.onConfirm(dir_path)
        end
    }
    UIManager:show(path_chooser)
end

function DownloadMgr:chooseCloudDir()
    local cloud_storage = require("apps/cloudstorage/cloudstorage"):new{
        item = self.item,
        onConfirm = function(dir_path)
            self.onConfirm(dir_path)
        end,
    }
    UIManager:show(cloud_storage)
end

return DownloadMgr
