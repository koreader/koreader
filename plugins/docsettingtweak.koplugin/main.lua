local Device = require("device")

if not Device:isTouchDevice() then
    return { disabled = true }
end

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local DocSettingTweak = WidgetContainer:extend{
    name = "docsettingtweak",
}

local directory_defaults_name = "directory_defaults.lua"
local directory_defaults_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), directory_defaults_name)
local directory_defaults = nil
local initialized = false

function DocSettingTweak:init()
    if not initialized then
        -- Make sure our settings file exists
        if not lfs.attributes(directory_defaults_path, "mode") then
            FFIUtil.copyFile(FFIUtil.joinPath(self.path, "directory_defaults_template.lua"),
                         directory_defaults_path)
        end
        initialized = true
    end
    DocSettingTweak:loadDefaults()
    self.ui.menu:registerToMainMenu(self)
end

function DocSettingTweak:loadDefaults()
    directory_defaults = LuaSettings:open(directory_defaults_path)
end

function DocSettingTweak:addToMainMenu(menu_items)
    menu_items.doc_setting_tweak = {
        text = _("Tweak document settings"),
        callback = function() DocSettingTweak:editDirectoryDefaults() end,
    }
end

function DocSettingTweak:editDirectoryDefaults()
    local defaults = util.readFromFile(directory_defaults_path, "rb")
    local config_editor
    config_editor = InputDialog:new{
        title = T(_("Directory Defaults: %1"), BD.filepath(directory_defaults_path)),
        input = defaults,
        input_type = "string",
        para_direction_rtl = false, -- force LTR
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = function()
            return defaults
        end,
        save_callback = function(content)
            if content and #content > 0 then
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local syntax_okay, syntax_error = pcall(loadstring(content))
                    if syntax_okay then
                        if not util.writeToFile(content, directory_defaults_path) then
                            return false, _("Missing defaults file")
                        end
                        DocSettingTweak:loadDefaults()
                        return true, _("Defaults saved")
                    end
                    return false, T(_("Defaults invalid: %1"), syntax_error)
                end
                return false, T(_("Defaults invalid: %1"), parse_error)
            end
            return false, _("Defaults empty")
        end,
    }
    UIManager:show(config_editor)
    config_editor:onShowKeyboard()
end

function DocSettingTweak:onDocSettingsLoad(doc_settings, document)
    -- check that the document has not been opened yet & and that we have defaults to customize
    if document.is_new and directory_defaults.data ~= nil then
        local base = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        local directory = FFIUtil.dirname(document.file)
        -- check if folder matches our defaults to override
        while directory:sub(1, #base) == base do
            if directory_defaults:has(directory) then
                local summary = doc_settings.data.summary -- keep status
                doc_settings.data = util.tableDeepCopy(directory_defaults:readSetting(directory))
                doc_settings.data.doc_path = document.file
                doc_settings.data.summary = doc_settings.data.summary or summary
                break
            else
                if directory == "/" or directory == "." then
                    -- have reached the filesystem root, abort
                    break
                else
                    directory = FFIUtil.dirname(directory)
                end
            end
        end
    end
end

return DocSettingTweak
