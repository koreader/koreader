--[[--
This module contains miscellaneous helper functions for FileManager
]]

local BD = require("ui/bidi")
local Device = require("device")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
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

function filemanagerutil.splitFileNameType(filepath)
    local _, filename = util.splitFilePathName(filepath)
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

function filemanagerutil.getRandomFile(dir, match_func)
    if not dir:match("/$") then
        dir = dir .. "/"
    end
    local files = {}
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for entry in iter, dir_obj do
            local file = dir .. entry
            if lfs.attributes(file, "mode") == "file" and match_func(file) then
                table.insert(files, entry)
            end
        end
        if #files > 0 then
            math.randomseed(os.time())
            return dir .. files[math.random(#files)]
        end
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
    local summary = doc_settings:readSetting("summary", {})
    summary.status = status
    summary.modified = os.date("%Y-%m-%d", os.time())
    doc_settings:flush()
end

function filemanagerutil.statusToString(status)
    local status_to_text = {
        new       = _("Unread"),
        reading   = _("Reading"),
        abandoned = _("On hold"),
        complete  = _("Finished"),
    }

    return status_to_text[status]
end

-- Generate all book status file dialog buttons in a row
function filemanagerutil.genStatusButtonsRow(doc_settings_or_file, caller_callback)
    local file, summary, status
    if type(doc_settings_or_file) == "table" then -- currently opened file
        file = doc_settings_or_file:readSetting("doc_path")
        summary = doc_settings_or_file:readSetting("summary")
        status = summary.status
    else
        file = doc_settings_or_file
        summary = {}
        status = filemanagerutil.getStatus(file)
    end
    local function genStatusButton(to_status)
        return {
            text = filemanagerutil.statusToString(to_status) .. (status == to_status and "  ✓" or ""),
            enabled = status ~= to_status,
            callback = function()
                summary.status = to_status
                filemanagerutil.setStatus(file, to_status)
                UIManager:broadcastEvent(Event:new("DocSettingsItemsChanged", file, { summary = summary })) -- for CoverBrowser
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
    file = ffiutil.realpath(file) or file
    local has_sidecar_file = DocSettings:hasSidecarFile(file)
    local custom_cover_file = DocSettings:findCustomCoverFile(file)
    local has_custom_cover_file = custom_cover_file and true or false
    local custom_metadata_file = DocSettings:findCustomMetadataFile(file)
    local has_custom_metadata_file = custom_metadata_file and true or false
    return {
        text = _("Reset"),
        enabled = not button_disabled and (has_sidecar_file or has_custom_metadata_file or has_custom_cover_file),
        callback = function()
            local CheckButton = require("ui/widget/checkbutton")
            local ConfirmBox = require("ui/widget/confirmbox")
            local check_button_settings, check_button_cover, check_button_metadata
            local confirmbox = ConfirmBox:new{
                text = T(_("Reset this document?") .. "\n\n%1\n\n" ..
                         _("Information will be permanently lost."),
                    BD.filepath(file)),
                ok_text = _("Reset"),
                ok_callback = function()
                    local data_to_purge = {
                        doc_settings         = check_button_settings.checked,
                        custom_cover_file    = check_button_cover.checked and custom_cover_file,
                        custom_metadata_file = check_button_metadata.checked and custom_metadata_file,
                    }
                    DocSettings:open(file):purge(nil, data_to_purge)
                    if data_to_purge.custom_cover_file or data_to_purge.custom_metadata_file then
                        UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file))
                    end
                    if data_to_purge.doc_settings then
                        UIManager:broadcastEvent(Event:new("DocSettingsItemsChanged", file)) -- for CoverBrowser
                        require("readhistory"):fileSettingsPurged(file)
                    end
                    caller_callback()
                end,
            }
            check_button_settings = CheckButton:new{
                text = _("document settings, progress, bookmarks, highlights, notes"),
                checked = has_sidecar_file,
                enabled = has_sidecar_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_settings)
            check_button_cover = CheckButton:new{
                text = _("custom cover image"),
                checked = has_custom_cover_file,
                enabled = has_custom_cover_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_cover)
            check_button_metadata = CheckButton:new{
                text = _("custom book metadata"),
                checked = has_custom_metadata_file,
                enabled = has_custom_metadata_file,
                parent = confirmbox,
            }
            confirmbox:addWidget(check_button_metadata)
            UIManager:show(confirmbox)
        end,
    }
end

function filemanagerutil.genAddRemoveFavoritesButton(file, caller_callback, button_disabled)
    local ReadCollection = require("readcollection")
    local has_file = ReadCollection:hasFile(file)
    return {
        text_func = function()
            return has_file and _("Remove from favorites") or _("Add to favorites")
        end,
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            if has_file then
                ReadCollection:removeItem(file)
            else
                ReadCollection:addItem(file)
            end
        end,
    }
end

function filemanagerutil.genShowFolderButton(file, caller_callback, button_disabled)
    return {
        text = _("Show folder"),
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            local ui = require("apps/filemanager/filemanager").instance
            if ui then
                local pathname = util.splitFilePathName(file)
                ui.file_chooser:changeToPath(pathname, file)
            else
                ui = require("apps/reader/readerui").instance
                ui:onClose()
                ui:showFileManager(file)
            end
        end,
    }
end

function filemanagerutil.genBookInformationButton(file, bookinfo, caller_callback, button_disabled)
    return {
        text = _("Book information"),
        enabled = not button_disabled,
        callback = function()
            caller_callback()
            local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
            FileManagerBookInfo:show(file, bookinfo and FileManagerBookInfo.extendProps(bookinfo))
        end,
    }
end

function filemanagerutil.genBookCoverButton(file, bookinfo, caller_callback, button_disabled)
    local has_cover = bookinfo and bookinfo.has_cover
    return {
        text = _("Book cover"),
        enabled = (not button_disabled and (not bookinfo or has_cover)) and true or false,
        callback = function()
            caller_callback()
            local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
            FileManagerBookInfo:onShowBookCover(file)
        end,
    }
end

function filemanagerutil.genBookDescriptionButton(file, bookinfo, caller_callback, button_disabled)
    local description = bookinfo and bookinfo.description
    return {
        text = _("Book description"),
        -- enabled for deleted books if description is kept in CoverBrowser bookinfo cache
        enabled = (not (button_disabled or bookinfo) or description) and true or false,
        callback = function()
            caller_callback()
            local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
            FileManagerBookInfo:onShowBookDescription(description, file)
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

function filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path, file_filter)
    local is_file = file_filter and true or false
    local path = current_path or default_path
    local dialog
    local buttons = {
        {
            {
                text = is_file and _("Choose file") or _("Choose folder"),
                callback = function()
                    UIManager:close(dialog)
                    if path then
                        if is_file then
                            path = path:match("(.*/)")
                        end
                        if lfs.attributes(path, "mode") ~= "directory" then
                            path = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
                        end
                    end
                    local PathChooser = require("ui/widget/pathchooser")
                    local path_chooser = PathChooser:new{
                        select_directory = not is_file,
                        select_file = is_file,
                        show_files = is_file,
                        file_filter = file_filter,
                        path = path,
                        onConfirm = function(new_path)
                            caller_callback(new_path)
                        end,
                    }
                    UIManager:show(path_chooser)
                end,
            },
        }
    }
    if default_path then
        table.insert(buttons, {
            {
                text = _("Use default"),
                enabled = path ~= default_path,
                callback = function()
                    UIManager:close(dialog)
                    caller_callback(default_path)
                end,
            },
        })
    end
    local title_value = path and (is_file and BD.filepath(path) or BD.dirpath(path))
                              or _("not set")
    local ButtonDialog = require("ui/widget/buttondialog")
    dialog = ButtonDialog:new{
        title = title_header .. "\n\n" .. title_value .. "\n",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

return filemanagerutil
