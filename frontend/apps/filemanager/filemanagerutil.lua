--[[--
This module contains miscellaneous helper functions for FileManager
]]

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local util = require("ffi/util")
local _ = require("gettext")
local T = util.template

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
        doc_settings:flush()
    end
end

-- Get a document's status ("new", "reading", "complete", or "abandoned")
function filemanagerutil.getStatus(file)
    local status = "new"
    if DocSettings:hasSidecarFile(file) then
        local docinfo = DocSettings:open(file) -- no io handles created, do not close
        if docinfo.data.summary and docinfo.data.summary.status and docinfo.data.summary.status ~= "" then
            status = docinfo.data.summary.status
        else
            status = "reading"
        end
    end
    return status
end

-- Set a document's status
function filemanagerutil.setStatus(file, status)
    -- In case the book doesn't have a sidecar file, this'll create it
    local docinfo = DocSettings:open(file)
    local summary
    if docinfo.data.summary and docinfo.data.summary.status then
        -- Book already had the full BookStatus table in its sidecar, easy peasy!
        docinfo.data.summary.status = status
        docinfo.data.summary.modified = os.date("%Y-%m-%d", os.time())
        summary = docinfo.data.summary
    else
        -- No BookStatus table, create a minimal one...
        if docinfo.data.summary then
            -- Err, a summary table with no status entry? Should never happen...
            summary = { status = status }
            -- Append the status entry to the existing summary...
            require("util").tableMerge(docinfo.data.summary, summary)
            docinfo.data.summary.modified = os.date("%Y-%m-%d", os.time())
            summary = docinfo.data.summary
        else
            -- No summary table at all, create a minimal one
            summary = {
                status = status,
                modified = os.date("%Y-%m-%d", os.time())
            }
        end
    end
    docinfo:saveSetting("summary", summary)
    docinfo:flush()
end

-- Generate all book status file dialog buttons in a row
function filemanagerutil.getStatusButtonsRow(file, caller_callback)
    local status = filemanagerutil.getStatus(file)
    local function genStatusButton(to_status)
        local status_text = {
            reading   = _("Reading"),
            abandoned = _("On hold"),
            complete  = _("Finished"),
        }
        return {
            text = status_text[to_status],
            id = to_status, -- used by covermenu
            enabled = status ~= to_status,
            callback = function()
                filemanagerutil.setStatus(file, to_status)
                caller_callback()
            end,
        }
    end
    return {
        genStatusButton("reading", status, file, caller_callback),
        genStatusButton("abandoned", status, file, caller_callback),
        genStatusButton("complete", status, file, caller_callback),
    }
end

-- Generate a "Reset settings" file dialog button
function filemanagerutil.genResetSettingsButton(file, currently_opened_file, caller_callback)
    return {
        text = _("Reset"),
        id = "reset", -- used by covermenu
        enabled = file ~= currently_opened_file and DocSettings:hasSidecarFile(util.realpath(file)),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = T(_("Reset this document?\n\n%1\n\nAll document progress, settings, bookmarks, highlights, and notes will be permanently lost."),
                    BD.filepath(file)),
                ok_text = _("Reset"),
                ok_callback = function()
                    filemanagerutil.purgeSettings(file)
                    require("readhistory"):fileSettingsPurged(file)
                    caller_callback()
                end,
            })
        end,
    }
end

return filemanagerutil
