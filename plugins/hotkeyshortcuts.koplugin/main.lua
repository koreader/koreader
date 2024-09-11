local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
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
    modifier_plus_up                 = Device:hasScreenKB() and _("ScreenKB + Up")      or _("Shift + Up"),
    modifier_plus_down               = Device:hasScreenKB() and _("ScreenKB + Down")    or _("Shift + Down"),
    modifier_plus_left               = Device:hasScreenKB() and _("ScreenKB + Left")    or _("Shift + Left"),
    modifier_plus_right              = Device:hasScreenKB() and _("ScreenKB + Right")   or _("Shift + Right"),
    modifier_plus_left_page_back     = Device:hasScreenKB() and _("ScreenKB + LPgBack") or _("Shift + LPgBack"),
    modifier_plus_left_page_forward  = Device:hasScreenKB() and _("ScreenKB + LPgFwd")  or _("Shift + LPgFwd"),
    modifier_plus_right_page_back    = Device:hasScreenKB() and _("ScreenKB + RPgBack") or _("Shift + RPgBack"),
    modifier_plus_right_page_forward = Device:hasScreenKB() and _("ScreenKB + RPgFwd")  or _("Shift + RPgFwd"),
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
        -- alt+cursor
        alt_plus_up                 = Device:hasSymKey() and _("Alt + Up")      or _("Alt or Ctrl + Up"),
        alt_plus_down               = Device:hasSymKey() and _("Alt + Down")    or _("Alt or Ctrl + Down"),
        alt_plus_left               = Device:hasSymKey() and _("Alt + Left")    or _("Alt or Ctrl + Left"),
        alt_plus_right              = Device:hasSymKey() and _("Alt + Right")   or _("Alt or Ctrl + Right"),
        -- alt+page_turn
        alt_plus_left_page_back     = Device:hasSymKey() and _("Alt + LPgBack") or _("Alt or Ctrl + LPgBack"),
        alt_plus_left_page_forward  = Device:hasSymKey() and _("Alt + LPgFwd")  or _("Alt or Ctrl + LPgFwd"),
        alt_plus_right_page_back    = Device:hasSymKey() and _("Alt + RPgBack") or _("Alt or Ctrl + RPgBack"),
        alt_plus_right_page_forward = Device:hasSymKey() and _("Alt + RPgFwd")  or _("Alt or Ctrl + RPgFwd"),
        -- alt+fn_keys
        alt_plus_back               = Device:hasSymKey() and _("Alt + Back")    or _("Alt or Ctrl + Back"),
        alt_plus_home               = Device:hasSymKey() and _("Alt + Home")    or _("Alt or Ctrl + Home"),
        alt_plus_press              = Device:hasSymKey() and _("Alt + Press")   or _("Alt or Ctrl + Press"),
        alt_plus_menu               = Device:hasSymKey() and _("Alt + Menu")    or _("Alt or Ctrl + Menu"),
        -- alt+alphabet
        alt_plus_a = Device:hasSymKey() and _("Alt + A") or _("Alt or Ctrl + A"),
        alt_plus_b = Device:hasSymKey() and _("Alt + B") or _("Alt or Ctrl + B"),
        alt_plus_c = Device:hasSymKey() and _("Alt + C") or _("Alt or Ctrl + C"),
        alt_plus_d = Device:hasSymKey() and _("Alt + D") or _("Alt or Ctrl + D"),
        alt_plus_e = Device:hasSymKey() and _("Alt + E") or _("Alt or Ctrl + E"),
        alt_plus_f = Device:hasSymKey() and _("Alt + F") or _("Alt or Ctrl + F"),
        alt_plus_g = Device:hasSymKey() and _("Alt + G") or _("Alt or Ctrl + G"),
        alt_plus_h = Device:hasSymKey() and _("Alt + H") or _("Alt or Ctrl + H"),
        alt_plus_i = Device:hasSymKey() and _("Alt + I") or _("Alt or Ctrl + I"),
        alt_plus_j = Device:hasSymKey() and _("Alt + J") or _("Alt or Ctrl + J"),
        alt_plus_k = Device:hasSymKey() and _("Alt + K") or _("Alt or Ctrl + K"),
        alt_plus_l = Device:hasSymKey() and _("Alt + L") or _("Alt or Ctrl + L"),
        alt_plus_m = Device:hasSymKey() and _("Alt + M") or _("Alt or Ctrl + M"),
        alt_plus_n = Device:hasSymKey() and _("Alt + N") or _("Alt or Ctrl + N"),
        alt_plus_o = Device:hasSymKey() and _("Alt + O") or _("Alt or Ctrl + O"),
        alt_plus_p = Device:hasSymKey() and _("Alt + P") or _("Alt or Ctrl + P"),
        alt_plus_q = Device:hasSymKey() and _("Alt + Q") or _("Alt or Ctrl + Q"),
        alt_plus_r = Device:hasSymKey() and _("Alt + R") or _("Alt or Ctrl + R"),
        alt_plus_s = Device:hasSymKey() and _("Alt + S") or _("Alt or Ctrl + S"),
        alt_plus_t = Device:hasSymKey() and _("Alt + T") or _("Alt or Ctrl + T"),
        alt_plus_u = Device:hasSymKey() and _("Alt + U") or _("Alt or Ctrl + U"),
        alt_plus_v = Device:hasSymKey() and _("Alt + V") or _("Alt or Ctrl + V"),
        alt_plus_w = Device:hasSymKey() and _("Alt + W") or _("Alt or Ctrl + W"),
        alt_plus_x = Device:hasSymKey() and _("Alt + X") or _("Alt or Ctrl + X"),
        alt_plus_y = Device:hasSymKey() and _("Alt + Y") or _("Alt or Ctrl + Y"),
        alt_plus_z = Device:hasSymKey() and _("Alt + Z") or _("Alt or Ctrl + Z"),
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
    self:registerKeyEvents()
    Dispatcher:init()
end


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

function HotKeyShortcuts:registerKeyEvents()
    if Device:hasScreenKB() then
        self.key_events.ModPlusUp   = { { "ScreenKB",    "Up" }, event = "HotkeyAction", args = "modifier_plus_up" }
        self.key_events.ModPlusDown = { { "ScreenKB",  "Down" }, event = "HotkeyAction", args = "modifier_plus_down" }
        self.key_events.ModPlusLeft = { { "ScreenKB",  "Left" }, event = "HotkeyAction", args = "modifier_plus_left" }
        self.key_events.ModPlusRght = { { "ScreenKB", "Right" }, event = "HotkeyAction", args = "modifier_plus_right" }
        if not self.is_docless then
            self.key_events.ModPlusLPgB = { { "ScreenKB", "LPgBack" }, event = "HotkeyAction", args = "modifier_plus_left_page_back" }
            self.key_events.ModPlusLPgF = { { "ScreenKB",  "LPgFwd" }, event = "HotkeyAction", args = "modifier_plus_left_page_forward" }
            self.key_events.ModPlusRPgB = { { "ScreenKB", "RPgBack" }, event = "HotkeyAction", args = "modifier_plus_right_page_back" }
            self.key_events.ModPlusRPgF = { { "ScreenKB",  "RPgFwd" }, event = "HotkeyAction", args = "modifier_plus_right_page_forward" }
            self.key_events.ModPlusPrss = { { "ScreenKB",   "Press" }, event = "HotkeyAction", args = "modifier_plus_press" }
            if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
                self.key_events.Press = { { "Press" }, event = "HotkeyAction", args = "press" }
            end
        end
        self.key_events.ModPlusBack = { { "ScreenKB", "Back" }, event = "HotkeyAction", args = "modifier_plus_back" }
        self.key_events.ModPlusHome = { { "ScreenKB", "Home" }, event = "HotkeyAction", args = "modifier_plus_home" }
        -- no event for screenkb+menu
    else
        self.key_events.ModPlusUp   = { { "Shift",    "Up" }, event = "HotkeyAction", args = "modifier_plus_up" }
        self.key_events.ModPlusDown = { { "Shift",  "Down" }, event = "HotkeyAction", args = "modifier_plus_down" }
        self.key_events.ModPlusLeft = { { "Shift",  "Left" }, event = "HotkeyAction", args = "modifier_plus_left" }
        self.key_events.ModPlusRght = { { "Shift", "Right" }, event = "HotkeyAction", args = "modifier_plus_right" }
        if not self.is_docless then
            self.key_events.ModPlusLPgB = { { "Shift", "LPgBack" }, event = "HotkeyAction", args = "modifier_plus_left_page_back" }
            self.key_events.ModPlusLPgF = { { "Shift",  "LPgFwd" }, event = "HotkeyAction", args = "modifier_plus_left_page_forward" }
            self.key_events.ModPlusRPgB = { { "Shift", "RPgBack" }, event = "HotkeyAction", args = "modifier_plus_right_page_back" }
            self.key_events.ModPlusRPgF = { { "Shift",  "RPgFwd" }, event = "HotkeyAction", args = "modifier_plus_right_page_forward" }
            self.key_events.ModPlusPrss = { { "Shift",   "Press" }, event = "HotkeyAction", args = "modifier_plus_press" }
            if G_reader_settings:isTrue("press_key_does_hotkeyshortcuts") then
                self.key_events.Press = { { "Press" }, event = "HotkeyAction", args = "press" }
            end
        end
        self.key_events.ModPlusBack = { { "Shift", "Back" }, event = "HotkeyAction", args = "modifier_plus_back" }
        self.key_events.ModPlusHome = { { "Shift", "Home" }, event = "HotkeyAction", args = "modifier_plus_home" }
        self.key_events.ModPlusMenu = { { "Shift", "Menu" }, event = "HotkeyAction", args = "modifier_plus_menu" }
    end

    if Device:hasKeyboard() then
        self.key_events.AltPlusUp   = { { "Alt",      "Up" }, { "Ctrl",      "Up" }, event = "HotkeyAction", args = "alt_plus_up" }
        self.key_events.AltPlusDown = { { "Alt",    "Down" }, { "Ctrl",    "Down" }, event = "HotkeyAction", args = "alt_plus_down" }
        self.key_events.AltPlusLeft = { { "Alt",    "Left" }, { "Ctrl",    "Left" }, event = "HotkeyAction", args = "alt_plus_left" }
        self.key_events.AltPlusRght = { { "Alt",   "Right" }, { "Ctrl",   "Right" }, event = "HotkeyAction", args = "alt_plus_right" }
        self.key_events.AltPlusLPgB = { { "Alt", "LPgBack" }, { "Ctrl", "LPgBack" }, event = "HotkeyAction", args = "alt_plus_left_page_back" }
        self.key_events.AltPlusLPgF = { { "Alt",  "LPgFwd" }, { "Ctrl",  "LPgFwd" }, event = "HotkeyAction", args = "alt_plus_left_page_forward" }
        self.key_events.AltPlusRPgB = { { "Alt", "RPgBack" }, { "Ctrl", "RPgBack" }, event = "HotkeyAction", args = "alt_plus_right_page_back" }
        self.key_events.AltPlusRPgF = { { "Alt",  "RPgFwd" }, { "Ctrl",  "RPgFwd" }, event = "HotkeyAction", args = "alt_plus_right_page_forward" }
        self.key_events.AltPlusPrss = { { "Alt",   "Press" }, { "Ctrl",   "Press" }, event = "HotkeyAction", args = "alt_plus_press" }
        self.key_events.AltPlusBack = { { "Alt",    "Back" }, { "Ctrl",    "Back" }, event = "HotkeyAction", args = "alt_plus_back" }
        self.key_events.AltPlusHome = { { "Alt",    "Home" }, { "Ctrl",    "Home" }, event = "HotkeyAction", args = "alt_plus_home" }
        self.key_events.AltPlusMenu = { { "Alt",    "Menu" }, { "Ctrl",    "Menu" }, event = "HotkeyAction", args = "alt_plus_menu" }
        -- alphabet keys
        if Device.k3_alt_plus_key_kernel_translated then
            self.key_events.AltPlusQ = { { Device.k3_alt_plus_key_kernel_translated["Q"] }, event = "HotkeyAction", args = "alt_plus_q" }
            self.key_events.AltPlusW = { { Device.k3_alt_plus_key_kernel_translated["W"] }, event = "HotkeyAction", args = "alt_plus_w" }
            self.key_events.AltPlusE = { { Device.k3_alt_plus_key_kernel_translated["E"] }, event = "HotkeyAction", args = "alt_plus_e" }
            self.key_events.AltPlusR = { { Device.k3_alt_plus_key_kernel_translated["R"] }, event = "HotkeyAction", args = "alt_plus_r" }
            self.key_events.AltPlusT = { { Device.k3_alt_plus_key_kernel_translated["T"] }, event = "HotkeyAction", args = "alt_plus_t" }
            self.key_events.AltPlusY = { { Device.k3_alt_plus_key_kernel_translated["Y"] }, event = "HotkeyAction", args = "alt_plus_y" }
            self.key_events.AltPlusU = { { Device.k3_alt_plus_key_kernel_translated["U"] }, event = "HotkeyAction", args = "alt_plus_u" }
            self.key_events.AltPlusI = { { Device.k3_alt_plus_key_kernel_translated["I"] }, event = "HotkeyAction", args = "alt_plus_i" }
            self.key_events.AltPlusO = { { Device.k3_alt_plus_key_kernel_translated["O"] }, event = "HotkeyAction", args = "alt_plus_o" }
            self.key_events.AltPlusP = { { Device.k3_alt_plus_key_kernel_translated["P"] }, event = "HotkeyAction", args = "alt_plus_p" }
        else
            self.key_events.AltPlusQ = { { "Alt", "Q" }, { "Ctrl", "Q" }, event = "HotkeyAction", args = "alt_plus_q" }
            self.key_events.AltPlusW = { { "Alt", "W" }, { "Ctrl", "W" }, event = "HotkeyAction", args = "alt_plus_w" }
            self.key_events.AltPlusE = { { "Alt", "E" }, { "Ctrl", "E" }, event = "HotkeyAction", args = "alt_plus_e" }
            self.key_events.AltPlusR = { { "Alt", "R" }, { "Ctrl", "R" }, event = "HotkeyAction", args = "alt_plus_r" }
            self.key_events.AltPlusT = { { "Alt", "T" }, { "Ctrl", "T" }, event = "HotkeyAction", args = "alt_plus_t" }
            self.key_events.AltPlusY = { { "Alt", "Y" }, { "Ctrl", "Y" }, event = "HotkeyAction", args = "alt_plus_y" }
            self.key_events.AltPlusU = { { "Alt", "U" }, { "Ctrl", "U" }, event = "HotkeyAction", args = "alt_plus_u" }
            self.key_events.AltPlusI = { { "Alt", "I" }, { "Ctrl", "I" }, event = "HotkeyAction", args = "alt_plus_i" }
            self.key_events.AltPlusO = { { "Alt", "O" }, { "Ctrl", "O" }, event = "HotkeyAction", args = "alt_plus_o" }
            self.key_events.AltPlusP = { { "Alt", "P" }, { "Ctrl", "P" }, event = "HotkeyAction", args = "alt_plus_p" }
        end
        self.key_events.AltPlusA = { { "Alt", "A" }, { "Ctrl", "A" }, event = "HotkeyAction", args = "alt_plus_a" }
        self.key_events.AltPlusS = { { "Alt", "S" }, { "Ctrl", "S" }, event = "HotkeyAction", args = "alt_plus_s" }
        self.key_events.AltPlusD = { { "Alt", "D" }, { "Ctrl", "D" }, event = "HotkeyAction", args = "alt_plus_d" }
        self.key_events.AltPlusF = { { "Alt", "F" }, { "Ctrl", "F" }, event = "HotkeyAction", args = "alt_plus_f" }
        self.key_events.AltPlusG = { { "Alt", "G" }, { "Ctrl", "G" }, event = "HotkeyAction", args = "alt_plus_g" }
        self.key_events.AltPlusH = { { "Alt", "H" }, { "Ctrl", "H" }, event = "HotkeyAction", args = "alt_plus_h" }
        self.key_events.AltPlusJ = { { "Alt", "J" }, { "Ctrl", "J" }, event = "HotkeyAction", args = "alt_plus_j" }
        self.key_events.AltPlusK = { { "Alt", "K" }, { "Ctrl", "K" }, event = "HotkeyAction", args = "alt_plus_k" }
        self.key_events.AltPlusL = { { "Alt", "L" }, { "Ctrl", "L" }, event = "HotkeyAction", args = "alt_plus_l" }
        self.key_events.AltPlusZ = { { "Alt", "Z" }, { "Ctrl", "Z" }, event = "HotkeyAction", args = "alt_plus_z" }
        self.key_events.AltPlusX = { { "Alt", "X" }, { "Ctrl", "X" }, event = "HotkeyAction", args = "alt_plus_x" }
        self.key_events.AltPlusC = { { "Alt", "C" }, { "Ctrl", "C" }, event = "HotkeyAction", args = "alt_plus_c" }
        self.key_events.AltPlusV = { { "Alt", "V" }, { "Ctrl", "V" }, event = "HotkeyAction", args = "alt_plus_v" }
        self.key_events.AltPlusB = { { "Alt", "B" }, { "Ctrl", "B" }, event = "HotkeyAction", args = "alt_plus_b" }
        self.key_events.AltPlusN = { { "Alt", "N" }, { "Ctrl", "N" }, event = "HotkeyAction", args = "alt_plus_n" }
        self.key_events.AltPlusM = { { "Alt", "M" }, { "Ctrl", "M" }, event = "HotkeyAction", args = "alt_plus_m" }
    end
end

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
    -- table.remove(sub_items, 13) -- removes 'Keep QuickMenu open' as it acts out on NT.
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
    menu_items.hotkeyshortcuts = {
        text = _("Shortcuts"),
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
