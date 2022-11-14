--[[--
This module contains miscellaneous helper functions for FileManager
]]

local Device = require("device")
local DocSettings = require("docsettings")
local util = require("ffi/util")
local _ = require("gettext")

local filemanagerutil = {}

function filemanagerutil.getDefaultDir()
    return Device.home_dir or "."
end

function filemanagerutil.abbreviate(path)
    if not path then return "" end
    if G_reader_settings:nilOrTrue("shorten_home_dir") then
        local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        if path == home_dir or path == home_dir .. "/" then
            return _("Home")
        end
        local len = home_dir:len()
        local start = path:sub(1, len)
        if start == home_dir and path:sub(len+1, len+1) == "/" then
            return path:sub(len+2)
        end
    end
    return path
end

-- Purge doc settings in sidecar directory
function filemanagerutil.purgeSettings(file)
    local file_abs_path = util.realpath(file)
    if file_abs_path then
        DocSettings:open(file_abs_path):purge()
    end
end

-- Purge doc settings except kept
function filemanagerutil.resetDocumentSettings(file)
    local settings_to_keep = {
        bookmarks = true,
        bookmarks_sorted = true,
        bookmarks_sorted_20220106 = true,
        bookmarks_version = true,
        cre_dom_version = true,
        highlight = true,
        highlights_imported = true,
        last_page = true,
        last_xpointer = true,
    }
    local file_abs_path = util.realpath(file)
    if file_abs_path then
        local doc_settings = DocSettings:open(file_abs_path)
        for k in pairs(doc_settings.data) do
            if not settings_to_keep[k] then
                doc_settings:delSetting(k)
            end
        end
        doc_settings:makeTrue("docsettings_reset_done") -- for readertypeset block_rendering_mode
        doc_settings:close()
    end
end

return filemanagerutil
