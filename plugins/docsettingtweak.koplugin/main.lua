local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local DocSettingTweak = WidgetContainer:extend{
    name = "docsettingtweak",
    settings_file = DataStorage:getSettingsDir() .. "/directory_defaults.lua",
}

function DocSettingTweak:init()
    if Device:isTouchDevice() or not Device:hasFewKeys() then
        -- cannot exit from text editor on non-touch devices with few keys
        self.ui.menu:registerToMainMenu(self)
    end
end

function DocSettingTweak:addToMainMenu(menu_items)
    menu_items.doc_setting_tweak = {
        text = _("Tweak document settings"),
        callback = function()
            DocSettingTweak:editDirectoryDefaults()
        end,
    }
end

function DocSettingTweak:editDirectoryDefaults()
    if not lfs.attributes(self.settings_file, "mode") then
        ffiUtil.copyFile(ffiUtil.joinPath(self.path, "directory_defaults_template.lua"), self.settings_file)
    end
    local defaults = util.readFromFile(self.settings_file, "rb")
    local config_editor
    config_editor = InputDialog:new{
        title = T(_("Directory Defaults: %1"), BD.filepath(self.settings_file)),
        input = defaults,
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
                        if not util.writeToFile(content, self.settings_file) then
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
    if document.is_new and lfs.attributes(self.settings_file, "mode") == "file" then
        local directory_defaults = LuaSettings:open(self.settings_file)
        if directory_defaults.data == nil then return true end
        local base = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
        local absolute_path = ffiUtil.realpath(document.file)
        local directory = ffiUtil.dirname(absolute_path)
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
                    directory = ffiUtil.dirname(directory)
                end
            end
        end
    end
    return true -- unique handler at the moment
end

return DocSettingTweak
