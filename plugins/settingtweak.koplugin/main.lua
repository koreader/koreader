local DataStorage = require("datastorage")
local FFIUtil = require("ffi/util")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = FFIUtil.template
local dump = require("dump")
local util = require("util")


local SettingTweak = WidgetContainer:new{
    name = 'settingtweak',
}


local undefined_settings_cache_dir = table.concat({DataStorage:getDataDir(), "cache", "settingtweak"}, '/')
local undefined_settings_cache = FFIUtil.joinPath(undefined_settings_cache_dir, "undefined_settings.lua")
local initialized = false

function SettingTweak:init()
    if not initialized then
        lfs.mkdir(undefined_settings_cache_dir)
        local luasettings = LuaSettings
        luasettings._undefined_settings = {}
        local init = luasettings.init
        local delSetting = luasettings.delSetting
        local readSetting = luasettings.readSetting
        local saveSetting = luasettings.saveSetting
        function luasettings.init(_self, ...)
            init(_self, ...)
            _self._undefined_settings = {}
        end
        function luasettings.delSetting(_self, k, ...)
            _self._undefined_settings[k] = nil
            return delSetting(_self, k, ...)
        end
        function luasettings.readSetting(_self, k, ...)
            if _self[k] == nil then
                _self._undefined_settings[k] = true
            end
            return readSetting(_self, k, ...)
        end
        function luasettings.saveSetting(_self, k, ...)
            _self._undefined_settings[k] = nil
            return saveSetting(_self, k, ...)
        end
        initialized = true
    end
    local input_file = io.open(undefined_settings_cache)
    if input_file then
        local ok, undefined_settings = pcall(loadstring(input_file:read("*a"):gsub("nil,", "true,")))
        input_file:close()
        if ok then
            G_reader_settings._undefined_settings = undefined_settings
        end
    end
    self.ui.menu:registerToMainMenu(self)
end

function SettingTweak:addToMainMenu(menu_items)
    menu_items.global_setting_tweak = {
        text = _("Tweak global settings"),
        sorting_hint = "more_tools",
        callback = function() SettingTweak:editSettings() end,
    }
end

function SettingTweak:editSettings()
    local concat, insert = table.concat, table.insert
    local settings_tbl = util.splitToArray(
        dump(G_reader_settings.data, nil, true), "\n", true
    )
    settings_tbl[1] = settings_tbl[1] .. "  -- Don't change or remove this line."
    settings_tbl[#settings_tbl] = settings_tbl[#settings_tbl] .. "  -- Don't change or remove this line."
    insert(settings_tbl, 2, _("\n---- Following settings are defined. ----\n"))
    insert(settings_tbl, #settings_tbl, _("\n---- Following settings aren't defined yet. ----\n"))
    for k in FFIUtil.orderedPairs(G_reader_settings._undefined_settings) do
        insert(settings_tbl, #settings_tbl, '    ["' .. k .. '"] = nil,')
    end
    local settings_str = "return " .. concat(settings_tbl, "\n")
    local config_editor = InputDialog:new{
        title = _("Tweak global settings"),
        input = settings_str,
        input_type = "string",
        para_direction_rtl = false, -- force LTR
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        reset_callback = function()
            return settings_str
        end,
        save_callback = function(content)
            if content and #content > 0 then
                local parse_error = util.checkLuaSyntax(content)
                if not parse_error then
                    local syntax_okay, settings_or_error = pcall(loadstring(content))
                    if syntax_okay then
                        for k, v in pairs(settings_or_error) do
                            G_reader_settings:saveSetting(k, v)
                        end
                        return true, _("Settings saved")
                    else
                        return false, T(_("Settings invalid: %1"), settings_or_error)
                    end
                else
                    return false, T(_("Settings invalid: %1"), parse_error)
                end
            end
            return false, _("Settings empty")
        end,
    }
    UIManager:show(config_editor)
    config_editor:onShowKeyboard()
end

function SettingTweak:onSaveSettings()
    local output_file = io.open(undefined_settings_cache, "w")
    if output_file then
        output_file:write((dump(G_reader_settings._undefined_settings, nil, true):gsub("true,", "nil,")))
        output_file:close()
    end
end

return SettingTweak
