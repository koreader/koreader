local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local PathChooser = require("ui/widget/pathchooser")
local Provider = require("provider")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Trapper = require("ui/trapper")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local util = require("util")

-- Main plugin container that registers in the tools menu
local CloudStorage = WidgetContainer:extend{
    name = "cloudstorage",
    is_doc_only = false,
}

-- The actual menu widget for cloud storage browsing
local CloudStorageMenu = Menu:extend{
    no_title = false,
    show_parent = nil,
    is_popout = false,
    is_borderless = true,
    title = _("Cloud storage"),
}

-- Get providers from the Provider system
function CloudStorageMenu:getProviders()
    return Provider:getProvidersTable("cloudstorage")
end

-- Check if any providers are available
function CloudStorageMenu:hasProviders()
    return Provider:size("cloudstorage") > 0
end

-- Get provider names for UI display
function CloudStorageMenu:getProviderNames()
    local names = {}
    local providers = self:getProviders()
    for id, config in pairs(providers) do
        names[id] = config.name
    end
    return names
end

function CloudStorageMenu:init()
    self.cs_settings = self:readSettings()
    self.show_parent = self

    if self.item then
        self.item_table = self:genItemTable(self.item)
        self.choose_folder_mode = true
    else
        self.item_table = self:genItemTableFromRoot()
    end

    self.title_bar_left_icon = "plus"
    self.onLeftButtonTap = function() -- add new cloud storage
        self:selectCloudType()
    end
    Menu.init(self)
    if self.item then
        self.item_table[1].callback()
    end
end

function CloudStorageMenu:genItemTableFromRoot()
    local item_table = {}
    local added_servers = self.cs_settings:readSetting("cs_servers") or {}
    local provider_names = self:getProviderNames()
    local providers = self:getProviders()

    for _, server in ipairs(added_servers) do
        if providers[server.type] then
            table.insert(item_table, {
                text = server.name,
                mandatory = provider_names[server.type],
                address = server.address,
                username = server.username,
                password = server.password,
                type = server.type,
                editable = true,
                url = server.url,
                sync_source_folder = server.sync_source_folder,
                sync_dest_folder = server.sync_dest_folder,
                callback = function()
                    self.type = server.type
                    self.password = server.password
                    self.address = server.address
                    self.username = server.username
                    self:openCloudServer(server.url)
                end,
            })
        end
    end
    return item_table
end

function CloudStorageMenu:genItemTable(item)
    local item_table = {}
    local added_servers = self.cs_settings:readSetting("cs_servers") or {}

    for _, server in ipairs(added_servers) do
        if server.name == item.text and server.password == item.password and server.type == item.type then
            table.insert(item_table, {
                text = server.name,
                address = server.address,
                username = server.username,
                password = server.password,
                type = server.type,
                url = server.url,
                callback = function()
                    self.type = server.type
                    self.password = server.password
                    self.address = server.address
                    self.username = server.username
                    self:openCloudServer(server.url)
                end,
            })
        end
    end
    return item_table
end

function CloudStorageMenu:selectCloudType()
    local buttons = {}
    local provider_names = self:getProviderNames()

    -- Build buttons from available providers
    for provider_id, name in FFIUtil.orderedPairs(provider_names) do
        table.insert(buttons, {
            {
                text = name,
                callback = function()
                    UIManager:close(self.cloud_dialog)
                    self:configCloud(provider_id)
                end,
            },
        })
    end

    -- Show error if no providers are available
    if #buttons == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No cloud storage providers available.\nPlease ensure provider plugins are enabled in Plugin Manager."),
            timeout = 3,
        })
        return false
    end

    self.cloud_dialog = ButtonDialog:new{
        title = _("Add new cloud storage"),
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(self.cloud_dialog)
    return true
end

function CloudStorageMenu:openCloudServer(url)
    local providers = self:getProviders()
    local provider = providers[self.type]
    if not provider or not provider.list then
        logger.err("CloudStorage:openCloudServer: No list function for provider", self.type)
        return false
    end

    logger.dbg("CloudStorage:openCloudServer type=", self.type, " url=", url or "")

    local tbl, e = provider.list(self.address, self.username, self.password, url, self.choose_folder_mode)

    if tbl then
        self:switchItemTable(url, tbl)
        if provider.upload or provider.create_folder then
            self.onLeftButtonTap = function()
                self:showPlusMenu(url)
            end
        else
            self:setTitleBarLeftIcon("home")
            self.onLeftButtonTap = function()
                self:init()
            end
        end
        return true
    else
        logger.err("CloudStorage:openCloudServer failed:", e)
        UIManager:show(InfoMessage:new{
            text = _("Cannot fetch list of folder contents\nPlease check your configuration or network connection."),
            timeout = 3,
        })
        table.remove(self.paths)
        return false
    end
end

function CloudStorageMenu:onMenuSelect(item)
    if item.callback then
        if item.url ~= nil then
            table.insert(self.paths, {
                url = item.url,
            })
        end
        item.callback()
    elseif item.type == "file" then
        self:downloadFile(item)
    elseif item.type == "other" then
        return true
    else
        table.insert(self.paths, {
            url = item.url,
        })
        if not self:openCloudServer(item.url) then
            table.remove(self.paths)
        end
    end
    return true
end

function CloudStorageMenu:downloadFile(item)
    local providers = self:getProviders()
    local provider = providers[self.type]
    if not provider or not provider.download then
        logger.err("CloudStorage:downloadFile: No download function for provider", self.type)
        return
    end

    local function startDownloadFile(unit_item, address, username, password, path_dir, callback_close)
        UIManager:scheduleIn(1, function()
            provider.download(unit_item, address, username, password, path_dir, callback_close)
        end)
        UIManager:show(InfoMessage:new{
            text = _("Downloading. This might take a moment."),
            timeout = 1,
        })
    end

    local function createTitle(filename_orig, filesize, filename, path)
        local filesize_str = filesize and util.getFriendlySize(filesize) or _("N/A")
        return T(_("Filename:\n%1\n\nFile size:\n%2\n\nDownload filename:\n%3\n\nDownload folder:\n%4"),
            filename_orig, filesize_str, filename, BD.dirpath(path))
    end

    local cs_settings = self:readSettings()
    local download_dir = cs_settings:readSetting("download_dir") or G_reader_settings:readSetting("lastdir")
    local filename_orig = item.text
    local filename = filename_orig
    local filesize = item.filesize

    local buttons = {
        {
            {
                text = _("Choose folder"),
                callback = function()
                    require("ui/downloadmgr"):new{
                        onConfirm = function(path)
                            self.cs_settings:saveSetting("download_dir", path)
                            self.cs_settings:flush()
                            download_dir = path
                            self.download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
                        end,
                    }:chooseDir(download_dir)
                end,
            },
            {
                text = _("Change filename"),
                callback = function()
                    local input_dialog
                    input_dialog = InputDialog:new{
                        title = _("Enter filename"),
                        input = filename,
                        input_hint = filename_orig,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(input_dialog)
                                    end,
                                },
                                {
                                    text = _("Set filename"),
                                    is_enter_default = true,
                                    callback = function()
                                        filename = input_dialog:getInputValue()
                                        if filename == "" then
                                            filename = filename_orig
                                        end
                                        UIManager:close(input_dialog)
                                        self.download_dialog:setTitle(createTitle(filename_orig, filesize, filename, download_dir))
                                    end,
                                },
                            }
                        },
                    }
                    UIManager:show(input_dialog)
                    input_dialog:onShowKeyboard()
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(self.download_dialog)
                end,
            },
            {
                text = _("Download"),
                callback = function()
                    UIManager:close(self.download_dialog)
                    local path_dir = (download_dir ~= "/" and download_dir or "") .. '/' .. filename
                    local callback_close = function() self:onClose() end
                    if lfs.attributes(path_dir) then
                        UIManager:show(ConfirmBox:new{
                            text = _("File already exists. Would you like to overwrite it?"),
                            ok_callback = function()
                                startDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                            end
                        })
                    else
                        startDownloadFile(item, self.address, self.username, self.password, path_dir, callback_close)
                    end
                end,
            },
        },
    }

    self.download_dialog = ButtonDialog:new{
        title = createTitle(filename_orig, filesize, filename, download_dir),
        buttons = buttons,
    }
    UIManager:show(self.download_dialog)
end

function CloudStorageMenu:configCloud(provider_id)
    local providers = self:getProviders()
    local provider = providers[provider_id]
    if not provider then
        logger.err("CloudStorage:configCloud: Unknown provider", provider_id)
        return
    end

    local function callbackAdd(fields)
        local cs_settings = self:readSettings()
        local cs_servers = cs_settings:readSetting("cs_servers") or {}

        local server_config = {
            type = provider_id,
        }

        -- Map fields to server config based on provider's config_fields
        for i, field_config in ipairs(provider.config_fields) do
            server_config[field_config.name] = fields[i]
        end

        table.insert(cs_servers, server_config)
        cs_settings:saveSetting("cs_servers", cs_servers)
        cs_settings:flush()
        self:init()
    end

    -- Use declarative configuration via MultiInputDialog
    local dialog_config = {
        title = provider.config_title or T(_("Add %1 account"), provider.name),
        fields = {},
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.config_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        if provider.config_info then
                            UIManager:show(InfoMessage:new{ text = provider.config_info })
                        end
                    end
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.config_dialog:getFields()
                        callbackAdd(fields)
                        UIManager:close(self.config_dialog)
                    end
                },
            },
        },
    }

    -- Build fields from provider configuration
    for _, field_config in ipairs(provider.config_fields) do
        table.insert(dialog_config.fields, {
            text = field_config.default or "",
            hint = field_config.hint,
            input_type = field_config.input_type or "string",
            text_type = field_config.text_type,
        })
    end

    self.config_dialog = MultiInputDialog:new(dialog_config)
    UIManager:show(self.config_dialog)
    self.config_dialog:onShowKeyboard()
end

-- Synchronization functionality for providers that support it
function CloudStorageMenu:synchronizeCloud(item)
    local providers = self:getProviders()
    local provider = providers[item.type]
    if not provider or not provider.sync then
        UIManager:show(InfoMessage:new{
            text = T(_("%1 synchronization is not supported."), provider and provider.name or item.type),
            timeout = 3,
        })
        return
    end

    self.type = item.type
    self.password = item.password
    self.address = item.address
    self.username = item.username

    logger.dbg(string.format("CloudStorage:synchronizeCloud type=%s item=%s", item.type or "nil", item.text or "nil"))

    Trapper:wrap(function()
        Trapper:setPausedText(_("Download paused.\nDo you want to continue or abort downloading files?"))

        local function on_progress(kind, current, total, rel_path)
            local progress_text
            if kind == "scan_remote" then
                progress_text = _("Scanning remote files...")
            elseif kind == "scan_local" then
                progress_text = _("Scanning local files...")
            elseif kind == "create_dirs" then
                progress_text = _("Creating directories...")
            elseif kind == "download" then
                progress_text = T(_("Downloading %1/%2: %3"), current, total, rel_path or "")
            elseif kind == "cleanup" then
                progress_text = _("Cleaning up local files...")
            elseif kind == "cleanup_dirs" then
                progress_text = _("Removing empty folders...")
            else
                progress_text = _("Synchronizing...")
            end
            Trapper:info(progress_text)
        end

        local ok, results_or_err = pcall(provider.sync, item, self.address, self.username, self.password, on_progress)

        if ok and results_or_err then
            local text
            if type(results_or_err) == "table" then
                local service_name = provider.name or _("Cloud service")
                text = T(N_("Successfully downloaded 1 file from %2.", "Successfully downloaded %1 files from %2.", results_or_err.downloaded), results_or_err.downloaded, service_name)
                if results_or_err.deleted_files and results_or_err.deleted_files > 0 then
                    text = text .. " " .. T(N_("Deleted 1 local file.", "Deleted %1 local files.", results_or_err.deleted_files), results_or_err.deleted_files)
                end
                if results_or_err.deleted_folders and results_or_err.deleted_folders > 0 then
                    text = text .. " " .. T(N_("Deleted 1 empty folder.", "Deleted %1 empty folders.", results_or_err.deleted_folders), results_or_err.deleted_folders)
                end
                if results_or_err.failed and results_or_err.failed > 0 then
                    text = text .. "\n" .. T(N_("Failed to download 1 file.", "Failed to download %1 files.", results_or_err.failed), results_or_err.failed)
                end
                if results_or_err.skipped and results_or_err.skipped > 0 then
                    text = text .. " " .. T(N_("Skipped 1 unchanged file.", "Skipped %1 unchanged files.", results_or_err.skipped), results_or_err.skipped)
                end
            end

            logger.dbg("CloudStorage:synchronizeCloud success:", text)
            UIManager:show(InfoMessage:new{
                text = text,
                timeout = 3,
            })
        else
            logger.err("CloudStorage:synchronizeCloud failed:", results_or_err)
            Trapper:reset()
            UIManager:show(InfoMessage:new{
                text = _("Synchronization failed.\nPlease check your configuration and connection."),
                timeout = 3,
            })
        end
    end)
end

function CloudStorageMenu:readSettings()
    self.cs_settings = LuaSettings:open(DataStorage:getSettingsDir().."/cloudstorage.lua")
    return self.cs_settings
end

function CloudStorageMenu:onReturn()
    if #self.paths > 0 then
        table.remove(self.paths)
        local path = self.paths[#self.paths]
        if path then
            self:openCloudServer(path.url)
        else
            self:init()
        end
    end
    return true
end

function CloudStorageMenu:onHoldReturn()
    if #self.paths > 1 then
        local path = self.paths[1]
        if path then
            for i = #self.paths, 2, -1 do
                table.remove(self.paths)
            end
            self:openCloudServer(path.url)
        end
    end
    return true
end

function CloudStorageMenu:updateSyncFolder(item, source, dest)
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for _, server in ipairs(cs_servers) do
        if server.name == item.text and server.password == item.password and server.type == item.type then
            if source then
                server.sync_source_folder = source
            end
            if dest then
                server.sync_dest_folder = dest
            end
            break
        end
    end
    cs_settings:saveSetting("cs_servers", cs_servers)
    cs_settings:flush()
end

function CloudStorageMenu:onMenuHold(item)
    if item.type == "folder_long_press" then
        local title = T(_("Choose this folder?\n\n%1"), BD.dirpath(item.url))
        local onConfirm = self.onConfirm
        local button_dialog
        button_dialog = ButtonDialog:new{
            title = title,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(button_dialog)
                        end,
                    },
                    {
                        text = _("Choose"),
                        callback = function()
                            if onConfirm then
                                onConfirm(item.url)
                            end
                            UIManager:close(button_dialog)
                            UIManager:close(self)
                        end,
                    },
                },
            },
        }
        UIManager:show(button_dialog)
    end
    if item.editable then
        local cs_server_dialog
        local buttons = {
            {
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:infoServer(item)
                    end
                },
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:editCloudServer(item)
                    end
                },
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:deleteCloudServer(item)
                    end
                },
            },
        }
        local providers = self:getProviders()
        local provider = providers[item.type]
        if provider and provider.sync then
            table.insert(buttons, {
                {
                    text = _("Synchronize now"),
                    enabled = item.sync_source_folder ~= nil and item.sync_dest_folder ~= nil,
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:synchronizeCloud(item)
                    end
                },
                {
                    text = _("Synchronize settings"),
                    callback = function()
                        UIManager:close(cs_server_dialog)
                        self:synchronizeSettings(item)
                    end
                },
            })
        end
        cs_server_dialog = ButtonDialog:new{
            buttons = buttons
        }
        UIManager:show(cs_server_dialog)
        return true
    end
end

function CloudStorageMenu:synchronizeSettings(item)
    local syn_dialog
    local providers = self:getProviders()
    local provider = providers[item.type]
    local remote_sync_folder = item.sync_source_folder or _("not set")
    local local_sync_folder = item.sync_dest_folder or _("not set")
    local service_name = provider and provider.name or _("Cloud service")

    syn_dialog = ButtonDialog:new {
        title = T(_("%1 folder:\n%2\nLocal folder:\n%3"), service_name, BD.dirpath(remote_sync_folder), BD.dirpath(local_sync_folder)),
        title_align = "center",
        buttons = {
            {
                {
                    text = T(_("Choose %1 folder"), service_name),
                    callback = function()
                        UIManager:close(syn_dialog)
                        require("ui/downloadmgr"):new{
                            item = item,
                            onConfirm = function(path)
                                self:updateSyncFolder(item, path)
                                item.sync_source_folder = path
                                self:synchronizeSettings(item)
                            end,
                        }:chooseCloudDir()
                    end,
                },
            },
            {
                {
                    text = _("Choose local folder"),
                    callback = function()
                        UIManager:close(syn_dialog)
                        require("ui/downloadmgr"):new{
                            onConfirm = function(path)
                                self:updateSyncFolder(item, nil, path)
                                item.sync_dest_folder = path
                                self:synchronizeSettings(item)
                            end,
                        }:chooseDir()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(syn_dialog)
                    end,
                },
            },
        }
    }
    UIManager:show(syn_dialog)
end

function CloudStorageMenu:showPlusMenu(url)
    local providers = self:getProviders()
    local provider = providers[self.type]
    local button_dialog
    local buttons = {}

    if provider and provider.upload then
        table.insert(buttons, {
            {
                text = _("Upload file"),
                callback = function()
                    UIManager:close(button_dialog)
                    self:uploadFile(url)
                end,
            },
        })
    end

    if provider and provider.create_folder then
        table.insert(buttons, {
            {
                text = _("New folder"),
                callback = function()
                    UIManager:close(button_dialog)
                    self:createFolder(url)
                end,
            },
        })
    end

    table.insert(buttons, {})
    table.insert(buttons, {
        {
            text = _("Return to cloud storage list"),
            callback = function()
                UIManager:close(button_dialog)
                self:init()
            end,
        },
    })

    button_dialog = ButtonDialog:new{
        buttons = buttons,
    }
    UIManager:show(button_dialog)
end

function CloudStorageMenu:uploadFile(url)
    local providers = self:getProviders()
    local provider = providers[self.type]
    if not provider or not provider.upload then
        UIManager:show(InfoMessage:new{
            text = _("Upload not supported for this provider"),
            timeout = 3,
        })
        return
    end

    local path_chooser
    path_chooser = PathChooser:new{
        select_directory = false,
        path = self.last_path,
        onConfirm = function(file_path)
            self.last_path = file_path:match("(.*)/")
            if self.last_path == "" then self.last_path = "/" end
            if lfs.attributes(file_path, "size") > 157286400 then
                UIManager:show(InfoMessage:new{
                    text = _("File size must be less than 150 MB."),
                })
            else
                local callback_close = function()
                    self:openCloudServer(url)
                end
                UIManager:nextTick(function()
                    UIManager:show(InfoMessage:new{
                        text = _("Uploading…"),
                        timeout = 1,
                    })
                end)
                local url_base = url ~= "/" and url or ""
                UIManager:tickAfterNext(function()
                    provider.upload(url_base, self.address, self.username, self.password, file_path, callback_close)
                end)
            end
        end
    }
    UIManager:show(path_chooser)
end

function CloudStorageMenu:createFolder(url)
    local providers = self:getProviders()
    local provider = providers[self.type]
    if not provider or not provider.create_folder then
        UIManager:show(InfoMessage:new{
            text = _("Create folder not supported for this provider"),
            timeout = 3,
        })
        return
    end

    local input_dialog, check_button_enter_folder
    input_dialog = InputDialog:new{
        title = _("New folder"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local folder_name = input_dialog:getInputText()
                        if folder_name == "" then return end
                        UIManager:close(input_dialog)
                        local url_base = url ~= "/" and url or ""
                        local callback_close = function()
                            if check_button_enter_folder.checked then
                                table.insert(self.paths, {
                                    url = url,
                                })
                                url = url_base .. "/" .. folder_name
                            end
                            self:openCloudServer(url)
                        end
                        provider.create_folder(url_base, self.address, self.username, self.password, folder_name, callback_close)
                    end,
                },
            }
        },
    }
    check_button_enter_folder = CheckButton:new{
        text = _("Enter folder after creation"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_enter_folder)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function CloudStorageMenu:editCloudServer(item)
    local providers = self:getProviders()
    local provider = providers[item.type]
    if not provider then
        logger.err("CloudStorage:editCloudServer: Unknown provider", item.type)
        return
    end

    local function callbackEdit(fields)
        local cs_settings = self:readSettings()
        local cs_servers = cs_settings:readSetting("cs_servers") or {}

        for i, server in ipairs(cs_servers) do
            if server.name == item.text and server.type == item.type then
                -- Map fields to server config based on provider's config_fields
                for j, field_config in ipairs(provider.config_fields) do
                    server[field_config.name] = fields[j]
                end
                cs_servers[i] = server
                break
            end
        end

        cs_settings:saveSetting("cs_servers", cs_servers)
        cs_settings:flush()
        self:init()
    end

    -- Use declarative configuration for editing
    local dialog_config = {
        title = provider.config_title or T(_("Edit %1 account"), provider.name),
        fields = {},
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.config_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        if provider.config_info then
                            UIManager:show(InfoMessage:new{ text = provider.config_info })
                        end
                    end
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.config_dialog:getFields()
                        callbackEdit(fields)
                        UIManager:close(self.config_dialog)
                    end
                },
            },
        },
    }

    -- Pre-populate fields with existing values
    for _, field_config in ipairs(provider.config_fields) do
        table.insert(dialog_config.fields, {
            text = item[field_config.name] or "",
            hint = field_config.hint,
            input_type = field_config.input_type or "string",
            text_type = field_config.text_type,
        })
    end

    self.config_dialog = MultiInputDialog:new(dialog_config)
    UIManager:show(self.config_dialog)
    self.config_dialog:onShowKeyboard()
end

function CloudStorageMenu:deleteCloudServer(item)
    local cs_settings = self:readSettings()
    local cs_servers = cs_settings:readSetting("cs_servers") or {}
    for i, server in ipairs(cs_servers) do
        if server.name == item.text and server.type == item.type then
            table.remove(cs_servers, i)
            break
        end
    end
    cs_settings:saveSetting("cs_servers", cs_servers)
    cs_settings:flush()
    self:init()
end

function CloudStorageMenu:infoServer(item)
    local providers = self:getProviders()
    local provider = providers[item.type]
    if provider and provider.info then
        provider.info(item)
    else
        local info_text = T(_"Type: %1\nName: %2", provider and provider.name or item.type, item.text)
        UIManager:show(InfoMessage:new{text = info_text})
    end
end

-- Main plugin initialization and menu registration
function CloudStorage:init()
    self.ui.menu:registerToMainMenu(self)
end

function CloudStorage:addToMainMenu(menu_items)
    menu_items.cloud_storage = {
        text = _("Cloud storage"),
        sorting_hint = "tools",
        callback = function()
            self:showCloudStorage()
        end,
    }
end

function CloudStorage:showCloudStorage()
    local cloud_storage_menu = CloudStorageMenu:new{}
    UIManager:show(cloud_storage_menu)
end

-- Export CloudStorageMenu for use by other modules (like downloadmgr)
CloudStorage.CloudStorageMenu = CloudStorageMenu

return CloudStorage
