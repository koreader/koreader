--[[
This module provides a unified interface for managing presets across different KOReader modules.
It handles creation, loading, updating, and deletion of presets, as well as menu generation.

    Usage example:
        local Presets = require("ui/presets")

        -- In your module:
        function MyModule:buildPreset()
            return {
                -- Return a table with the settings you want to save
                setting1 = self.setting1,
                setting2 = self.setting2,
            }
        end

        function MyModule:loadPreset(preset)
            -- Apply the preset settings to your module
            self.setting1 = preset.setting1
            self.setting2 = preset.setting2
            -- Update UI or other necessary changes
            self:refresh()
        end

        -- To create menu items for presets:
        function MyModule:genPresetMenuItemTable()
            return Presets:genModulePresetMenuTable(
                self,
                "my_module_presets", -- preset key for settings
                _("Create new preset") -- optional custom text
            )
        end

        -- To create a new preset:
        function MyModule:createPresetFromCurrentSettings(touchmenu_instance)
            return Presets:createModulePreset(self, touchmenu_instance, "my_module_presets")
        end

        -- To load a preset by name:
        function MyModule:onLoadPreset(preset_name)
            return Presets:onLoadPreset(self, preset_name, "my_module_presets", true)
        end

        -- To get list of available presets:
        function MyModule.getPresets()
            return Presets:getPresets("my_module_presets")
        end

Required module methods:
- buildPreset(): returns a table with the settings to save
- loadPreset(preset): applies the settings from the preset table

The preset system handles:
- Saving/loading presets to/from G_reader_settings
- Creating and managing preset menu items
- User interface for creating/updating/deleting presets
- Notifications when presets are loaded/updated
- Adding actions to Dispatcher for loading presets through gestures/hotkeys/profiles
--]]

local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local Notification = require("ui/widget/notification")
local T = require("ffi/util").template
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local Presets = {}

function Presets:createPresetFromCurrentSettings(touchmenu_instance, preset_name_key, buildPresetFunc, genPresetMenuItemTableFunc)
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Enter preset name"),
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
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local preset_name = input_dialog:getInputText()
                        if preset_name == "" or preset_name:match("^%s*$") then return end
                        local presets = G_reader_settings:readSetting(preset_name_key, {})
                        if presets[preset_name] then
                            UIManager:show(InfoMessage:new{
                                text = T(_("A preset named '%1' already exists. Please choose a different name."), preset_name),
                                timeout = 2,
                            })
                        else
                            presets[preset_name] = buildPresetFunc()
                            G_reader_settings:saveSetting(preset_name_key, presets)
                            UIManager:close(input_dialog)
                            touchmenu_instance.item_table = genPresetMenuItemTableFunc()
                            touchmenu_instance:updateItems()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Presets:genPresetMenuItemTable(preset_name_key, text, buildPresetFunc, loadPresetFunc, genPresetMenuItemTableFunc)
    local presets = G_reader_settings:readSetting(preset_name_key, {})
    local items = {
        {
            text = text or _("Create new preset from current settings"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:createPresetFromCurrentSettings(touchmenu_instance, preset_name_key, buildPresetFunc, genPresetMenuItemTableFunc)
            end,
            separator = true,
        },
    }
    for preset_name in ffiUtil.orderedPairs(presets) do
        table.insert(items, {
            text = preset_name,
            keep_menu_open = true,
            callback = function()
                loadPresetFunc(presets[preset_name])
            end,
            hold_callback = function(touchmenu_instance)
                UIManager:show(MultiConfirmBox:new{
                    text = T(_("What would you like to do with preset '%1'?"), preset_name),
                    choice1_text = _("Delete"),
                    choice1_callback = function()
                        presets[preset_name] = nil
                        G_reader_settings:saveSetting(preset_name_key, presets)
                        touchmenu_instance.item_table = genPresetMenuItemTableFunc()
                        touchmenu_instance:updateItems()
                    end,
                    choice2_text = _("Update"),
                    choice2_callback = function()
                        presets[preset_name] = buildPresetFunc()
                        G_reader_settings:saveSetting(preset_name_key, presets)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Preset '%1' was updated with current settings"), preset_name),
                            timeout = 2,
                        })
                    end,
                })
            end,
        })
    end
    return items
end

-- Simplified interface for modules that need to create presets
function Presets:createModulePreset(module, touchmenu_instance, preset_key)
    return self:createPresetFromCurrentSettings(
        touchmenu_instance,
        preset_key,
        function() return module:buildPreset() end,
        function() return module:genPresetMenuItemTable() end
    )
end

function Presets:genModulePresetMenuTable(module, preset_key, text)
    return self:genPresetMenuItemTable(
        preset_key,
        text,
        function() return module:buildPreset() end,
        function(preset) module:loadPreset(preset) end,
        function() return module:genPresetMenuItemTable() end
    )
end

function Presets:onLoadPreset(module, preset_name, preset_key, show_notification)
    local presets = G_reader_settings:readSetting(preset_key)
    if presets and presets[preset_name] then
        module:loadPreset(presets[preset_name])
        if show_notification then
            Notification:notify(T(_("Preset '%1' was loaded"), preset_name))
        end
    end
    return true
end

function Presets:getPresets(preset_name_key) -- for Dispatcher
    local presets = G_reader_settings:readSetting(preset_name_key)
    local actions = {}
    if presets and next(presets) then
        for preset_name in pairs(presets) do
            table.insert(actions, preset_name)
        end
        if #actions > 1 then
            table.sort(actions)
        end
    end
    return actions, actions
end

return Presets
