--[[--
This module provides a unified interface for managing presets across different KOReader modules.
It handles creation, loading, updating, and deletion of presets, as well as menu generation.

Usage:
    local Presets = require("ui/presets")

    -- 1. In your module's init() method, set up a preset object:
        self.preset_obj = {
            presets = G_reader_settings:readSetting("my_module_presets", {}),             -- or custom storage
            cycle_index = G_reader_settings:readSetting("my_module_presets_cycle_index"), -- optional, only needed if cycling through presets
            dispatcher_name = "load_my_module_preset",                                    -- must match dispatcher.lua entry
            saveCycleIndex = function(this)                                               -- Save cycle index to persistent storage
                G_reader_settings:saveSetting("my_module_presets_cycle_index", this.cycle_index)
            end,
            buildPreset = function() return self:buildPreset() end,                       -- Closure to build a preset from current state
            loadPreset = function(preset) self:loadPreset(preset) end,                    -- Closure to apply a preset to the module
        }

    -- 2. Implement required methods in your module:
        function MyModule:buildPreset()
            return {
                -- Return a table with the settings you want to save in the preset
                setting1 = self.setting1,
                setting2 = self.setting2,
                enabled_features = self.enabled_features,
            }
        end

        function MyModule:loadPreset(preset)
            -- Apply the preset settings to your module
            self.setting1 = preset.setting1
            self.setting2 = preset.setting2
            self.enabled_features = preset.enabled_features
            -- Update UI or perform other necessary changes
            self:refresh()
        end

    -- 3. Create menu items for presets: (Alternatively, you could call Presets.genPresetMenuItemTable directly from touchmenu_instance)
        function MyModule:genPresetMenuItemTable(touchmenu_instance)
            return Presets.genPresetMenuItemTable(
                self.preset_obj,                                 -- preset object
                _("Create new preset from current settings"),    -- optional: custom text for UI menu
                function() return self:hasValidSettings() end,   -- optional: function to enable/disable creating presets
            )
        end

    -- 4. Load a preset by name (for dispatcher/event handling):
        function MyModule:onLoadMyModulePreset(preset_name)
            return Presets.onLoadPreset(
                self.preset_obj,
                preset_name,
                true  -- show notification
            )
        end

    -- 5. Cycle through presets (for dispatcher/event handling):
        function MyModule:onCycleMyModulePresets()
            return Presets.cycleThroughPresets(
                self.preset_obj,
                true  -- show notification
            )
        end

    -- 6. Get list of available presets (for dispatcher):
        function MyModule.getPresets() -- Note: This is a static method on MyModule
            local config = {
                presets = G_reader_settings:readSetting("my_module_presets", {})
            }
            return Presets.getPresets(config)
        end

    -- 7. Add to dispatcher.lua:
        load_my_module_preset = {
            category = "string",
            event = "LoadMyModulePreset",
            title = _("Load my module preset"),
            args_func = MyModule.getPresets,
            reader = true
        },
        cycle_my_module_preset = {
            category = "none",
            event = "CycleMyModulePresets",
            title = _("Cycle through my module presets"),
            reader = true
        },

Required preset_obj fields:
    - presets: table containing saved presets
    - cycle_index: current index for cycling through presets (optional, defaults to 0)
    - dispatcher_name: string matching the dispatcher action name (for dispatcher integration)
    - saveCycleIndex(this): function to save cycle index (optional, only needed if cycling is used)

Required module methods:
    - buildPreset(): returns a table with the current settings to save as a preset
    - loadPreset(preset): applies the settings from the preset table to the module

The preset system handles:
    - Creating, updating, deleting, and renaming presets through UI dialogs
    - Generating menu items with hold actions for preset management
    - Saving/loading presets to/from G_reader_settings (or custom storage)
    - Cycling through presets with wrap-around
    - User notifications when presets are loaded/updated/created
    - Integration with Dispatcher for gesture/hotkey/profile support
    - Broadcasting events to update dispatcher when presets change
    - Input validation and duplicate name prevention
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

function Presets.editPresetName(options, preset_obj, on_success_callback)
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
                        local entered_preset_name = input_dialog:getInputText()
                        if entered_preset_name == "" or entered_preset_name:match("^%s*$") then
                            UIManager:show(InfoMessage:new{
                                text = _("Invalid preset name. Please choose a different name."),
                                timeout = 2,
                            })
                            return false
                        end
                        if options.initial_value and entered_preset_name == options.initial_value then
                            UIManager:close(input_dialog)
                            return false
                        end
                        if preset_obj.presets[entered_preset_name] then
                            UIManager:show(InfoMessage:new{
                                text = T(_("A preset named '%1' already exists. Please choose a different name."), entered_preset_name),
                                timeout = 2,
                            })
                            return false
                        end

                        -- If all validation passes, call the success callback
                        on_success_callback(entered_preset_name)
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Presets.genPresetMenuItemTable(preset_obj, text, enabled_func)
    local presets = preset_obj.presets
    local items = {
        {
            text = text or _("Create new preset from current settings"),
            keep_menu_open = true,
            enabled_func = enabled_func,
            callback = function(touchmenu_instance)
                Presets.editPresetName({}, preset_obj,
                    function(entered_preset_name)
                        local preset_data = preset_obj.buildPreset()
                        preset_obj.presets[entered_preset_name] = preset_data
                        touchmenu_instance.item_table = Presets.genPresetMenuItemTable(preset_obj, text, enabled_func)
                        touchmenu_instance:updateItems()
                    end
                )
            end,
            separator = true,
        },
    }
    for preset_name in ffiUtil.orderedPairs(presets) do
        table.insert(items, {
            text = preset_name,
            keep_menu_open = true,
            callback = function()
                preset_obj.loadPreset(presets[preset_name])
                -- There's no guarantee that it'll be obvious to the user that the preset was loaded so, we show a notification.
                UIManager:show(InfoMessage:new{
                    text = T(_("Preset '%1' loaded successfully."), preset_name),
                    timeout = 2,
                })
            end,
            hold_callback = function(touchmenu_instance, item)
                UIManager:show(ConfirmBox:new{
                    text = T(_("What would you like to do with preset '%1'?"), preset_name),
                    icon = "notice-question",
                    ok_text = _("Update"),
                    ok_callback = function()
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Are you sure you want to overwrite preset '%1' with current settings?"), preset_name),
                            ok_callback = function()
                                presets[preset_name] = preset_obj.buildPreset()
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
                                            local action_key = preset_obj.dispatcher_name
                                            if action_key then
                                                UIManager:broadcastEvent(Event:new("DispatcherActionValueChanged", {
                                                    name = action_key,
                                                    old_value = preset_name,
                                                    new_value = nil -- delete the action
                                                }))
                                            end
                                            table.remove(touchmenu_instance.item_table, item.idx)
                                            touchmenu_instance:updateItems()
                                        end,
                                    })
                                end,
                            },
                            {
                                text = _("Rename"),
                                callback = function()
                                    Presets.editPresetName({
                                        title = _("Enter new preset name"),
                                        initial_value = preset_name,
                                        confirm_button_text = _("Rename"),
                                    }, preset_obj,
                                    function(new_name)
                                        presets[new_name] = presets[preset_name]
                                        presets[preset_name] = nil
                                        local action_key = preset_obj.dispatcher_name
                                        if action_key then
                                            UIManager:broadcastEvent(Event:new("DispatcherActionValueChanged", {
                                                name = action_key,
                                                old_value = preset_name,
                                                new_value = new_name
                                            }))
                                        end
                                        touchmenu_instance.item_table = Presets.genPresetMenuItemTable(preset_obj, text, enabled_func)
                                        touchmenu_instance:updateItems()
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


function Presets.onLoadPreset(preset_obj, preset_name, show_notification)
    local presets = preset_obj.presets
    if presets and presets[preset_name] then
        preset_obj.loadPreset(presets[preset_name])
        if show_notification then
            Notification:notify(T(_("Preset '%1' was loaded"), preset_name))
        end
    end
    return true
end

function Presets.cycleThroughPresets(preset_obj, show_notification)
    local preset_names = Presets.getPresets(preset_obj)
    if #preset_names == 0 then
        Notification:notify(_("No presets available"), Notification.SOURCE_ALWAYS_SHOW)
        return true -- we *must* return true here to prevent further event propagation, i.e multiple notifications
    end
    -- Get and increment index, wrap around if needed
    local index = (preset_obj.cycle_index or 0) + 1
    if index > #preset_names then
        index = 1
    end
    local next_preset_name = preset_names[index]
    preset_obj.loadPreset(preset_obj.presets[next_preset_name])
    preset_obj.cycle_index = index
    preset_obj:saveCycleIndex()
    if show_notification then
        Notification:notify(T(_("Loaded preset: %1"), next_preset_name))
    end
    return true
end

function Presets.getPresets(preset_obj)
    local presets = preset_obj.presets
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
