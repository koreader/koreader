--[[--
This module contains miscellaneous helper functions for FileManager
]]

local BD = require("ui/bidi")
local Device = require("device")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

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

function filemanagerutil.splitFileNameType(filename)
    local filename_without_suffix, filetype = util.splitFileNameSuffix(filename)
    filetype = filetype:lower()
    if filetype == "zip" then
        local filename_without_sub_suffix, sub_filetype = util.splitFileNameSuffix(filename_without_suffix)
        sub_filetype = sub_filetype:lower()
        local supported_sub_filetypes = { "fb2", "htm", "html", "log", "md", "rtf", "txt", }
        if util.arrayContains(supported_sub_filetypes, sub_filetype) then
            return filename_without_sub_suffix, sub_filetype .. ".zip"
        end
    end
    return filename_without_suffix, filetype
end

-- Purge doc settings in sidecar directory
function filemanagerutil.purgeSettings(file)
    local file_abs_path = ffiutil.realpath(file)
    if file_abs_path then
        return DocSettings:open(file_abs_path):purge()
    end
end

-- Purge doc settings except kept
function filemanagerutil.resetDocumentSettings(file)
    local settings_to_keep = {
        bookmarks = true,
        bookmarks_sorted_20220106 = true,
        bookmarks_version = true,
        cre_dom_version = true,
        highlight = true,
        highlights_imported = true,
        last_page = true,
        last_xpointer = true,
    }
    local file_abs_path = ffiutil.realpath(file)
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

-- Get a document status ("new", "reading", "complete", or "abandoned")
function filemanagerutil.getStatus(file)
    if DocSettings:hasSidecarFile(file) then
        local summary = DocSettings:open(file):readSetting("summary")
        if summary and summary.status and summary.status ~= "" then
            return summary.status
        end
        return "reading"
    end
    return "new"
end

-- Set a document status ("reading", "complete", or "abandoned")
function filemanagerutil.setStatus(file, status)
    -- In case the book doesn't have a sidecar file, this'll create it
    local doc_settings = DocSettings:open(file)
    local summary = doc_settings:readSetting("summary") or {}
    summary.status = status
    summary.modified = os.date("%Y-%m-%d", os.time())
    doc_settings:saveSetting("summary", summary)
    doc_settings:flush()
end

-- Generate all book status file dialog buttons in a row
function filemanagerutil.genStatusButtonsRow(file, caller_callback, current_status)
    local status = current_status or filemanagerutil.getStatus(file)
    local function genStatusButton(to_status)
        local status_text = {
            reading   = _("Reading"),
            abandoned = _("On hold"),
            complete  = _("Finished"),
        }
        return {
            text = status_text[to_status] .. (status == to_status and "  ✓" or ""),
            id = to_status, -- used by covermenu
            enabled = status ~= to_status,
            callback = function()
                filemanagerutil.setStatus(file, to_status)
                caller_callback()
            end,
        }
    end
    return {
        genStatusButton("reading"),
        genStatusButton("abandoned"),
        genStatusButton("complete"),
    }
end

-- Generate "Reset" file dialog button
function filemanagerutil.genResetSettingsButton(file, caller_callback, button_disabled)
    return {
        text = _("Reset"),
        id = "reset", -- used by covermenu
        enabled = (not button_disabled and DocSettings:hasSidecarFile(ffiutil.realpath(file))) and true or false,
        callback = function()
            local ConfirmBox = require("ui/widget/confirmbox")
            local confirmbox = ConfirmBox:new{
                text = T(_("Reset this document?") .. "\n\n%1\n\n" ..
                    _("Document progress, settings, bookmarks, highlights, notes and custom cover image will be permanently lost."),
                    BD.filepath(file)),
                ok_text = _("Reset"),
                ok_callback = function()
                    local custom_metadata_purged = filemanagerutil.purgeSettings(file)
                    if custom_metadata_purged then -- refresh coverbrowser cached book info
                        local FileManager = require("apps/filemanager/filemanager")
                        local ui = FileManager.instance
                        if not ui then
                            local ReaderUI = require("apps/reader/readerui")
                            ui = ReaderUI.instance
                        end
                        if ui and ui.coverbrowser then
                            ui.coverbrowser:deleteBookInfo(file)
                        end
                    end
                    require("readhistory"):fileSettingsPurged(file)
                    caller_callback()
                end,
            }
            UIManager:show(confirmbox)
        end,
    }
end

function filemanagerutil.genBookInformationButton(file, caller_callback, button_disabled)
    return {
        text = _("Book information"),
        id = "book_information", -- used by covermenu
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            require("apps/filemanager/filemanagerbookinfo"):show(file)
        end,
    }
end

function filemanagerutil.genBookCoverButton(file, caller_callback, button_disabled)
    return {
        text = _("Book cover"),
        id = "book_cover", -- used by covermenu
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            require("apps/filemanager/filemanagerbookinfo"):onShowBookCover(file)
        end,
    }
end

function filemanagerutil.genBookDescriptionButton(file, caller_callback, button_disabled)
    return {
        text = _("Book description"),
        id = "book_description", -- used by covermenu
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            require("apps/filemanager/filemanagerbookinfo"):onShowBookDescription(nil, file)
        end,
    }
end

-- Generate "Execute script" file dialog button
function filemanagerutil.genExecuteScriptButton(file, caller_callback)
    local InfoMessage = require("ui/widget/infomessage")
    return {
        -- @translators This is the script's programming language (e.g., shell or python)
        text = T(_("Execute %1 script"), util.getScriptType(file)),
        callback = function()
            caller_callback()
            local script_is_running_msg = InfoMessage:new{
                -- @translators %1 is the script's programming language (e.g., shell or python), %2 is the filename
                text = T(_("Running %1 script %2…"), util.getScriptType(file), BD.filename(ffiutil.basename(file))),
            }
            UIManager:show(script_is_running_msg)
            UIManager:scheduleIn(0.5, function()
                local rv
                if Device:isAndroid() then
                    Device:setIgnoreInput(true)
                    rv = os.execute("sh " .. ffiutil.realpath(file)) -- run by sh, because sdcard has no execute permissions
                    Device:setIgnoreInput(false)
                else
                    rv = os.execute(ffiutil.realpath(file))
                end
                UIManager:close(script_is_running_msg)
                if rv == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("The script exited successfully."),
                    })
                else
                    --- @note: Lua 5.1 returns the raw return value from the os's system call. Counteract this madness.
                    UIManager:show(InfoMessage:new{
                        text = T(_("The script returned a non-zero status code: %1!"), bit.rshift(rv, 8)),
                        icon = "notice-warning",
                    })
                end
            end)
        end,
    }
end

return filemanagerutil
