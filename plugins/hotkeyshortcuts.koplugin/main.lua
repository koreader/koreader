local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local T = FFIUtil.template
local _ = require("gettext")

if not (Device:hasScreenKB() or Device:hasKeyboard()) then
    return { disabled = true, }
end

local HotKeyShortcuts = InputContainer:extend{
    name = "hotkeyshortcuts",
    settings_data = nil,
    hotkeyshortcuts = nil,
    defaults = nil,
    updated = false,
}
local hotkeyshortcuts_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), "hotkeyshortcuts.lua")

-- mofifier *here* refers to either screenkb or shift
local hotkeyshortcuts_list = {
    -- cursor keys
    modifier_plus_up                 = Device:hasScreenKB() and _("ScreenKB + Up")      or _("Shift + Up"),
    modifier_plus_down               = Device:hasScreenKB() and _("ScreenKB + Down")    or _("Shift + Down"),
    modifier_plus_left               = Device:hasScreenKB() and _("ScreenKB + Left")    or _("Shift + Left"),
    modifier_plus_right              = Device:hasScreenKB() and _("ScreenKB + Right")   or _("Shift + Right"),
    -- page turn buttons
    modifier_plus_left_page_back     = Device:hasScreenKB() and _("ScreenKB + LPgBack") or _("Shift + LPgBack"),
    modifier_plus_left_page_forward  = Device:hasScreenKB() and _("ScreenKB + LPgFwd")  or _("Shift + LPgFwd"),
    modifier_plus_right_page_back    = Device:hasScreenKB() and _("ScreenKB + RPgBack") or _("Shift + RPgBack"),
    modifier_plus_right_page_forward = Device:hasScreenKB() and _("ScreenKB + RPgFwd")  or _("Shift + RPgFwd"),
    -- function keys
    modifier_plus_back               = Device:hasScreenKB() and _("ScreenKB + Back")    or _("Shift + Back"),
    modifier_plus_home               = Device:hasScreenKB() and _("ScreenKB + Home")    or _("Shift + Home"),
    modifier_plus_press              = Device:hasScreenKB() and _("ScreenKB + Press")   or _("Shift + Press"),
    -- modifier_plus_menu (screenkb+menu) is already used globally for screenshots (on k4), don't add it here.
}
if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
    local hotkeyshortcuts_list_press = { press = _("Press") }
    util.tableMerge(hotkeyshortcuts_list, hotkeyshortcuts_list_press)
end
if Device:hasKeyboard() then
    local hotkeyshortcuts_list_haskeyboard = {
        modifier_plus_menu          = _("Shift + Menu"),
        -- NOTE: we will use 'alt' for kindles and 'ctrl' for other devices with keyboards
        --       but for simplicity we will use in code 'alt+keys' as the array's key for all.
        -- alt+cursor
        alt_plus_up                 = Device:hasSymKey() and _("Alt + Up")      or _("Ctrl + Up"),
        alt_plus_down               = Device:hasSymKey() and _("Alt + Down")    or _("Ctrl + Down"),
        alt_plus_left               = Device:hasSymKey() and _("Alt + Left")    or _("Ctrl + Left"),
        alt_plus_right              = Device:hasSymKey() and _("Alt + Right")   or _("Ctrl + Right"),
        -- alt+page_turn
        alt_plus_left_page_back     = Device:hasSymKey() and _("Alt + LPgBack") or _("Ctrl + LPgBack"),
        alt_plus_left_page_forward  = Device:hasSymKey() and _("Alt + LPgFwd")  or _("Ctrl + LPgFwd"),
        alt_plus_right_page_back    = Device:hasSymKey() and _("Alt + RPgBack") or _("Ctrl + RPgBack"),
        alt_plus_right_page_forward = Device:hasSymKey() and _("Alt + RPgFwd")  or _("Ctrl + RPgFwd"),
        -- alt+fn_keys
        alt_plus_back               = Device:hasSymKey() and _("Alt + Back")    or _("Ctrl + Back"),
        alt_plus_home               = Device:hasSymKey() and _("Alt + Home")    or _("Ctrl + Home"),
        alt_plus_press              = Device:hasSymKey() and _("Alt + Press")   or _("Ctrl + Press"),
        alt_plus_menu               = Device:hasSymKey() and _("Alt + Menu")    or _("Ctrl + Menu"),
        -- alt+alphabet
        alt_plus_a = Device:hasSymKey() and _("Alt + A") or _("Ctrl + A"),
        alt_plus_b = Device:hasSymKey() and _("Alt + B") or _("Ctrl + B"),
        alt_plus_c = Device:hasSymKey() and _("Alt + C") or _("Ctrl + C"),
        alt_plus_d = Device:hasSymKey() and _("Alt + D") or _("Ctrl + D"),
        alt_plus_e = Device:hasSymKey() and _("Alt + E") or _("Ctrl + E"),
        alt_plus_f = Device:hasSymKey() and _("Alt + F") or _("Ctrl + F"),
        alt_plus_g = Device:hasSymKey() and _("Alt + G") or _("Ctrl + G"),
        alt_plus_h = Device:hasSymKey() and _("Alt + H") or _("Ctrl + H"),
        alt_plus_i = Device:hasSymKey() and _("Alt + I") or _("Ctrl + I"),
        alt_plus_j = Device:hasSymKey() and _("Alt + J") or _("Ctrl + J"),
        alt_plus_k = Device:hasSymKey() and _("Alt + K") or _("Ctrl + K"),
        alt_plus_l = Device:hasSymKey() and _("Alt + L") or _("Ctrl + L"),
        alt_plus_m = Device:hasSymKey() and _("Alt + M") or _("Ctrl + M"),
        alt_plus_n = Device:hasSymKey() and _("Alt + N") or _("Ctrl + N"),
        alt_plus_o = Device:hasSymKey() and _("Alt + O") or _("Ctrl + O"),
        alt_plus_p = Device:hasSymKey() and _("Alt + P") or _("Ctrl + P"),
        alt_plus_q = Device:hasSymKey() and _("Alt + Q") or _("Ctrl + Q"),
        alt_plus_r = Device:hasSymKey() and _("Alt + R") or _("Ctrl + R"),
        alt_plus_s = Device:hasSymKey() and _("Alt + S") or _("Ctrl + S"),
        alt_plus_t = Device:hasSymKey() and _("Alt + T") or _("Ctrl + T"),
        alt_plus_u = Device:hasSymKey() and _("Alt + U") or _("Ctrl + U"),
        alt_plus_v = Device:hasSymKey() and _("Alt + V") or _("Ctrl + V"),
        alt_plus_w = Device:hasSymKey() and _("Alt + W") or _("Ctrl + W"),
        alt_plus_x = Device:hasSymKey() and _("Alt + X") or _("Ctrl + X"),
        alt_plus_y = Device:hasSymKey() and _("Alt + Y") or _("Ctrl + Y"),
        alt_plus_z = Device:hasSymKey() and _("Alt + Z") or _("Ctrl + Z"),
    }
    util.tableMerge(hotkeyshortcuts_list, hotkeyshortcuts_list_haskeyboard)
end

function HotKeyShortcuts:init()
    local defaults_path = FFIUtil.joinPath(self.path, "defaults.lua")
    if not lfs.attributes(hotkeyshortcuts_path, "mode") then
        FFIUtil.copyFile(defaults_path, hotkeyshortcuts_path)
    end
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.hotkey_mode = self.is_docless and "hotkeyshortcuts_fm" or "hotkeyshortcuts_reader"
    self.defaults = LuaSettings:open(defaults_path).data[self.hotkey_mode]
    if not self.settings_data then
        self.settings_data = LuaSettings:open(hotkeyshortcuts_path)
    end
    self.hotkeyshortcuts = self.settings_data.data[self.hotkey_mode]

    self.ui.menu:registerToMainMenu(self)
    Dispatcher:init()
    self:registerKeyEvents()
end


--[[
    Handles the action triggered by a hotkey press.
    @param hotkey (string) The identifier for the hotkey that was pressed.
    @return (boolean) Returns true if the hotkey action was successfully executed, otherwise returns nil.
]]
function HotKeyShortcuts:onHotkeyAction(hotkey)
    local action_list = self.hotkeyshortcuts[hotkey]
    if action_list == nil then
        return
    else
        local exec_props = { hotkeyshortcuts = hotkey }
        Dispatcher:execute(action_list, exec_props)
    end
    return true
end

--[[
["modifier_plus_right_page_forward"] = {
    ["settings"] = {
        ["order"] = {
            [1] = "swap_right_page_turn_buttons",
        },
    },
    ["swap_right_page_turn_buttons"] = true,
}, ]]

--[[
    Description:
    This function registers key events for the HotKeyShortcuts plugin. It initializes the key events table,
    overrides conflicting functions, and maps various keys to specific events based on the device's capabilities.
]]
function HotKeyShortcuts:registerKeyEvents()
    self.key_events = {}
    self:overrideConflictingFunctions()
    local key_name_mapping = {
        LPgBack = "left_page_back",    RPgBack = "right_page_back",
        LPgFwd  = "left_page_forward", RPgFwd  = "right_page_forward",
    }
    local cursor_keys = { "Up", "Down", "Left", "Right" }
    local page_turn_keys = { "LPgBack", "LPgFwd", "RPgBack", "RPgFwd" }
    local function_keys = { "Back", "Home", "Press", "Menu" }

    local function addKeyEvent(modifier, key, event, args)
        self.key_events[modifier .."Plus".. key] = { { modifier, key }, event = event, args = args }
    end

    local function addKeyEvents(modifier, keys, event, args_prefix)
        for _, key in ipairs(keys) do
            local mapped_key = key_name_mapping[key] or key:lower()
            addKeyEvent(modifier, key, event, args_prefix .. mapped_key)
        end
    end

    if Device:hasScreenKB() then
        addKeyEvents("ScreenKB", cursor_keys, "HotkeyAction", "modifier_plus_")
        if not self.is_docless then
            addKeyEvents("ScreenKB", page_turn_keys, "HotkeyAction", "modifier_plus_")
            addKeyEvent("ScreenKB", "Press", "HotkeyAction", "modifier_plus_press")
            if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
                self.key_events.Press = { { "Press" }, event = "HotkeyAction", args = "press" }
            end
        end
        addKeyEvent("ScreenKB", "Back", "HotkeyAction", "modifier_plus_back")
        addKeyEvent("ScreenKB", "Home", "HotkeyAction", "modifier_plus_home")
    else
        addKeyEvents("Shift", cursor_keys, "HotkeyAction", "modifier_plus_")
        if not self.is_docless then
            addKeyEvents("Shift", page_turn_keys, "HotkeyAction", "modifier_plus_")
            addKeyEvent("Shift", "Press", "HotkeyAction", "modifier_plus_press")
            if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
                self.key_events.Press = { { "Press" }, event = "HotkeyAction", args = "press" }
            end
        end
        addKeyEvent("Shift", "Back", "HotkeyAction", "modifier_plus_back")
        addKeyEvent("Shift", "Home", "HotkeyAction", "modifier_plus_home")
        addKeyEvent("Shift", "Menu", "HotkeyAction", "modifier_plus_menu")
    end

    if Device:hasKeyboard() then
        local second_modifier = Device:hasSymKey() and "Alt" or "Ctrl"
        addKeyEvents(second_modifier, cursor_keys, "HotkeyAction", "alt_plus_")
        addKeyEvents(second_modifier, page_turn_keys, "HotkeyAction", "alt_plus_")
        addKeyEvents(second_modifier, function_keys, "HotkeyAction", "alt_plus_")
        local top_row_keys = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }
        local remaining_keys = { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M" }
        if Device.k3_alt_plus_key_kernel_translated then
            -- Add the infamous top row keys, with kernel issues
            for _, key in ipairs(top_row_keys) do
                self.key_events["AltPlus" .. key] = {
                    { Device.k3_alt_plus_key_kernel_translated[key] },
                    event = "HotkeyAction",
                    args = "alt_plus_" .. key:lower()
                }
            end
        else
            addKeyEvents(second_modifier, top_row_keys, "HotkeyAction", "alt_plus_")
        end
        addKeyEvents(second_modifier, remaining_keys, "HotkeyAction", "alt_plus_")
    end -- if hasKeyboard()
end -- registerKeyEvents()

HotKeyShortcuts.onPhysicalKeyboardConnected = HotKeyShortcuts.registerKeyEvents

function HotKeyShortcuts:shortcutTitleFunc(hotkey)
    local title = hotkeyshortcuts_list[hotkey]
    return T(_("%1: (%2)"), title, Dispatcher:menuTextFunc(self.hotkeyshortcuts[hotkey]))
end

function HotKeyShortcuts:genMenu(hotkey)
    local sub_items = {}
    if hotkeyshortcuts_list[hotkey] ~= nil then
        table.insert(sub_items, {
            text = T(_("%1 (default)"), Dispatcher:menuTextFunc(self.defaults[hotkey])),
            keep_menu_open = true,
            separator = true,
            checked_func = function()
                return util.tableEquals(self.hotkeyshortcuts[hotkey], self.defaults[hotkey])
            end,
            callback = function()
                self.hotkeyshortcuts[hotkey] = util.tableDeepCopy(self.defaults[hotkey])
                self.updated = true
            end,
        })
    end
    table.insert(sub_items, {
        text = _("Pass through"),
        keep_menu_open = true,
        checked_func = function()
            return self.hotkeyshortcuts[hotkey] == nil
        end,
        callback = function()
            self.hotkeyshortcuts[hotkey] = nil
            self.updated = true
        end,
    })
    Dispatcher:addSubMenu(self, sub_items, self.hotkeyshortcuts, hotkey)
    sub_items.max_per_page = nil -- restore default, settings in page 2
    return sub_items
end

function HotKeyShortcuts:genSubItem(hotkey, separator, hold_callback)
    local reader_only = {
        -- these button combinations are used by different events in FM already, don't allow users to customise them.
        modifier_plus_down = true,
        modifier_plus_left_page_back = true,
        modifier_plus_left_page_forward = true,
        modifier_plus_right_page_back = true,
        modifier_plus_right_page_forward = true,
        modifier_plus_press = true,
    }
    if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
        local fm_do_not_press = { press = true }
        util.tableMerge(reader_only, fm_do_not_press)
    end
    local enabled_func
    if reader_only[hotkey] then
       enabled_func = function() return self.hotkey_mode == "hotkeyshortcuts_reader" end
    end
    return {
        text_func = function() return self:shortcutTitleFunc(hotkey) end,
        enabled_func = enabled_func,
        sub_item_table_func = function() return self:genMenu(hotkey) end,
        separator = separator,
        hold_callback = hold_callback,
        ignored_by_menu_search = true, -- This item is not strictly duplicated, but its subitems are. Ignoring it speeds up search.
    }
end

function HotKeyShortcuts:genSubItemTable(hotkeyshortcuts)
    local sub_item_table = {}
    for _, item in ipairs(hotkeyshortcuts) do
        table.insert(sub_item_table, self:genSubItem(item))
    end
    return sub_item_table
end

function HotKeyShortcuts:attachNewTableToExistingTable(orig_table, second_table)
    for _, v in ipairs(second_table) do
        table.insert(orig_table, v)
    end
end

--[[
    This function configures and adds various hotkey shortcuts to the main menu based on the device's capabilities
    and user settings. It supports different sets of keys for devices with and without keyboards.

    The function performs the following steps:
    1. Defines sets of cursor keys, page-turn buttons, and function keys.
    2. Adds the "press" key to function keys if the corresponding setting is enabled.
    3. If the device has a keyboard, additional sets of keys (cursor, page-turn, and function keys) are appended.
    4. Adds a menu item for enabling/disabling the use of the press key for shortcuts.
    5. Adds a menu item for configuring keyboard shortcuts, including cursor keys, page-turn buttons, and function keys.
    6. If the device has a keyboard, an additional menu item for alphabet keys is added.
--]]
function HotKeyShortcuts:addToMainMenu(menu_items)
    local cursor_keys = {
        "modifier_plus_up",
        "modifier_plus_down",
        "modifier_plus_left",
        "modifier_plus_right",
    }
    local pg_turn = {
        "modifier_plus_left_page_back",
        "modifier_plus_left_page_forward",
        "modifier_plus_right_page_back",
        "modifier_plus_right_page_forward",
    }
    local fn_keys = {
        "modifier_plus_back",
        "modifier_plus_home",
        "modifier_plus_press"
    }
    if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
        table.insert(fn_keys, 1, "press")
    end
    if Device:hasKeyboard() then
        local cursor_keys_haskeyboard = {
            "alt_plus_up",
            "alt_plus_down",
            "alt_plus_left",
            "alt_plus_right",
        }
        self:attachNewTableToExistingTable(cursor_keys, cursor_keys_haskeyboard)
        local pg_turn_haskeyboard = {
            "alt_plus_left_page_back",
            "alt_plus_left_page_forward",
            "alt_plus_right_page_back",
            "alt_plus_right_page_forward",
        }
        self:attachNewTableToExistingTable(pg_turn, pg_turn_haskeyboard)
        local fn_keys_haskeyboard = {
            "modifier_plus_menu",
            "alt_plus_back",
            "alt_plus_home",
            "alt_plus_press",
            "alt_plus_menu"
        }
        self:attachNewTableToExistingTable(fn_keys, fn_keys_haskeyboard)
    end
    menu_items.button_press_does_hotkeyshortcuts = {
        sorting_hint = "physical_buttons_setup",
        text = _("Use the press key for shortcuts"),
        checked_func = function()
            return G_reader_settings:isTrue("press_key_does_hotkeyshortcuts")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("press_key_does_hotkeyshortcuts")
            UIManager:askForRestart()
        end,
    }
    menu_items.hotkeyshortcuts = {
        sorting_hint = "physical_buttons_setup",
        text = _("Keyboard shortcuts"),
        sub_item_table = {
            {
                text = _("Cursor keys"),
                sub_item_table = self:genSubItemTable(cursor_keys),
            },
            {
                text = _("Page-turn buttons"),
                enabled_func = function() return self.hotkey_mode == "hotkeyshortcuts_reader" end,
                sub_item_table = self:genSubItemTable(pg_turn),
            },
            {
                text = _("Function keys"),
                sub_item_table = self:genSubItemTable(fn_keys),
            },
        },
    }

    if Device:hasKeyboard() then
        table.insert(menu_items.hotkeyshortcuts.sub_item_table, {
            text = _("Alphabet keys"),
            sub_item_table = self:genSubItemTable({
                "alt_plus_a", "alt_plus_b", "alt_plus_c", "alt_plus_d", "alt_plus_e", "alt_plus_f", "alt_plus_g", "alt_plus_h", "alt_plus_i",
                "alt_plus_j", "alt_plus_k", "alt_plus_l", "alt_plus_m", "alt_plus_n", "alt_plus_o", "alt_plus_p", "alt_plus_q", "alt_plus_r",
                "alt_plus_s", "alt_plus_t", "alt_plus_u", "alt_plus_v", "alt_plus_w", "alt_plus_x", "alt_plus_y", "alt_plus_z",
            }),
        })
    end
end

--[[
    Description:
    This function overrides existing `registerKeyEvents()` functions in various modules to resolve conflicts and customize key event handling.
    It modifies the key event registration for several reader and file manager modules based on device capabilities and user settings.

    Modules and their modifications:
    - ReaderBookmark: Overrides `registerKeyEvents()` with an empty function.
    - ReaderConfig: Customizes `ShowConfigMenu` key event based on user settings.
    - ReaderDictionary: Overrides `registerKeyEvents()` with an empty function.
    - ReaderLink: Customizes `GotoSelectedPageLink` key event for devices with screen keyboard or symbol key.
    - ReaderSearch: Customizes `ShowFulltextSearchInputBlank` key event for devices with a keyboard.
    - ReaderToc: Overrides `registerKeyEvents()` with an empty function.
    - ReaderThumbnail: Overrides `registerKeyEvents()` with an empty function.
    - ReaderWikipedia: Overrides `registerKeyEvents()` with an empty function.
    - ReaderUI: Customizes `Home` and `KeyContentSelection` key events based on device capabilities.
    - FileManager: Customizes `Home` and `Back` key events, and conditionally removes `Close` key event.
    - FileSearcher: CCustomizes `ShowFileSearchBlank` key event for devices with keyboards.
    - FileManagerMenu: Customizes `ShowMenu` key event for devices with keys.
]]
function HotKeyShortcuts:overrideConflictingFunctions()
    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    ReaderBookmark.registerKeyEvents = function(_self)
    end

    local ReaderConfig = require("apps/reader/modules/readerconfig")
    ReaderConfig.registerKeyEvents = function(_self)
        if Device:hasKeys() then
            if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
                self.key_events.ShowConfigMenu = { { "AA" } }
            elseif G_reader_settings:nilOrFalse("press_key_does_hotkeyshortcuts") then
                self.key_events.ShowConfigMenu = { { { "Press", "AA" } } }
            end
        end
    end

    local ReaderDictionary= require("apps/reader/modules/readerdictionary")
    ReaderDictionary.registerKeyEvents = function(_self)
    end

    local ReaderLink = require("apps/reader/modules/readerlink")
    ReaderLink.registerKeyEvents = function(_self)
        if Device:hasScreenKB() or Device:hasSymKey() then
            self.key_events.GotoSelectedPageLink = { { "Press" }, event = "GotoSelectedPageLink" }
        elseif Device:hasKeys() then
            self.key_events = {
                SelectNextPageLink = {
                    { "Tab" },
                    event = "SelectNextPageLink",
                },
                SelectPrevPageLink = {
                    { "Shift", "Tab" },
                    event = "SelectPrevPageLink",
                },
                GotoSelectedPageLink = {
                    { "Press" },
                    event = "GotoSelectedPageLink",
                },
            }
        end
    end

    local ReaderSearch = require("apps/reader/modules/readersearch")
    ReaderSearch.registerKeyEvents = function(_self)
        if Device:hasKeyboard() then
            self.key_events.ShowFulltextSearchInputBlank = {
                { "Alt", "Shift", "S" }, { "Ctrl", "Shift", "S" },
                event = "ShowFulltextSearchInput",
                args = ""
            }
        end
    end

    local ReaderToc = require("apps/reader/modules/readertoc")
    ReaderToc.registerKeyEvents = function(_self)
    end

    local ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
    ReaderThumbnail.registerKeyEvents = function(_self)
    end

    local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
    ReaderWikipedia.registerKeyEvents = function(_self)
    end

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI.registerKeyEvents = function(_self)
        if Device:hasKeys() then
            self.key_events.Home = { { "Home" } }
            if Device:hasDPad() and Device:useDPadAsActionKeys() then
                self.key_events.KeyContentSelection = { { { "Up", "Down" } }, event = "StartHighlightIndicator" }
            elseif Device:hasKeyboard() then
                self.key_events.Reload = { { "F5" } }
            end
        end
    end

    local FileManager = require("apps/filemanager/filemanager")
    local FileChooser = require("ui/widget/filechooser")
    FileManager.registerKeyEvents = function(_self)
        if Device:hasKeys() then
            self.key_events.Home = { { "Home" } }
            -- Ensure file_chooser is initialized before accessing it
            if not self.file_chooser then
                self.file_chooser = FileChooser:new()
            end
            -- Override the menu.lua way of handling the back key
            self.file_chooser.key_events.Back = { { Device.input.group.Back } }
            if not Device:hasFewKeys() then
                -- Also remove the handler assigned to the "Back" key by menu.lua
                self.file_chooser.key_events.Close = nil
            end
        end
    end

    local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
    FileSearcher.registerKeyEvents = function(_self)
        if Device:hasKeyboard() then
            self.key_events.ShowFileSearchBlank = {
                { "Alt", "Shift", "F" }, { "Ctrl", "Shift", "F" },
                event = "ShowFileSearch",
                args = ""
            }
        end
    end

    local FileManagerMenu = require("apps/filemanager/filemanagermenu")
    FileManagerMenu.registerKeyEvents = function(_self)
        if Device:hasKeys() then
            self.key_events.ShowMenu = { { "Menu" } }
        end
    end
end -- overrideConflictingFunctions()

--[[
    This function checks if the `settings_data` exists and if it has been marked as updated.
    If both conditions are met, it flushes the `settings_data` and resets the `updated` flag to false.
--]]
function HotKeyShortcuts:onFlushSettings()
    if self.settings_data and self.updated then
        self.settings_data:flush()
        self.updated = false
    end
end

function HotKeyShortcuts:updateProfiles(action_old_name, action_new_name)
    for _, section in ipairs({ "hotkeyshortcuts_fm", "hotkeyshortcuts_reader" }) do
       local hotkeyshortcuts = self.settings_data.data[section]
        for shortcut_name, shortcut in pairs(hotkeyshortcuts) do
            if shortcut[action_old_name] then
                if shortcut.settings and shortcut.settings.order then
                    for i, action in ipairs(shortcut.settings.order) do
                        if action == action_old_name then
                            if action_new_name then
                                shortcut.settings.order[i] = action_new_name
                            else
                                table.remove(shortcut.settings.order, i)
                                if #shortcut.settings.order == 0 then
                                    shortcut.settings.order = nil
                                    if next(shortcut.settings) == nil then
                                        shortcut.settings = nil
                                    end
                                end
                            end
                            break
                        end
                    end
                end
                shortcut[action_old_name] = nil
                if action_new_name then
                    shortcut[action_new_name] = true
                else
                    if next(shortcut) == nil then
                        self.settings_data.data[section][shortcut_name] = nil
                    end
                end
                self.updated = true
            end
        end
    end
end

return HotKeyShortcuts
