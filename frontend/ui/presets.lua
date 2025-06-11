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

local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local T = require("ffi/util").template
local _ = require("gettext")

local Presets = {}

function Presets:createPresetFromCurrentSettings(touchmenu_instance, preset_config, buildPresetFunc, genPresetMenuItemTableFunc)
    self:editPresetName({},
        function(entered_preset_name, dialog_instance)
        if self:validateAndSavePreset(entered_preset_name, preset_config, buildPresetFunc()) then
            UIManager:close(dialog_instance)
            touchmenu_instance.item_table = genPresetMenuItemTableFunc()
            touchmenu_instance:updateItems()
        end
        -- If validateAndSavePreset returns false, it means validation failed (e.g., duplicate name),
        -- an InfoMessage was shown by validateAndSavePreset, and the dialog remains open.
    end)
end

function Presets:editPresetName(options, on_confirm_callback)
    local input_dialog
    input_dialog = InputDialog:new{
        title = options.title or _("Enter preset name"),
        input = options.initial_value or "",
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
                    text = options.confirm_button_text or _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local entered_text = input_dialog:getInputText()
                        on_confirm_callback(entered_text, input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Presets:genPresetMenuItemTable(module, preset_config, text, enabled_func, buildPresetFunc, loadPresetFunc, genPresetMenuItemTableFunc)
    local presets = preset_config.presets
    local items = {
        {
            text = text or _("Create new preset from current settings"),
            keep_menu_open = true,
            enabled_func = enabled_func,
            callback = function(touchmenu_instance)
                self:createPresetFromCurrentSettings(touchmenu_instance, preset_config, buildPresetFunc, genPresetMenuItemTableFunc)
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
                -- There's no guarantee that it'll be obvious to the user that the preset was loaded so, we show a notification.
                UIManager:show(InfoMessage:new{
                    text = T(_("Preset '%1' loaded successfully."), preset_name),
                    timeout = 2,
                })
            end,
            hold_callback = function(touchmenu_instance)
                UIManager:show(ConfirmBox:new{
                    text = T(_("What would you like to do with preset '%1'?"), preset_name),
                    icon = "notice-question",
                    ok_text = _("Update"),
                    ok_callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Are you sure you want to overwrite preset '%1' with current settings?"), preset_name),
                            ok_callback = function()
                                presets[preset_name] = buildPresetFunc()
                                preset_config:save()
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Preset '%1' was updated with current settings"), preset_name),
                                    timeout = 2,
                                })
                            end,
                        })
                    end,
                    other_buttons_first = true,
                    other_buttons = {
                        {
                            {
                                text = _("Delete"),
                                callback = function()
                                    UIManager:show(ConfirmBox:new{
                                        text = T(_("Are you sure you want to delete preset '%1'?"), preset_name),
                                        ok_text = _("Delete"),
                                        ok_callback = function()
                                            presets[preset_name] = nil
                                            preset_config:save()
                                            local action_key = self:_getTargetActionKeyForModule(module, preset_name)
                                            if action_key then
                                                UIManager:broadcastEvent(Event:new("DispatcherActionValueChanged", {
                                                    name = action_key,
                                                    old_value = preset_name,
                                                    new_value = nil -- delete the action
                                                }))
                                            end
                                            touchmenu_instance.item_table = genPresetMenuItemTableFunc()
                                            touchmenu_instance:updateItems()
                                        end,
                                    })
                                end,
                            },
                            {
                                text = _("Rename"),
                                callback = function()
                                    self:editPresetName({
                                        title = _("Enter new preset name"),
                                        initial_value = preset_name,
                                        confirm_button_text = _("Rename"),
                                    }, function(new_name, dialog_instance)
                                        if new_name == preset_name then
                                            UIManager:close(dialog_instance) -- no change?, just close then
                                            return
                                        end
                                        if self:validateAndSavePreset(new_name, preset_config, presets[preset_name]) then
                                            presets[preset_name] = nil
                                            preset_config:save()
                                            local action_key = self:_getTargetActionKeyForModule(module, preset_name)
                                            if action_key then
                                                UIManager:broadcastEvent(Event:new("DispatcherActionValueChanged", {
                                                    name = action_key,
                                                    old_value = preset_name,
                                                    new_value = new_name
                                                }))
                                            end
                                            touchmenu_instance.item_table = genPresetMenuItemTableFunc()
                                            touchmenu_instance:updateItems()
                                            UIManager:close(dialog_instance)
                                        end
                                    end) -- editPresetName
                                end, -- rename callback
                            },
                        },
                    }, -- end of other_buttons
                }) -- end of ConfirmBox
            end, -- hold_callback
        }) -- end of table.insert
    end -- for each preset
    return items
end

function Presets:validateAndSavePreset(preset_name, preset_config, preset_data)
    if preset_name == "" or preset_name:match("^%s*$") then return end
    if preset_config.presets[preset_name] then
        UIManager:show(InfoMessage:new{
            text = T(_("A preset named '%1' already exists. Please choose a different name."), preset_name),
            timeout = 2,
        })
        return false
    end
    preset_config.presets[preset_name] = preset_data
    preset_config:save() -- Let the module handle its own saving
    return true
end

function Presets:_getTargetActionKeyForModule(module, preset_name)
    -- We need to make sure we only update the name of the preset the user is currently interacting with,
    -- since preset names are not unique across modules and we don't use uuids, we need to be careful about
    -- updating/deleting the correct preset.
    local Dispatcher = require("dispatcher") -- we **must** require this here to avoid circular dependencies
    local module_get_presets_func = module.getPresets
    if not module_get_presets_func then return end

    -- Helper function to search within a specific settings data source (e.g., hotkeys or gestures)
    -- for the module's specific preset action key.
    local function find_key_in_specific_settings(settings_data_source, relevant_section_names)
        if not settings_data_source or not settings_data_source.data then return end
        for _, section_name in ipairs(relevant_section_names) do
            local section_content = settings_data_source.data[section_name]
            if section_content then
                for _, actions in pairs(section_content) do -- Iterate through key bindings/gestures
                    for action_key, action_value in pairs(actions) do
                        -- We check action_value against preset_name to find actions using this preset.
                        -- The crucial part is the args_func comparison to ensure it's THIS module's action.
                        if action_value == preset_name then
                            local action_args_func = Dispatcher:getActionArgsFunc(action_key)
                            if module_get_presets_func and action_args_func == module_get_presets_func then
                                return action_key -- Found the key for this module
                            end
                        end
                    end
                end
            end
        end
        return nil -- Key not found in this settings source
    end -- find_key_in_specific_settings()

    if module.ui.hotkeys and module.ui.hotkeys.settings_data then
        local found_key = find_key_in_specific_settings(module.ui.hotkeys.settings_data, {"hotkeys_reader", "hotkeys_fm"})
        if found_key then return found_key end
    end
    if module.ui.gestures and module.ui.gestures.settings_data then
        local found_key = find_key_in_specific_settings(module.ui.gestures.settings_data, {"gesture_reader", "gesture_fm"})
        if found_key then return found_key end
    end
    return nil -- key not found
end -- _getTargetActionKeyForModule()

--[[
    The following couple of functions are simplified interfaces for modules that need to create presets.
    They handle the creation of presets and the generation of preset menu items.
    These functions are intended to be used by modules that need to create presets without
    having to implement the full preset management logic themselves.
]]

function Presets:createModulePreset(module, touchmenu_instance)
    return self:createPresetFromCurrentSettings(
        touchmenu_instance,
        module.preset_config,
        function() return module:buildPreset() end,
        function() return module:genPresetMenuItemTable() end
    )
end

function Presets:genModulePresetMenuTable(module, text, enabled_func)
    return self:genPresetMenuItemTable(
        module,
        module.preset_config,
        text,
        enabled_func,
        function() return module:buildPreset() end,
        function(preset) module:loadPreset(preset) end,
        function() return module:genPresetMenuItemTable() end
    )
end

function Presets:onLoadPreset(module, preset_name, show_notification)
    local presets = module.preset_config.presets
    if presets and presets[preset_name] then
        module:loadPreset(presets[preset_name])
        if show_notification then
            Notification:notify(T(_("Preset '%1' was loaded"), preset_name))
        end
    end
    return true
end

function Presets:cycleThroughPresets(module, show_notification)
    local preset_names = self:getPresets(module.preset_config)
    if #preset_names == 0 then
        Notification:notify(_("No presets available"), Notification.SOURCE_ALWAYS_SHOW)
        return true -- we *must* return true here to prevent further event propagation, i.e multiple notifications
    end
    -- Get and increment index, wrap around if needed
    local index = module.preset_config.cycle_index + 1
    if index > #preset_names then
        index = 1
    end
    local next_preset_name = preset_names[index]
    module:loadPreset(module.preset_config.presets[next_preset_name])
    module.preset_config.cycle_index = index
    module.preset_config:saveCycleIndex()
    if show_notification then
        Notification:notify(T(_("Loaded preset: %1"), next_preset_name))
    end
    return true
end

function Presets:getPresets(preset_config)
    local presets = preset_config.presets
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
