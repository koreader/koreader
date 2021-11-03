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
        if path == home_dir then
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

-- Purge reflowable doc font and page settings
function filemanagerutil.purgeViewSettings(file)
    local view_settings = {
        "font_face",
        -- crop tab
        "copt_h_page_margins",
        "copt_t_page_margin",
        "copt_b_page_margin",
        -- pageview tab
        "copt_line_spacing",
        "line_space_percent",
        -- textsize tab
        "font_size",
        "copt_font_size",
        "word_spacing",
        "copt_word_spacing",
        "word_expansion",
        "copt_word_expansion",
        -- contrast tab
        "gamma_index",
        "copt_font_gamma",
        "font_base_weight",
        "copt_font_base_weight",
        "font_hinting",
        "copt_font_hinting",
        "font_kerning",
        "copt_font_kerning",
    }
    local file_abs_path = util.realpath(file)
    if file_abs_path then
        local doc_settings = DocSettings:open(file_abs_path)
        for _, v in ipairs(view_settings) do
            doc_settings:delSetting(v)
        end
        doc_settings:close()
    end
end

return filemanagerutil
