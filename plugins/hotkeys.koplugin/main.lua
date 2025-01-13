local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local T = FFIUtil.template
local _ = require("gettext")

if not (Device:hasScreenKB() or Device:hasKeyboard()) then
    return { disabled = true, }
end

local HotKeys = InputContainer:extend{
    name = "hotkeys",
    settings_data = nil,
    hotkeys = nil,
    defaults = nil,
    updated = false,
}
local hotkeys_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), "hotkeys.lua")

-- mofifier *here* refers to either screenkb or shift
local hotkeys_list = {
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
if LuaSettings:open(hotkeys_path).data["press_key_does_hotkeys"] then
    local hotkeys_list_press = { press = _("Press") }
    util.tableMerge(hotkeys_list, hotkeys_list_press)
end
if Device:hasKeyboard() then
    local hotkeys_list_haskeyboard = {
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
    util.tableMerge(hotkeys_list, hotkeys_list_haskeyboard)
end

function HotKeys:init()
    local defaults_path = FFIUtil.joinPath(self.path, "defaults.lua")
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.hotkey_mode = self.is_docless and "hotkeys_fm" or "hotkeys_reader"
    self.defaults = LuaSettings:open(defaults_path).data[self.hotkey_mode]
    if not self.settings_data then
        self.settings_data = LuaSettings:open(hotkeys_path)
        if not next(self.settings_data.data) then
            logger.warn("No hotkeys file or invalid hotkeys file found, copying defaults")
            self.settings_data:purge()
            FFIUtil.copyFile(defaults_path, hotkeys_path)
            self.settings_data = LuaSettings:open(hotkeys_path)
        end
    end
    self.hotkeys = self.settings_data.data[self.hotkey_mode]
    self.type_to_search = self.settings_data.data["type_to_search"] or false

    self.ui.menu:registerToMainMenu(self)
    Dispatcher:init()
    self:registerKeyEvents()
end

--[[
    Handles the action triggered by a hotkey press.
    @param hotkey (string) The identifier for the hotkey that was pressed.
    @return (boolean) Returns true if the hotkey action was successfully executed, otherwise returns nil.
]]
function HotKeys:onHotkeyAction(hotkey)
    local hotkey_action_list = self.hotkeys[hotkey]
    local context = self.is_docless and "FileManager" or "Reader"
    if hotkey_action_list == nil then
        logger.dbg("No actions associated with hotkey: ", hotkey, " in ", context)
        return
    else
        local execution_properties = { hotkeys = hotkey }
        logger.dbg("Executing actions for hotkey: ", hotkey, " in ", context, " with events: ", hotkey_action_list)
        -- Execute (via Dispatcher) the list of actions associated with the hotkey
        Dispatcher:execute(hotkey_action_list, execution_properties)
        return true
    end
end
--[[ The following snippet is an example of the hotkeys.lua file that is generated in the settings directory:
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
    This function registers key events for the HotKeys plugin. It initializes the key events table,
    overrides conflicting functions, and maps various keys to specific events based on the device's capabilities.
]]
function HotKeys:registerKeyEvents()
    self.key_events = {}
    self:overrideConflictingKeyEvents()
    local cursor_keys = { "Up", "Down", "Left", "Right" }
    local page_turn_keys = { "LPgBack", "LPgFwd", "RPgBack", "RPgFwd" }
    local function_keys = { "Back", "Home", "Press", "Menu" }
    local key_name_mapping = {
        LPgBack = "left_page_back",    RPgBack = "right_page_back",
        LPgFwd  = "left_page_forward", RPgFwd  = "right_page_forward",
    }
    local function addKeyEvent(modifier, key, event, args)
        self.key_events[modifier .."Plus".. key] = { { modifier, key }, event = event, args = args }
    end

    local function addKeyEvents(modifier, keys, event, args_prefix)
        for _, key in ipairs(keys) do
            local mapped_key = key_name_mapping[key] or key:lower()
            addKeyEvent(modifier, key, event, args_prefix .. mapped_key)
        end
    end

    local modifier = Device:hasScreenKB() and "ScreenKB" or "Shift"
    addKeyEvents(modifier, cursor_keys, "HotkeyAction", "modifier_plus_")
    if not self.is_docless then
        addKeyEvents(modifier, page_turn_keys, "HotkeyAction", "modifier_plus_")
        addKeyEvent(modifier, "Press", "HotkeyAction", "modifier_plus_press")
        if self.settings_data.data["press_key_does_hotkeys"] then
            self.key_events.Press = { { "Press" }, event = "HotkeyAction", args = "press" }
        end
    end
    addKeyEvent(modifier, "Back", "HotkeyAction", "modifier_plus_back")
    addKeyEvent(modifier, "Home", "HotkeyAction", "modifier_plus_home")
    -- remember, screenkb+menu is already used for screenshots (on k4), don't add it here.

    if Device:hasKeyboard() then
        addKeyEvent("Shift", "Menu", "HotkeyAction", "modifier_plus_menu")
        local second_modifier = Device:hasSymKey() and "Alt" or "Ctrl"
        addKeyEvents(second_modifier, cursor_keys, "HotkeyAction", "alt_plus_")
        addKeyEvents(second_modifier, page_turn_keys, "HotkeyAction", "alt_plus_")
        addKeyEvents(second_modifier, function_keys, "HotkeyAction", "alt_plus_")
        local top_row_keys = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }
        local remaining_keys = { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M" }
        if Device.k3_alt_plus_key_kernel_translated then
            -- Add the infamous top row keys, with kernel issues (see #12358 for details)
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

    local key_event_count = util.tableSize(self.key_events)
    logger.dbg("Total number of hotkey events registered successfully: ", key_event_count)
end -- registerKeyEvents()

HotKeys.onPhysicalKeyboardConnected = HotKeys.registerKeyEvents

function HotKeys:shortcutTitleFunc(hotkey)
    local title = hotkeys_list[hotkey]
    local action_list = self.hotkeys[hotkey]
    local action_text = action_list and Dispatcher:menuTextFunc(action_list) or _("No action")
    return T(_("%1: (%2)"), title, action_text)
end

function HotKeys:genMenu(hotkey)
    local sub_items = {}
    if hotkeys_list[hotkey] ~= nil then
        local default_action = self.defaults[hotkey]
        local default_text = default_action and Dispatcher:menuTextFunc(default_action) or _("No action")
        table.insert(sub_items, {
            text = T(_("%1 (default)"), default_text),
            keep_menu_open = true,
            checked_func = function()
                return util.tableEquals(self.hotkeys[hotkey], self.defaults[hotkey])
            end,
            callback = function()
                self.hotkeys[hotkey] = util.tableDeepCopy(self.defaults[hotkey])
                self.updated = true
            end,
        })
    end
    table.insert(sub_items, {
        text = _("No action"),
        keep_menu_open = true,
        separator = true,
        checked_func = function()
            return self.hotkeys[hotkey] == nil
        end,
        callback = function()
            self.hotkeys[hotkey] = nil
            self.updated = true
        end,
    })
    Dispatcher:addSubMenu(self, sub_items, self.hotkeys, hotkey)
    -- Since we are already handling potential conflicts via overrideConflictingKeyEvents(), both "No action" and "Nothing",
    -- introduced through Dispatcher:addSubMenu(), are effectively the same (from a user point of view); thus, we can do away
    -- with "Nothing".
    -- We prioritize "No action" as it will allow the predefined underlaying actions to be executed for hotkeys in the 'reader_only'
    -- array in the genSubItem() function.
    table.remove(sub_items, 3) -- removes the 'Nothing' option as it is redundant.
    sub_items.max_per_page = 9 -- push settings ('Arrange actions', 'Show as quick menu', 'keep quick menu open') to page 2
    return sub_items
end

function HotKeys:genSubItem(hotkey, separator, hold_callback)
    local reader_only = {
        -- these button combinations are used by different events in FM already, don't allow users to customise them.
        modifier_plus_down = true,
        modifier_plus_left_page_back = true,
        modifier_plus_left_page_forward = true,
        modifier_plus_right_page_back = true,
        modifier_plus_right_page_forward = true,
        modifier_plus_press = true,
    }
    if self.settings_data.data["press_key_does_hotkeys"] then
        local do_not_allow_press_key_do_shortcuts_in_fm = { press = true }
        util.tableMerge(reader_only, do_not_allow_press_key_do_shortcuts_in_fm)
    end
    local enabled_func
    if reader_only[hotkey] then
       enabled_func = function() return self.hotkey_mode == "hotkeys_reader" end
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

function HotKeys:genSubItemTable(hotkeys)
    local sub_item_table = {}
    for _, item in ipairs(hotkeys) do
        table.insert(sub_item_table, self:genSubItem(item))
    end
    return sub_item_table
end

local function attachNewTableToExistingTable(original_table, second_table)
    for _, v in ipairs(second_table) do
        table.insert(original_table, v)
    end
end

--[[
    This function configures and adds various hotkey shortcuts to the main menu based on the device's capabilities
    and user settings. It supports different sets of keys for devices with and without keyboards.
--]]
function HotKeys:addToMainMenu(menu_items)
    -- 1. Defines sets of cursor keys, page-turn buttons, and function keys.
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
        -- modifier_plus_menu (screenkb+menu) is already used globally for screenshots (on k4), don't add it here.
    }
    -- 2. Adds the "press" key to function keys if the corresponding setting is enabled.
    if self.settings_data.data["press_key_does_hotkeys"] then
        table.insert(fn_keys, 1, "press")
    end
    -- 3. If the device has a keyboard, additional sets of keys (cursor, page-turn, and function keys) are appended.
    if Device:hasKeyboard() then
        local cursor_keys_haskeyboard = {
            "alt_plus_up",
            "alt_plus_down",
            "alt_plus_left",
            "alt_plus_right",
        }
        attachNewTableToExistingTable(cursor_keys, cursor_keys_haskeyboard)
        local pg_turn_haskeyboard = {
            "alt_plus_left_page_back",
            "alt_plus_left_page_forward",
            "alt_plus_right_page_back",
            "alt_plus_right_page_forward",
        }
        attachNewTableToExistingTable(pg_turn, pg_turn_haskeyboard)
        local fn_keys_haskeyboard = {
            "modifier_plus_menu",
            "alt_plus_back",
            "alt_plus_home",
            "alt_plus_press",
            "alt_plus_menu"
        }
        attachNewTableToExistingTable(fn_keys, fn_keys_haskeyboard)
    end
    -- 4a. Adds a menu item for enabling/disabling the type-to-search feature
    if Device:hasKeyboard() and not self.is_docless then
        menu_items.a_type_to_search = {
            sorting_hint = "physical_buttons_setup",
            text = _("Type to launch full text search"),
            checked_func = function()
                return self.type_to_search
            end,
            callback = function()
                self.type_to_search = not self.type_to_search
                self.settings_data.data["type_to_search"] = self.type_to_search
                self.updated = true
                self:onFlushSettings()
                UIManager:askForRestart()
            end,
        }
    end
    -- 4b. Adds a menu item for enabling/disabling the use of the press key for shortcuts.
    if Device:hasScreenKB() or Device:hasSymKey() then
        menu_items.button_press_does_hotkeys = {
            sorting_hint = "physical_buttons_setup",
            text = _("Use the press key for shortcuts"),
            checked_func = function()
                return self.settings_data.data["press_key_does_hotkeys"]
            end,
            callback = function()
                self.settings_data.data["press_key_does_hotkeys"] = not self.settings_data.data["press_key_does_hotkeys"]
                self.updated = true
                self:onFlushSettings()
                UIManager:askForRestart()
            end,
        }
    end
    --5. Adds a menu item for configuring keyboard shortcuts, including cursor keys, page-turn buttons, and function keys.
    menu_items.hotkeys = {
        sorting_hint = "physical_buttons_setup",
        text = _("Keyboard shortcuts"),
        sub_item_table = {
            {
                text = _("Cursor keys"),
                sub_item_table = self:genSubItemTable(cursor_keys),
            },
            {
                text = _("Page-turn buttons"),
                enabled_func = function()
                    return Device:hasKeyboard() and self.hotkey_mode == "hotkeys_fm" or self.hotkey_mode == "hotkeys_reader"
                end,
                sub_item_table = self:genSubItemTable(pg_turn),
            },
            {
                text = _("Function keys"),
                sub_item_table = self:genSubItemTable(fn_keys),
            },
        },
    }
    -- 6. If the device has a keyboard, adds a menu item for configuring hotkeys using alphabet keys.
    if Device:hasKeyboard() then
        table.insert(menu_items.hotkeys.sub_item_table, {
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
    This function resets existing key_event tables in various modules to resolve conflicts and customize key event handling
    Details:
    - Resets and overrides key events for the following modules:
        - ReaderBookmark
        - ReaderConfig
        - ReaderLink
        - ReaderSearch; also adds a type to search feature.
        - ReaderToc
        - ReaderThumbnail
        - ReaderUI
        - ReaderDictionary
        - ReaderWikipedia
        - FileSearcher
        - FileManagerMenu (if in docless mode)
    - Logs debug messages indicating which key events have been overridden.
]]
function HotKeys:overrideConflictingKeyEvents()
    if not self.is_docless then
        self.ui.bookmark.key_events = {} -- reset it.
        logger.dbg("Hotkey ReaderBookmark:registerKeyEvents() overridden.")

        if Device:hasScreenKB() or Device:hasSymKey() then
            local readerconfig = self.ui.config
            readerconfig.key_events = {} -- reset it, then add our own
            if self.settings_data.data["press_key_does_hotkeys"] then
                readerconfig.key_events.ShowConfigMenu = { { "AA" }, event = "ShowConfigMenu" }
            else
                readerconfig.key_events.ShowConfigMenu = { { { "Press", "AA" } }, event = "ShowConfigMenu" }
            end
            logger.dbg("Hotkey ReaderConfig:registerKeyEvents() overridden.")
        end

        local readerlink = self.ui.link
        readerlink.key_events = {} -- reset it.
        if Device:hasScreenKB() or Device:hasSymKey() then
            readerlink.key_events.GotoSelectedPageLink = { { "Press" }, event = "GotoSelectedPageLink" }
        elseif Device:hasKeyboard() then
            readerlink.key_events = {
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
        logger.dbg("Hotkey ReaderLink:registerKeyEvents() overridden.")

        if Device:hasKeyboard() then
            local readersearch = self.ui.search
            readersearch.key_events = {} -- reset it.
            readersearch.key_events.ShowFulltextSearchInputBlank = {
                { "Alt", "Shift", "S" }, { "Ctrl", "Shift", "S" },
                event = "ShowFulltextSearchInput",
                args = ""
            }
            if self.type_to_search then
                self.ui.highlight.key_events.StartHighlightIndicator = nil -- remove 'H' shortcut used for highlight indicator
                readersearch.key_events.Alphabet = {
                    { Device.input.group.Alphabet }, { "Shift", Device.input.group.Alphabet },
                    event = "ShowFulltextSearchInput",
                    args = ""
                }
            end
            logger.dbg("Hotkey ReaderSearch:registerKeyEvents() overridden.")
        end

        self.ui.toc.key_events = {} -- reset it.
        logger.dbg("Hotkey ReaderToc:registerKeyEvents() overridden.")

        self.ui.thumbnail.key_events = {} -- reset it.
        logger.dbg("Hotkey ReaderThumbnail:registerKeyEvents() overridden.")

        local readerui = self.ui
        readerui.key_events = {} -- reset it, then add our own
        readerui.key_events.Home = { { "Home" } }
        readerui.key_events.Back = { { Device.input.group.Back } }
        if Device:hasDPad() and Device:useDPadAsActionKeys() then
            readerui.key_events.KeyContentSelection = { { { "Up", "Down" } }, event = "StartHighlightIndicator" }
        elseif Device:hasKeyboard() then
            readerui.key_events.Reload = { { "F5" } }
        end
        logger.dbg("Hotkey ReaderUI:registerKeyEvents() overridden.")
    end

    if Device:hasKeyboard() then
        self.ui.dictionary.key_events = {} -- reset it.
        logger.dbg("Hotkey ReaderDictionary:registerKeyEvents() overridden.")

        self.ui.wikipedia.key_events = {} -- reset it.
        logger.dbg("Hotkey ReaderWikipedia:registerKeyEvents() overridden.")

        local filesearcher = self.ui.filesearcher
        filesearcher.key_events = {} -- reset it.
        filesearcher.key_events.ShowFileSearchBlank = {
            { "Alt", "Shift", "F" }, { "Ctrl", "Shift", "F" },
            event = "ShowFileSearch",
            args = ""
        }
        logger.dbg("Hotkey FileSearcher:registerKeyEvents() overridden.")
    end

    if self.is_docless then
        local filemanagermenu = self.ui.menu
        filemanagermenu.key_events = {} -- reset it.
        filemanagermenu.key_events.ShowMenu = { { "Menu" } }
        logger.dbg("Hotkey FileManagerMenu:registerKeyEvents() overridden.")
    end
end -- overrideConflictingKeyEvents()

--[[
    This function checks if the `settings_data` exists and if it has been marked as updated.
    If both conditions are met, it flushes the `settings_data` and resets the `updated` flag to false.
--]]
function HotKeys:onFlushSettings()
    if self.settings_data and self.updated then
        self.settings_data:flush()
        self.updated = false
    end
end

function HotKeys:updateProfiles(action_old_name, action_new_name)
    for _, section in ipairs({ "hotkeys_fm", "hotkeys_reader" }) do
        local hotkeys = self.settings_data.data[section]
        for shortcut_name, shortcut in pairs(hotkeys) do
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

return HotKeys
