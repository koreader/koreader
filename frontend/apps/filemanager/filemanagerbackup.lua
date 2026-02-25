local Archiver = require("ffi/archiver")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local dump = require("dump")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local random = require("random")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local device_id = G_reader_settings:readSetting("device_id", random.uuid())
local root_path = DataStorage:getFullDataDir():match("(.*)/.*") -- remove ending "/koreader"
local data_dir = DataStorage:getDataDir()
local default_backup_folder = data_dir .. "/backup"
local settings = G_reader_settings:readSetting("backup", {})

local sections = {
    "g_settings",  -- koreader/settings.reader.lua, koreader/defaults.custom.lua,
                   -- config set from koreader/settings/bookinfo_cache.sqlite3 (CoverBrowser)
    "history",     -- koreader/history.lua
    "plugins",     -- koreader/settings/*.lua
    "styletweaks", -- koreader/styletweaks/*.css (including subfolders)
}

local section_text = {
    g_settings  = _("program settings"),
    history     = _("history"),
    plugins     = _("plugins settings"),
    styletweaks = _("user style tweaks"),
}

local FileManagerBackup = {}

function FileManagerBackup:genBackupMenu(ui)
    self.ui = ui
    util.makePath(settings.backup_folder or default_backup_folder)
    local item_table = {
        {
            text_func = function()
                return T(_("Backup folder: %1"), ffiUtil.realpath(settings.backup_folder or default_backup_folder))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local title_header = _("Current backup folder:")
                local current_path = ffiUtil.realpath(settings.backup_folder or default_backup_folder)
                local default_path = ffiUtil.realpath(default_backup_folder)
                local caller_callback = function(path)
                    settings.backup_folder = path ~= default_path and path or nil
                    touchmenu_instance:updateItems()
                end
                filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
            end,
        },
        {
            text = _("Show backup folder"),
            callback = function()
                ui.file_chooser:changeToPath(ffiUtil.realpath(settings.backup_folder or default_backup_folder))
            end,
            separator = true,
        },
        {
            text = _("Back up"),
            enabled_func = function()
                for _, section in ipairs(sections) do
                    if settings[section] then
                        return true
                    end
                end
                return false
            end,
            keep_menu_open = true,
            callback = function()
                self:backUpSettings()
            end,
        },
    }
    for _, section in ipairs(sections) do
        table.insert(item_table, {
            text = section_text[section],
            checked_func = function()
                return settings[section] and true or false
            end,
            callback = function()
                settings[section] = not settings[section] or nil
            end,
        })
    end
    item_table[#item_table].separator = true
    table.insert(item_table, {
        text = _("Restore"),
        keep_menu_open = true,
        callback = function()
            self:chooseBackupFile()
        end,
    })
    return item_table
end

function FileManagerBackup:backUpSettings()
    UIManager:flushSettings()
    local now = os.date("%Y-%m-%d %H:%M:%S")
    local backup = {
        config = {
            date_time = now,
            device_id = device_id,
            model = Device.model,
            root_path = root_path,
        },
    }
    local function back_up_file(section, settings_file, settings_file_path)
        if settings_file_path == nil then
            settings_file_path = data_dir .. "/" .. settings_file
            if lfs.attributes(settings_file_path, "mode") ~= "file" then return end
        end
        backup[section][settings_file] = util.readFromFile(settings_file_path, "rb")
    end
    if settings.g_settings then
        backup.g_settings = { coverbrowser = self.ui.coverbrowser and self.ui.coverbrowser.getConfigSet() }
        back_up_file("g_settings", "settings.reader.lua")
        back_up_file("g_settings", "defaults.custom.lua")
    end
    if settings.history then
        backup.history = {}
        back_up_file("history", "history.lua")
    end
    if settings.plugins then
        backup.plugins = {}
        local dir = DataStorage:getSettingsDir()
        util.findFiles(dir, function(path, f)
            if f:match("%.lua$") and not util.stringStartsWith(f, "._") then
                back_up_file("plugins", f, path)
            end
        end, false)
    end
    if settings.styletweaks then
        backup.styletweaks = {}
        local dir = data_dir .. "/styletweaks"
        util.findFiles(dir, function(path, f)
            if f:match("%.css$") and not util.stringStartsWith(f, "._") then
                back_up_file("styletweaks", path:gsub(dir .. "/", ""), path)
            end
        end) -- include subfolders
    end
    local content = "return " .. dump(backup, nil, true) .. "\n"
    local backup_file = T("%1/backup %2.zip", settings.backup_folder or default_backup_folder, now:gsub(":", "-"))
    local arc = Archiver.Writer:new{}
    if arc:open(backup_file) then
        arc:addFileFromMemory("backup", content)
        arc:close()
        UIManager:show(InfoMessage:new{ text = _("The settings have been backed up") })
    end
end

function FileManagerBackup:chooseBackupFile()
    UIManager:show(PathChooser:new{
        select_directory = false,
        file_filter = function(filename)
            local _, ext = filemanagerutil.splitFileNameType(filename)
            return ext == "zip"
        end,
        path = ffiUtil.realpath(settings.backup_folder or default_backup_folder),
        onConfirm = function(new_path)
            local backup
            local arc = Archiver.Reader:new()
            if arc:open(new_path) then
                for entry in arc:iterate() do
                    if entry.path == "backup" then
                        backup = arc:extractToMemory("backup")
                        backup = backup and loadstring(backup)
                        backup = backup and backup()
                        break
                    end
                end
                arc:close()
            end
            if type(backup) ~= "table" then
                UIManager:show(InfoMessage:new{ text = _("Invalid backup file") })
                return
            end

            local button_dialog
            local check_buttons = {}
            local buttons = {
                {
                    {
                        text = _("Cancel"),
                        callback = function()
                            UIManager:close(button_dialog)
                        end,
                    },
                    {
                        text = _("Restore"),
                        callback = function()
                            for _, section in ipairs(sections) do
                                if check_buttons[section].checked then
                                    UIManager:close(button_dialog)
                                    return self:restoreSettings(backup, check_buttons)
                                end
                            end
                        end,
                    },
                },
            }
            button_dialog = ButtonDialog:new{
                title = T(_("Backup date: %1\nSource device: %2"), backup.config.date_time,
                    device_id == backup.config.device_id and _("this device") or backup.config.model),
                width_factor = 0.8,
                buttons = buttons,
            }
            for i, section in ipairs(sections) do
                check_buttons[section] = CheckButton:new{
                    text = section_text[section],
                    enabled = backup[section] and true or false,
                    checked = backup[section] and true or false,
                    parent = button_dialog,
                }
                if i == #sections and device_id ~= backup.config.device_id then
                    check_buttons[section].separator = true
                end
                button_dialog:addWidget(check_buttons[section])
            end
            if device_id ~= backup.config.device_id then
                check_buttons["preserve_paths"] = CheckButton:new{
                    text = _("preserve paths in settings"),
                    checked = true,
                    parent = button_dialog,
                }
                button_dialog:addWidget(check_buttons["preserve_paths"])
            end
            UIManager:show(button_dialog)
        end,
    })
end

function FileManagerBackup:restoreSettings(backup, check_buttons)
    local g_settings_to_keep = {
        backup = true,
        device_id = true,
        dicts_disabled = true,
        dicts_order = true,
        folder_shortcuts = true,
        last_migration_date = true,
        lastdir = true,
        lastfile = true,
        quickstart_shown_version = true,
    }
    local function update_path(new_setting, old_setting)
        if util.stringStartsWith(new_setting, backup.config.root_path) then
            if check_buttons.preserve_paths and check_buttons.preserve_paths.checked then
                new_setting = old_setting
            else -- replace root path
                new_setting = new_setting:gsub("^" .. backup.config.root_path, root_path)
            end
        end
        return new_setting
    end
    self.ui:onClose()
    if check_buttons.g_settings.checked then
        if backup.g_settings.coverbrowser and self.ui.coverbrowser then
            self.ui.coverbrowser.saveConfigSet(backup.g_settings.coverbrowser)
        end
        local reader_settings = loadstring(backup.g_settings["settings.reader.lua"])()
        for k, v in pairs(reader_settings) do
            local curr_setting = G_reader_settings:readSetting(k)
            if g_settings_to_keep[k] then
                reader_settings[k] = curr_setting
            else
                if type(v) == "string" then
                    reader_settings[k] = update_path(v, curr_setting)
                elseif k == "exporter" and v.clipping_dir ~= nil then
                    reader_settings[k].clipping_dir = update_path(v.clipping_dir, curr_setting.clipping_dir)
                end
            end
        end
        G_reader_settings.data = reader_settings
        G_reader_settings:flush()
        if backup.g_settings["defaults.custom.lua"] then
            util.writeToFile(backup.g_settings["defaults.custom.lua"], data_dir .. "/defaults.custom.lua", true)
        end
    end
    if check_buttons.history.checked then
        util.writeToFile(backup.history["history.lua"], data_dir .. "/history.lua", true)
    end
    if check_buttons.plugins.checked then
        local dir = DataStorage:getSettingsDir() .. "/"
        for file, content in pairs(backup.plugins) do
            util.writeToFile(content, dir .. file, true)
        end
    end
    if check_buttons.styletweaks.checked then
        local dir = data_dir .. "/styletweaks/"
        for file, content in pairs(backup.styletweaks) do
            local file_path = dir .. file -- 'file' may include subfolders
            util.makePath(ffiUtil.dirname(file_path))
            util.writeToFile(content, file_path, true)
        end
    end
    if Device:canRestart() then
        UIManager:restartKOReader()
    else
        UIManager:quit()
    end
end

return FileManagerBackup
