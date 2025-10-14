local Device = require("device")
if not Device:isTouchDevice() then
    return { disabled = true }
end

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureDetector = require("device/gesturedetector")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Screen = require("device").screen
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = ffiUtil.template

local Gestures = WidgetContainer:extend{
    name = "gestures",
    settings_data = nil,
    gestures = nil,
    defaults = nil,
    custom_multiswipes = nil,
    updated = false,
    has_multitouch = Device:hasMultitouch(),
}
local gestures_path = ffiUtil.joinPath(DataStorage:getSettingsDir(), "gestures.lua")

local section_titles = {
    tap_corner          = _("Tap corner"),
    hold_corner         = _("Long-press on corner"),
    one_finger_swipe    = _("One-finger swipe"),
    double_tap          = _("Double tap"),
    two_finger_tap      = _("Two-finger tap corner"),
    two_finger_swipe    = _("Two-finger swipe"),
    spread_and_pinch    = _("Spread and pinch"),
    two_finger_rotation = _("Two-finger rotation"),
    multiswipes         = _("Multiswipes"),
    custom_multiswipes  = _("Custom multiswipes"),
}

local section_items = {
    tap_corner = {
        "tap_top_left_corner",
        "tap_top_right_corner",
        "tap_left_bottom_corner",
        "tap_right_bottom_corner",
    },
    hold_corner = {
        "hold_top_left_corner",
        "hold_top_right_corner",
        "hold_bottom_left_corner",
        "hold_bottom_right_corner",
    },
    one_finger_swipe = {
        "short_diagonal_swipe",
        "one_finger_swipe_left_edge_down",
        "one_finger_swipe_left_edge_up",
        "one_finger_swipe_right_edge_down",
        "one_finger_swipe_right_edge_up",
        "one_finger_swipe_top_edge_right",
        "one_finger_swipe_top_edge_left",
        "one_finger_swipe_bottom_edge_right",
        "one_finger_swipe_bottom_edge_left",
    },
    double_tap = {
        "double_tap_left_side",
        "double_tap_right_side",
        "double_tap_top_left_corner",
        "double_tap_top_right_corner",
        "double_tap_bottom_left_corner",
        "double_tap_bottom_right_corner",
    },
    two_finger_tap = {
        "two_finger_tap_top_left_corner",
        "two_finger_tap_top_right_corner",
        "two_finger_tap_bottom_left_corner",
        "two_finger_tap_bottom_right_corner",
    },
    two_finger_swipe = {
        "two_finger_swipe_east",
        "two_finger_swipe_west",
        "two_finger_swipe_south",
        "two_finger_swipe_north",
        "two_finger_swipe_northeast",
        "two_finger_swipe_northwest",
        "two_finger_swipe_southeast",
        "two_finger_swipe_southwest",
    },
    spread_and_pinch = {
        "spread_gesture",
        "pinch_gesture",
    },
    two_finger_rotation = {
        "rotate_cw",
        "rotate_ccw",
    },
}

local gestures_list = {
    tap_top_left_corner = _("Top left"),
    tap_top_right_corner = _("Top right"),
    tap_left_bottom_corner = _("Bottom left"),
    tap_right_bottom_corner = _("Bottom right"),
    hold_top_left_corner = _("Top left"),
    hold_top_right_corner = _("Top right"),
    hold_bottom_left_corner = _("Bottom left"),
    hold_bottom_right_corner = _("Bottom right"),
    one_finger_swipe_left_edge_down = _("Left edge down"),
    one_finger_swipe_left_edge_up = _("Left edge up"),
    one_finger_swipe_right_edge_down = _("Right edge down"),
    one_finger_swipe_right_edge_up = _("Right edge up"),
    one_finger_swipe_top_edge_right = _("Top edge right"),
    one_finger_swipe_top_edge_left = _("Top edge left"),
    one_finger_swipe_bottom_edge_right = _("Bottom edge right"),
    one_finger_swipe_bottom_edge_left = _("Bottom edge left"),
    double_tap_left_side = _("Left side"),
    double_tap_right_side = _("Right side"),
    double_tap_top_left_corner = _("Top left"),
    double_tap_top_right_corner = _("Top right"),
    double_tap_bottom_left_corner = _("Bottom left"),
    double_tap_bottom_right_corner = _("Bottom right"),
    two_finger_tap_top_left_corner = _("Top left"),
    two_finger_tap_top_right_corner = _("Top right"),
    two_finger_tap_bottom_left_corner = _("Bottom left"),
    two_finger_tap_bottom_right_corner = _("Bottom right"),
    short_diagonal_swipe = _("Short diagonal swipe"),
    two_finger_swipe_east = "⇒",
    two_finger_swipe_west = "⇐",
    two_finger_swipe_south = "⇓",
    two_finger_swipe_north = "⇑",
    two_finger_swipe_northeast = "⇗",
    two_finger_swipe_northwest = "⇖",
    two_finger_swipe_southeast = "⇘",
    two_finger_swipe_southwest = "⇙",
    spread_gesture = _("Spread"),
    pinch_gesture = _("Pinch"),
    rotate_cw = _("Rotate clockwise ⤸ 90°"),
    rotate_ccw = _("Rotate counterclockwise ⤹ 90°"),
    multiswipe = "", -- otherwise registerGesture() won't pick up on multiswipes
    multiswipe_west_east = "⬅ ➡",
    multiswipe_east_west = "➡ ⬅",
    multiswipe_north_east = "⬆ ➡",
    multiswipe_north_west = "⬆ ⬅",
    multiswipe_north_south = "⬆ ⬇",
    multiswipe_east_north = "➡ ⬆",
    multiswipe_west_north = "⬅ ⬆",
    multiswipe_east_south = "➡ ⬇",
    multiswipe_south_north = "⬇ ⬆",
    multiswipe_south_east = "⬇ ➡",
    multiswipe_south_west = "⬇ ⬅",
    multiswipe_west_south = "⬅ ⬇",
    multiswipe_north_south_north = "⬆ ⬇ ⬆",
    multiswipe_south_north_south = "⬇ ⬆ ⬇",
    multiswipe_west_east_west = "⬅ ➡ ⬅",
    multiswipe_east_west_east = "➡ ⬅ ➡",
    multiswipe_south_west_north = "⬇ ⬅ ⬆",
    multiswipe_north_east_south = "⬆ ➡ ⬇",
    multiswipe_north_west_south = "⬆ ⬅ ⬇",
    multiswipe_west_south_east = "⬅ ⬇ ➡",
    multiswipe_west_north_east = "⬅ ⬆ ➡",
    multiswipe_east_south_west = "➡ ⬇ ⬅",
    multiswipe_east_north_west = "➡ ⬆ ⬅",
    multiswipe_south_east_north = "⬇ ➡ ⬆",
    multiswipe_east_north_west_east = "➡ ⬆ ⬅ ➡",
    multiswipe_south_east_north_south = "⬇ ➡ ⬆ ⬇",
    multiswipe_east_south_west_north = "➡ ⬇ ⬅ ⬆",
    multiswipe_west_south_east_north = "⬅ ⬇ ➡ ⬆",
    multiswipe_south_east_north_west = "⬇ ➡ ⬆ ⬅",
    multiswipe_south_west_north_east = "⬇ ⬅ ⬆ ➡",
    multiswipe_southeast_northeast = "⬊ ⬈",
    multiswipe_northeast_southeast = "⬈ ⬊",
    multiswipe_northwest_southwest_northwest = "⬉ ⬋ ⬉",
    multiswipe_southeast_southwest_northwest = "⬊ ⬋ ⬉",
    multiswipe_southeast_northeast_northwest = "⬊ ⬈ ⬉",
}

local multiswipes_info_text = _([[
Multiswipes allow you to perform complex gestures built up out of multiple swipe directions, never losing touch with the screen.

These advanced gestures consist of either straight swipes or diagonal swipes. To ensure accuracy, they can't be mixed.]])

-- If the gesture contains "toggle_touch_input" or "touch_input_on" actions, or is set "Always active" manually,
-- mark it "always active" to make sure that InputContainer won't block it after the IgnoreTouchInput Event.
function Gestures:isGestureAlwaysActive(ges, multiswipe_directions)
    -- Handle multiswipes properly
    -- NOTE: This is a bit clunky, as ges comes from the list of registered touch zones,
    --       while multiswipe_directions comes from the actual input event.
    --       Alas, all our multiswipe gestures are handled by a single "multiswipe" zone.
    if self.multiswipes_enabled then
        if ges == "multiswipe" and multiswipe_directions then
            ges = "multiswipe_" .. self:safeMultiswipeName(multiswipe_directions)
        end
    end

    local gest = self.gestures[ges]
    return gest and (gest.toggle_touch_input or gest.touch_input_on or (gest.settings and gest.settings.always_active))
end

function Gestures:init()
    local defaults_path = ffiUtil.joinPath(self.path, "defaults.lua")
    self.ignore_hold_corners = G_reader_settings:isTrue("ignore_hold_corners")
    self.multiswipes_enabled = G_reader_settings:isTrue("multiswipes_enabled")
    self.is_docless = self.ui.document == nil
    self.ges_mode = self.is_docless and "gesture_fm" or "gesture_reader"
    self.defaults = LuaSettings:open(defaults_path).data[self.ges_mode]
    if not self.settings_data then
        self.settings_data = LuaSettings:open(gestures_path)
        if not next(self.settings_data.data) then
            logger.warn("No gestures file or invalid gestures file found, copying defaults")
            self.settings_data:purge()
            ffiUtil.copyFile(defaults_path, gestures_path)
            self.settings_data = LuaSettings:open(gestures_path)
        end
    end
    self.gestures = self.settings_data.data[self.ges_mode]
    self.custom_multiswipes = self.settings_data.data["custom_multiswipes"]
    if G_reader_settings:has("gesture_fm") or G_reader_settings:has("gesture_reader") then
        -- Migrate old gestures
        local Migration = require("migration")
        Migration:migrateGestures(self)
    end

    -- Some of these defaults need to be reversed in RTL mirrored UI,
    -- and as we set them in the saved gestures, we need to reset them
    -- to the defaults in case of UI language's direction change.
    local mirrored_if_rtl = {
        tap_top_left_corner = "tap_top_right_corner",
        tap_right_bottom_corner = "tap_left_bottom_corner",
        double_tap_left_side = "double_tap_right_side",
    }

    local is_rtl = BD.mirroredUILayout()
    if is_rtl then
        for k, v in pairs(mirrored_if_rtl) do
            self.defaults[k], self.defaults[v] = self.defaults[v], self.defaults[k]
        end
    end
    -- We remember the last UI direction gestures were made on. If it changes,
    -- reset the mirrored_if_rtl ones to the default for the new direction.
    local ges_dir_setting = self.ges_mode.."ui_lang_direction_rtl"
    local prev_lang_dir_rtl = G_reader_settings:isTrue(ges_dir_setting)
    if (is_rtl and not prev_lang_dir_rtl) or (not is_rtl and prev_lang_dir_rtl) then
        local reset = false
        for k, v in pairs(mirrored_if_rtl) do
            -- We only replace them if they are still the other direction's default.
            -- If not, the user has changed them: let him deal with setting new ones if needed.
            if util.tableEquals(self.gestures[k], self.defaults[v]) then
                self.gestures[k] = self.defaults[k]
                reset = true
            end
            if util.tableEquals(self.gestures[v], self.defaults[k]) then
                self.gestures[v] = self.defaults[v]
                reset = true
            end
        end
        if reset then
            self.updated = true
            logger.info("UI language direction changed: resetting some gestures to direction default")
        end
        G_reader_settings:flipNilOrFalse(ges_dir_setting)
    end

    self.ui.menu:registerToMainMenu(self)
    Dispatcher:init()
    self:initGesture()
    -- Overload InputContainer's stub to allow it to recognize "always active" gestures
    InputContainer.isGestureAlwaysActive = function(this, ges, multiswipe_directions) return self:isGestureAlwaysActive(ges, multiswipe_directions) end
end

function Gestures:onCloseWidget()
    -- Restore the stub implementation on teardown, to avoid pinning a stale instance of ourselves
    InputContainer.isGestureAlwaysActive = InputContainer._isGestureAlwaysActive
end

function Gestures:gestureTitleFunc(ges)
    local title = gestures_list[ges] or self:friendlyMultiswipeName(ges)
    return T(_("%1   (%2)"), title, Dispatcher:menuTextFunc(self.gestures[ges]))
end

function Gestures:genMenu(ges)
    local sub_items = {}
    if gestures_list[ges] ~= nil then
        table.insert(sub_items, {
            text = T(_("%1 (default)"), Dispatcher:menuTextFunc(self.defaults[ges])),
            checked_func = function()
                return util.tableEquals(self.gestures[ges], self.defaults[ges])
            end,
            check_callback_updates_menu = true,
            radio = true,
            callback = function(touchmenu_instance)
                local function do_remove()
                    self.gestures[ges] = util.tableDeepCopy(self.defaults[ges])
                    self.updated = true
                    touchmenu_instance:updateItems()
                end
                Dispatcher.removeActions(self.gestures[ges], do_remove)
            end,
            separator = true,
        })
    end
    table.insert(sub_items, {
        text = _("Pass through"),
        checked_func = function()
            return self.gestures[ges] == nil
        end,
        check_callback_updates_menu = true,
        radio = true,
        callback = function(touchmenu_instance)
            local function do_remove()
                self.gestures[ges] = nil
                self.updated = true
                touchmenu_instance:updateItems()
            end
            Dispatcher.removeActions(self.gestures[ges], do_remove)
        end,
    })
    Dispatcher:addSubMenu(self, sub_items, self.gestures, ges)
    sub_items.max_per_page = nil -- restore default, settings in page 2
    table.insert(sub_items, {
        text = _("Anchor QuickMenu to gesture position"),
        enabled_func = function()
            return util.tableGetValue(self.gestures, ges, "settings", "show_as_quickmenu") or false
        end,
        checked_func = function()
            return util.tableGetValue(self.gestures, ges, "settings", "anchor_quickmenu")
        end,
        callback = function()
            if self.gestures[ges] then
                if util.tableGetValue(self.gestures, ges, "settings", "anchor_quickmenu") then
                    util.tableRemoveValue(self.gestures, ges, "settings", "anchor_quickmenu")
                else
                    util.tableSetValue(self.gestures, true, ges, "settings", "anchor_quickmenu")
                end
                self.updated = true
            end
        end,
        separator = true,
    })
    table.insert(sub_items, {
        text = _("Always active"),
        checked_func = function()
            return util.tableGetValue(self.gestures, ges, "settings", "always_active")
        end,
        callback = function()
            if self.gestures[ges] then
                if util.tableGetValue(self.gestures, ges, "settings", "always_active") then
                    util.tableRemoveValue(self.gestures, ges, "settings", "always_active")
                else
                    util.tableSetValue(self.gestures, true, ges, "settings", "always_active")
                end
                self.updated = true
            end
        end,
    })
    return sub_items
end

function Gestures:genSubItem(ges, separator, hold_callback)
    local reader_only = {tap_top_left_corner=true, tap_top_right_corner=true, hold_top_left_corner=true,}
    local enabled_func
    if reader_only[ges] then
       enabled_func = function() return self.ges_mode == "gesture_reader" end
    end
    return {
        text_func = function() return self:gestureTitleFunc(ges) end,
        enabled_func = enabled_func,
        sub_item_table_func = function() return self:genMenu(ges) end,
        separator = separator,
        hold_callback = hold_callback,
        ignored_by_menu_search = true, -- This item is not strictly duplicated, but its subitems are.
                                       -- Ignoring it speeds up search.
    }
end

function Gestures:genSubItemTable(gestures)
    local sub_item_table = {}
    for _, item in ipairs(gestures) do
        table.insert(sub_item_table, self:genSubItem(item))
    end
    return sub_item_table
end

function Gestures:genMultiswipeMenu(get_list)
    -- { multiswipe name, separator }
    local multiswipe_list = {
        {"multiswipe_west_east",},
        {"multiswipe_east_west",},
        {"multiswipe_north_south",},
        {"multiswipe_south_north", true},
        {"multiswipe_north_west",},
        {"multiswipe_north_east",},
        {"multiswipe_south_west",},
        {"multiswipe_south_east",},
        {"multiswipe_east_north",},
        {"multiswipe_west_north",},
        {"multiswipe_east_south",},
        {"multiswipe_west_south", true},
        {"multiswipe_north_south_north",},
        {"multiswipe_south_north_south",},
        {"multiswipe_west_east_west",},
        {"multiswipe_east_west_east", true},
        {"multiswipe_south_west_north",},
        {"multiswipe_north_east_south",},
        {"multiswipe_north_west_south",},
        {"multiswipe_west_south_east",},
        {"multiswipe_west_north_east",},
        {"multiswipe_east_south_west",},
        {"multiswipe_east_north_west",},
        {"multiswipe_south_east_north", true},
        {"multiswipe_east_north_west_east",},
        {"multiswipe_south_east_north_south", true},
        {"multiswipe_east_south_west_north",},
        {"multiswipe_west_south_east_north",},
        {"multiswipe_south_east_north_west",},
        {"multiswipe_south_west_north_east", true},
        {"multiswipe_southeast_northeast",},
        {"multiswipe_northeast_southeast",},
        {"multiswipe_northwest_southwest_northwest",},
        {"multiswipe_southeast_southwest_northwest",},
        {"multiswipe_southeast_northeast_northwest",},
    }
    if get_list then
        return multiswipe_list
    end
    local sub_item_table = {}
    for _, item in ipairs(multiswipe_list) do
        table.insert(sub_item_table, self:genSubItem(item[1], item[2]))
    end
    return sub_item_table
end

local multiswipe_to_arrow = {
    east = "➡",
    west = "⬅",
    north = "⬆",
    south = "⬇",
    northeast = "⬈",
    northwest = "⬉",
    southeast = "⬊",
    southwest = "⬋",
}
function Gestures:friendlyMultiswipeName(multiswipe)
    return multiswipe:gsub("multiswipe", ""):gsub("_", " "):gsub("%S+", multiswipe_to_arrow)
end

function Gestures:safeMultiswipeName(multiswipe)
    return multiswipe:gsub(" ", "_")
end

function Gestures:multiswipeRecorder(touchmenu_instance)
    local multiswipe_recorder
    multiswipe_recorder = InputDialog:new{
        title = _("Multiswipe recorder"),
        input_hint = _("Make a multiswipe gesture"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(multiswipe_recorder)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local recorded_multiswipe = multiswipe_recorder._raw_multiswipe
                        if not recorded_multiswipe then return end
                        logger.dbg("Multiswipe recorder detected:", recorded_multiswipe)

                        if gestures_list[recorded_multiswipe] ~= nil then
                            UIManager:show(InfoMessage:new{
                                text = _("Recorded multiswipe already exists."),
                                show_icon = false,
                                timeout = 5,
                            })
                            return
                        end

                        self.custom_multiswipes[recorded_multiswipe] = true
                        self.updated = true
                        --touchmenu_instance.item_table = self:genMultiswipeMenu()
                        -- We need to update touchmenu_instance.item_table in-place for the upper
                        -- menu to have it updated too
                        local item_table = touchmenu_instance.item_table
                        while #item_table > 0 do
                            table.remove(item_table, #item_table)
                        end
                        for __, v in ipairs(self:genCustomMultiswipeSubmenu()) do
                            table.insert(item_table, v)
                        end
                        touchmenu_instance:updateItems()
                        UIManager:close(multiswipe_recorder)
                    end,
                },
            }
        },
    }

    multiswipe_recorder.ges_events.Multiswipe = {
        GestureRange:new{
            ges = "multiswipe",
            range = Geom:new{
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            },
        }
    }

    function multiswipe_recorder:onMultiswipe(arg, ges)
        multiswipe_recorder._raw_multiswipe = "multiswipe_" .. Gestures:safeMultiswipeName(ges.multiswipe_directions)
        multiswipe_recorder:setInputText(Gestures:friendlyMultiswipeName(ges.multiswipe_directions))
    end

    UIManager:show(multiswipe_recorder)
end


function Gestures:genCustomMultiswipeSubmenu()
    local submenu = {
        {
            text = _("Multiswipe recorder"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:multiswipeRecorder(touchmenu_instance)
            end,
            help_text = _("The number of possible multiswipe gestures is theoretically infinite. With the multiswipe recorder you can easily record your own."),
        },
    }
    for item in ffiUtil.orderedPairs(self.custom_multiswipes) do
        local hold_callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = T(_("Remove custom multiswipe %1?"), self:friendlyMultiswipeName(item)),
                ok_text = _("Remove"),
                ok_callback = function()
                    -- remove from list of custom multiswipes
                    self.custom_multiswipes[item] = nil
                    -- remove any settings for the muliswipe
                    self.settings_data.data["gesture_fm"][item] = nil
                    self.settings_data.data["gesture_reader"][item] = nil
                    self.updated = true

                    --touchmenu_instance.item_table = self:genMultiswipeMenu()
                    -- We need to update touchmenu_instance.item_table in-place for the upper
                    -- menu to have it updated too
                    local item_table = touchmenu_instance.item_table
                    while #item_table > 0 do
                        table.remove(item_table, #item_table)
                    end
                    for __, v in ipairs(self:genCustomMultiswipeSubmenu()) do
                        table.insert(item_table, v)
                    end
                    touchmenu_instance:updateItems()
                end,
            })
        end
        table.insert(submenu, self:genSubItem(item, nil, hold_callback))
    end
    return submenu
end

function Gestures:onShowGestureOverview()
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local nothing = Dispatcher:menuTextFunc({})
    local kv_pairs = {}
    local function add_section(section_id, items)
        items = items or section_items[section_id]
        local pos = #kv_pairs + 1
        local added
        for _, ges_name in ipairs(items) do
            if section_id == "multiswipes" then
                ges_name = ges_name[1]
            end
            local gest = self.gestures[ges_name]
            if gest then
                local value = Dispatcher:menuTextFunc(gest)
                if value ~= nothing then
                    local key = gestures_list[ges_name] or self:friendlyMultiswipeName(ges_name)
                    local callback
                    if Dispatcher:_itemsCount(gest) > 1 then -- multi-action gesture
                        local text = {}
                        for item, v in Dispatcher.iter_func(gest) do
                            if type(item) == "number" then item = v end
                            if gest[item] ~= nil then
                                table.insert(text, " " .. Dispatcher:getNameFromItem(item, gest))
                            end
                        end
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = table.concat(text, "\n"),
                                show_icon = false,
                            })
                        end
                    end
                    table.insert(kv_pairs, { key, value, callback = callback, key_bold = false })
                    added = true
                end
            end
        end
        if added then
            table.insert(kv_pairs, pos, { section_titles[section_id], " " })
            kv_pairs[#kv_pairs].separator = true
        end
    end
    add_section("tap_corner")
    add_section("hold_corner")
    add_section("one_finger_swipe")
    if not self.is_docless and self.ui.disable_double_tap ~= true then
        add_section("double_tap")
    end
    if self.has_multitouch then
        add_section("two_finger_tap")
        add_section("two_finger_swipe")
        add_section("spread_and_pinch")
        add_section("two_finger_rotation")
    end
    if self.multiswipes_enabled then
        add_section("multiswipes", self:genMultiswipeMenu(true))
        if next(self.custom_multiswipes) then
            local items = {}
            for item in ffiUtil.orderedPairs(self.custom_multiswipes) do
                table.insert(items, item)
            end
            add_section("custom_multiswipes", items)
        end
    end
    UIManager:show(KeyValuePage:new{
        title = self.is_docless and _("Gestures in file browser") or _("Gestures in reader"),
        value_overflow_align = "right",
        kv_pairs = kv_pairs,
    })
end

function Gestures:addIntervals(menu_items)
    menu_items.gesture_intervals = {
        text = _("Gesture intervals"),
        sub_item_table = {
            {
                text = _("Text selection rate"),
                keep_menu_open = true,
                callback = function()
                    local default_value = Screen.low_pan_rate and 5.0 or 30.0
                    local current_value = G_reader_settings:readSetting("hold_pan_rate", default_value)
                    local items = SpinWidget:new{
                        title_text = _("Text selection rate"),
                        info_text = _([[
The rate is how often screen will be refreshed per second while selecting text.
Higher values mean faster screen updates, but also use more CPU.]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = current_value,
                        value_min = 1.0,
                        value_max = 60.0,
                        value_step = 1,
                        value_hold_step = 15,
                        unit = C_("Frequency", "Hz"),
                        ok_text = _("Set rate"),
                        default_value = default_value,
                        callback = function(spin)
                            G_reader_settings:saveSetting("hold_pan_rate", spin.value)
                            UIManager:broadcastEvent(Event:new("UpdateHoldPanRate"))
                        end
                    }
                    UIManager:show(items)
                end,
                separator = true,
            },
            {
                text = _("Tap interval"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Tap interval"),
                        info_text = _([[
Any other taps made within this interval after a first tap will be considered accidental and ignored.

The interval value is in milliseconds and can range from 0 (0 seconds) to 2000 (2 seconds).]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(GestureDetector.ges_tap_interval),
                        value_min = 0,
                        value_max = 2000,
                        value_step = 50,
                        value_hold_step = 200,
                        unit = C_("Time", "ms"),
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.TAP_INTERVAL_MS,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_tap_interval_ms", spin.value)
                            GestureDetector.ges_tap_interval = time.ms(spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Tap interval on keyboard"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Tap interval on keyboard"),
                        info_text = _([[
Any other taps made within this interval after a first tap will be considered accidental and ignored.

The interval value is in milliseconds and can range from 0 (0 seconds) to 2000 (2 seconds).]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(G_reader_settings:readSetting("ges_tap_interval_on_keyboard_ms", 0)),
                        value_min = 0,
                        value_max = 2000,
                        value_step = 50,
                        value_hold_step = 200,
                        unit = C_("Time", "ms"),
                        ok_text = _("Set interval"),
                        default_value = 0,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_tap_interval_on_keyboard_ms", spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Double tap interval"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Double tap interval"),
                        info_text = _([[
When double tap is enabled, this sets the time to wait for the second tap. A single tap will take at least this long to be detected.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(GestureDetector.ges_double_tap_interval),
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        unit = C_("Time", "ms"),
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.DOUBLE_TAP_INTERVAL_MS,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_double_tap_interval_ms", spin.value)
                            GestureDetector.ges_double_tap_interval = time.ms(spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Two finger tap duration"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Two finger tap duration"),
                        info_text = _([[
This sets the allowed duration of any of the two fingers touch/release for the combined event to be considered a two finger tap.

The duration value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(GestureDetector.ges_two_finger_tap_duration),
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        unit = C_("Time", "ms"),
                        ok_text = _("Set duration"),
                        default_value = GestureDetector.TWO_FINGER_TAP_DURATION_MS,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_two_finger_tap_duration_ms", spin.value)
                            GestureDetector.ges_two_finger_tap_duration = time.ms(spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Long-press interval"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Long-press interval"),
                        info_text = _([[
If a touch is not released in this interval, it is considered a long-press. On document text, single word selection will then be triggered.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to the very-long-press interval.]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(GestureDetector.ges_hold_interval),
                        value_min = 100,
                        value_max = 1000 * (G_reader_settings:readSetting("highlight_long_hold_threshold_s")
                                         or GestureDetector.LONG_HOLD_INTERVAL_S) - 100,
                        value_step = 100,
                        value_hold_step = 500,
                        unit = C_("Time", "ms"),
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.HOLD_INTERVAL_MS,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_hold_interval_ms", spin.value)
                            GestureDetector.ges_hold_interval = time.ms(spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Swipe interval"),
                keep_menu_open = true,
                callback = function()
                    local items = SpinWidget:new{
                        title_text = _("Swipe interval"),
                        info_text = _([[
This sets the maximum delay between the start and the end of a swipe for it to be considered a swipe. Above this interval, it's considered panning.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = time.to_ms(GestureDetector.ges_swipe_interval),
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        unit = C_("Time", "ms"),
                        value_hold_step = 500,
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.SWIPE_INTERVAL_MS,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_swipe_interval_ms", spin.value)
                            GestureDetector.ges_swipe_interval = time.ms(spin.value)
                        end
                    }
                    UIManager:show(items)
                end,
            },
        }
    }
end

function Gestures:addToMainMenu(menu_items)
    menu_items.gesture_manager = {
        text = _("Gesture manager"),
        sub_item_table = {
            max_per_page = 11,
            {
                text = _("Turn on multiswipes"),
                checked_func = function() return self.multiswipes_enabled end,
                callback = function()
                    G_reader_settings:toggle("multiswipes_enabled")
                    self.multiswipes_enabled = G_reader_settings:isTrue("multiswipes_enabled")
                end,
                help_text = multiswipes_info_text,
            },
            {
                text = section_titles.multiswipes,
                sub_item_table = self:genMultiswipeMenu(),
                enabled_func = function() return self.multiswipes_enabled end,
            },
            {
                text = section_titles.custom_multiswipes,
                sub_item_table = self:genCustomMultiswipeSubmenu(),
                enabled_func = function() return self.multiswipes_enabled end,
                separator = true,
            },
            {
                text = section_titles.tap_corner,
                sub_item_table = self:genSubItemTable(section_items.tap_corner),
            },
            {
                text = section_titles.hold_corner,
                sub_item_table = self:genSubItemTable(section_items.hold_corner),
            },
            {
                text = section_titles.one_finger_swipe,
                sub_item_table = self:genSubItemTable(section_items.one_finger_swipe),
            },
            {
                text = section_titles.double_tap,
                enabled_func = function()
                    return not self.is_docless and self.ui.disable_double_tap ~= true
                end,
                sub_item_table = self:genSubItemTable(section_items.double_tap),
            },
        },
    }

    if self.has_multitouch then
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = section_titles.two_finger_tap,
            sub_item_table = self:genSubItemTable(section_items.two_finger_tap),
        })
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = section_titles.two_finger_swipe,
            sub_item_table = self:genSubItemTable(section_items.two_finger_swipe),
        })
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = section_titles.spread_and_pinch,
            sub_item_table = self:genSubItemTable(section_items.spread_and_pinch),
        })
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = section_titles.two_finger_rotation,
            sub_item_table = self:genSubItemTable(section_items.two_finger_rotation),
        })
    end

    menu_items.gesture_overview = {
        text = _("Gesture overview"),
        keep_menu_open = true,
        callback = function()
            self:onShowGestureOverview()
        end,
    }

    self:addIntervals(menu_items)
end

function Gestures:initGesture()
    for ges, _ in pairs(gestures_list) do
        self:setupGesture(ges)
    end
end

function Gestures:setupGesture(ges)
    local ges_type
    local zone
    local overrides
    local direction, distance

    local zone_fullscreen = {
        ratio_x = 0, ratio_y = 0,
        ratio_w = 1, ratio_h = 1,
    }

    local dswipe_zone_left_edge = G_defaults:readSetting("DSWIPE_ZONE_LEFT_EDGE")
    local zone_left_edge = {
        ratio_x = dswipe_zone_left_edge.x,
        ratio_y = dswipe_zone_left_edge.y,
        ratio_w = dswipe_zone_left_edge.w,
        ratio_h = dswipe_zone_left_edge.h,
    }
    local dswipe_zone_right_edge = G_defaults:readSetting("DSWIPE_ZONE_RIGHT_EDGE")
    local zone_right_edge = {
        ratio_x = dswipe_zone_right_edge.x,
        ratio_y = dswipe_zone_right_edge.y,
        ratio_w = dswipe_zone_right_edge.w,
        ratio_h = dswipe_zone_right_edge.h,
    }
    local dswipe_zone_top_edge = G_defaults:readSetting("DSWIPE_ZONE_TOP_EDGE")
    local zone_top_edge = {
        ratio_x = dswipe_zone_top_edge.x,
        ratio_y = dswipe_zone_top_edge.y,
        ratio_w = dswipe_zone_top_edge.w,
        ratio_h = dswipe_zone_top_edge.h,
    }
    local dswipe_zone_bottom_edge = G_defaults:readSetting("DSWIPE_ZONE_BOTTOM_EDGE")
    local zone_bottom_edge = {
        ratio_x = dswipe_zone_bottom_edge.x,
        ratio_y = dswipe_zone_bottom_edge.y,
        ratio_w = dswipe_zone_bottom_edge.w,
        ratio_h = dswipe_zone_bottom_edge.h,
    }

    local dtap_zone_top_left = G_defaults:readSetting("DTAP_ZONE_TOP_LEFT")
    local zone_top_left_corner = {
        ratio_x = dtap_zone_top_left.x,
        ratio_y = dtap_zone_top_left.y,
        ratio_w = dtap_zone_top_left.w,
        ratio_h = dtap_zone_top_left.h,
    }
    local dtap_zone_top_right = G_defaults:readSetting("DTAP_ZONE_TOP_RIGHT")
    local zone_top_right_corner = {
        ratio_x = dtap_zone_top_right.x,
        ratio_y = dtap_zone_top_right.y,
        ratio_w = dtap_zone_top_right.w,
        ratio_h = dtap_zone_top_right.h,
    }
    local dtap_zone_bottom_left = G_defaults:readSetting("DTAP_ZONE_BOTTOM_LEFT")
    local zone_bottom_left_corner = {
        ratio_x = dtap_zone_bottom_left.x,
        ratio_y = dtap_zone_bottom_left.y,
        ratio_w = dtap_zone_bottom_left.w,
        ratio_h = dtap_zone_bottom_left.h,
    }
    local dtap_zone_bottom_right = G_defaults:readSetting("DTAP_ZONE_BOTTOM_RIGHT")
    local zone_bottom_right_corner = {
        ratio_x = dtap_zone_bottom_right.x,
        ratio_y = dtap_zone_bottom_right.y,
        ratio_w = dtap_zone_bottom_right.w,
        ratio_h = dtap_zone_bottom_right.h,
    }
    -- NOTE: The defaults are effectively mapped to G_defaults:readSetting("DTAP_ZONE_BACKWARD") & G_defaults:readSetting("DTAP_ZONE_FORWARD")
    local ddouble_tap_zone_prev_chapter = G_defaults:readSetting("DDOUBLE_TAP_ZONE_PREV_CHAPTER")
    local zone_left = {
        ratio_x = ddouble_tap_zone_prev_chapter.x,
        ratio_y = ddouble_tap_zone_prev_chapter.y,
        ratio_w = ddouble_tap_zone_prev_chapter.w,
        ratio_h = ddouble_tap_zone_prev_chapter.h,
    }
    local ddouble_tap_zone_next_chapter = G_defaults:readSetting("DDOUBLE_TAP_ZONE_NEXT_CHAPTER")
    local zone_right = {
        ratio_x = ddouble_tap_zone_next_chapter.x,
        ratio_y = ddouble_tap_zone_next_chapter.y,
        ratio_w = ddouble_tap_zone_next_chapter.w,
        ratio_h = ddouble_tap_zone_next_chapter.h,
    }

    local overrides_tap_corner
    local overrides_double_tap_corner
    local overrides_hold_corner
    local overrides_vertical_edge, overrides_horizontal_edge
    local overrides_pan, overrides_pan_release
    local overrides_swipe_pan, overrides_swipe_pan_release
    if self.is_docless then
        overrides_tap_corner = {
            "filemanager_ext_tap",
            "filemanager_tap",
        }
        overrides_horizontal_edge = {
            "filemanager_ext_swipe",
            "filemanager_swipe",
        }
    else
        overrides_tap_corner = {
            "readerfooter_tap",
            "readerconfigmenu_ext_tap",
            "readerconfigmenu_tap",
            "readermenu_ext_tap",
            "readermenu_tap",
            "tap_forward",
            "tap_backward",
        }
        overrides_double_tap_corner = {
            "double_tap_left_side",
            "double_tap_right_side",
        }
        overrides_hold_corner = {
            -- As hold corners are "ignored" by default, and we have
            -- a "Ignore hold on corners" menu item and gesture, let
            -- them have priority over word lookup and text selection.
            "readerhighlight_hold",
            "readerfooter_hold",
        }
        overrides_vertical_edge = {
            "readerconfigmenu_ext_swipe",
            "readerconfigmenu_swipe",
            "readermenu_ext_swipe",
            "readermenu_swipe",
            "paging_swipe",
            "rolling_swipe",
        }
        overrides_horizontal_edge = {
            "swipe_link",
            "readerconfigmenu_ext_swipe",
            "readerconfigmenu_swipe",
            "readermenu_ext_swipe",
            "readermenu_swipe",
            "paging_swipe",
            "rolling_swipe",
        }
        overrides_pan = {
            "paging_swipe",
            "rolling_swipe",
        }
        overrides_pan_release = {
            "paging_pan_release",
        }
    end

    if ges == "multiswipe" then
        ges_type = "multiswipe"
        zone = zone_fullscreen
        direction = {
            northeast = true, northwest = true,
            southeast = true, southwest = true,
            east = true, west = true,
            north = true, south = true,
        }
    elseif ges == "tap_top_left_corner" then
        ges_type = "tap"
        zone = zone_top_left_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_top_right_corner" then
        ges_type = "tap"
        zone = zone_top_right_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_right_bottom_corner" then
        ges_type = "tap"
        zone = zone_bottom_right_corner
        overrides = overrides_tap_corner
    elseif ges == "tap_left_bottom_corner" then
        ges_type = "tap"
        zone = zone_bottom_left_corner
        overrides = overrides_tap_corner
    elseif ges == "double_tap_left_side" then
        ges_type = "double_tap"
        zone = zone_left
    elseif ges == "double_tap_right_side" then
        ges_type = "double_tap"
        zone = zone_right
    elseif ges == "double_tap_top_left_corner" then
        ges_type = "double_tap"
        zone = zone_top_left_corner
        overrides = overrides_double_tap_corner
    elseif ges == "double_tap_top_right_corner" then
        ges_type = "double_tap"
        zone = zone_top_right_corner
        overrides = overrides_double_tap_corner
    elseif ges == "double_tap_bottom_right_corner" then
        ges_type = "double_tap"
        zone = zone_bottom_right_corner
        overrides = overrides_double_tap_corner
    elseif ges == "double_tap_bottom_left_corner" then
        ges_type = "double_tap"
        zone = zone_bottom_left_corner
        overrides = overrides_double_tap_corner
    elseif ges == "hold_top_left_corner" then
        ges_type = "hold"
        zone = zone_top_left_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_top_right_corner" then
        ges_type = "hold"
        zone = zone_top_right_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_bottom_right_corner" then
        ges_type = "hold"
        zone = zone_bottom_right_corner
        overrides = overrides_hold_corner
    elseif ges == "hold_bottom_left_corner" then
        ges_type = "hold"
        zone = zone_bottom_left_corner
        overrides = overrides_hold_corner
    elseif ges == "one_finger_swipe_left_edge_down" then
        ges_type = "swipe"
        zone = zone_left_edge
        direction = {south = true}
        overrides = overrides_vertical_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_left_edge_up" then
        ges_type = "swipe"
        zone = zone_left_edge
        direction = {north = true}
        overrides = overrides_vertical_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_right_edge_down" then
        ges_type = "swipe"
        zone = zone_right_edge
        direction = {south = true}
        overrides = overrides_vertical_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_right_edge_up" then
        ges_type = "swipe"
        zone = zone_right_edge
        direction = {north = true}
        overrides = overrides_vertical_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_top_edge_right" then
        ges_type = "swipe"
        zone = zone_top_edge
        direction = {east = true}
        overrides = overrides_horizontal_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_top_edge_left" then
        ges_type = "swipe"
        zone = zone_top_edge
        direction = {west = true}
        overrides = overrides_horizontal_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_bottom_edge_right" then
        ges_type = "swipe"
        zone = zone_bottom_edge
        direction = {east = true}
        overrides = overrides_horizontal_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "one_finger_swipe_bottom_edge_left" then
        ges_type = "swipe"
        zone = zone_bottom_edge
        direction = {west = true}
        overrides = overrides_horizontal_edge
        overrides_swipe_pan = overrides_pan
        overrides_swipe_pan_release = overrides_pan_release
    elseif ges == "two_finger_tap_top_left_corner" then
        ges_type = "two_finger_tap"
        zone = zone_top_left_corner
    elseif ges == "two_finger_tap_top_right_corner" then
        ges_type = "two_finger_tap"
        zone = zone_top_right_corner
    elseif ges == "two_finger_tap_bottom_right_corner" then
        ges_type = "two_finger_tap"
        zone = zone_bottom_right_corner
    elseif ges == "two_finger_tap_bottom_left_corner" then
        ges_type = "two_finger_tap"
        zone = zone_bottom_left_corner
    elseif ges == "two_finger_swipe_west" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {west = true}
    elseif ges == "two_finger_swipe_east" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {east = true}
    elseif ges == "two_finger_swipe_south" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {south = true}
    elseif ges == "two_finger_swipe_north" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {north = true}
    elseif ges == "two_finger_swipe_northwest" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {northwest = true}
    elseif ges == "two_finger_swipe_northeast" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {northeast = true}
    elseif ges == "two_finger_swipe_southwest" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {southwest = true}
    elseif ges == "two_finger_swipe_southeast" then
        ges_type = "two_finger_swipe"
        zone = zone_fullscreen
        direction = {southeast = true}
    elseif ges == "short_diagonal_swipe" then
        ges_type = "swipe"
        zone = {
            ratio_x = 0.0, ratio_y = 0,
            ratio_w = 1, ratio_h = 1,
        }
        direction = {northeast = true, northwest = true, southeast = true, southwest = true}
        distance = "short"
        if self.is_docless then
            overrides = {
                "filemanager_ext_tap",
                "filemanager_tap",
                "filemanager_ext_swipe",
                "filemanager_swipe",
            }
        else
            overrides = {
                "paging_swipe",
                "rolling_swipe",
            }
        end
    elseif ges == "spread_gesture" then
        ges_type = "spread"
        zone = zone_fullscreen
    elseif ges == "pinch_gesture" then
        ges_type = "pinch"
        zone = zone_fullscreen
    elseif ges == "rotate_cw" then
        ges_type = "rotate"
        zone = zone_fullscreen
        direction = {cw = true}
    elseif ges == "rotate_ccw" then
        ges_type = "rotate"
        zone = zone_fullscreen
        direction = {ccw = true}
    else return
    end
    self:registerGesture(ges, ges_type, zone, overrides, direction, distance)
    -- make dummy zone to disable panning and panning_release when gesture is swipe
    if ges_type == "swipe" and ges ~= "short_diagonal_swipe" then
        local pan_gesture = ges.."_pan"
        local pan_release_gesture = ges.."_pan_release"
        self:registerGesture(pan_gesture, "pan", zone, overrides_swipe_pan, direction, distance)
        self:registerGesture(pan_release_gesture, "pan_release", zone, overrides_swipe_pan_release, direction, distance)
    end
end

function Gestures:registerGesture(ges, ges_type, zone, overrides, direction, distance)
    self.ui:registerTouchZones({
        {
            id = ges,
            ges = ges_type,
            screen_zone = zone,
            handler = function(gest)
                if distance == "short" and gest.distance > Screen:scaleBySize(300) then return end
                if direction and not direction[gest.direction] then return end

                if ges == "multiswipe" then
                    return self:multiswipeAction(gest.multiswipe_directions, gest)
                end

                return self:gestureAction(ges, gest)
            end,
            overrides = overrides,
        },
    })
end

function Gestures:gestureAction(action, ges)
    if G_reader_settings:isTrue("gestures_migrated") then
        UIManager:show(InfoMessage:new{
            text = _("Gestures have been upgraded. You may now set more than one action per gesture."),
            show_icon = false,
        })
        G_reader_settings:delSetting("gestures_migrated")
        return true
    end
    local action_list = self.gestures[action]
    if action_list == nil
        or (ges.ges == "hold" and self.ignore_hold_corners) then
        return
    else
        self.ui:handleEvent(Event:new("HandledAsSwipe"))
        local exec_props = { gesture = ges }
        if action_list.settings and action_list.settings.anchor_quickmenu then
            exec_props.qm_anchor = ges.end_pos or ges.pos
        end
        Dispatcher:execute(action_list, exec_props)
    end
    return true
end

function Gestures:multiswipeAction(multiswipe_directions, ges)
    if self.multiswipes_enabled == nil then
        UIManager:show(ConfirmBox:new{
            text = _("You have just performed your first multiswipe gesture.") .."\n\n".. multiswipes_info_text,
            ok_text = _("Turn on"),
            ok_callback = function()
                G_reader_settings:makeTrue("multiswipes_enabled")
                self.multiswipes_enabled = true
            end,
            cancel_text = _("Turn off"),
            cancel_callback = function()
                G_reader_settings:makeFalse("multiswipes_enabled")
                self.multiswipes_enabled = false
            end,
        })
        return
    else
        if not self.multiswipes_enabled then return end
        local multiswipe_gesture_name = "multiswipe_"..self:safeMultiswipeName(multiswipe_directions)
        return self:gestureAction(multiswipe_gesture_name, ges)
    end
end

function Gestures:onIgnoreHoldCorners(ignore_hold_corners, no_notification)
    if ignore_hold_corners == nil then
        G_reader_settings:flipNilOrFalse("ignore_hold_corners")
    else
        G_reader_settings:saveSetting("ignore_hold_corners", ignore_hold_corners)
    end
    self.ignore_hold_corners = G_reader_settings:isTrue("ignore_hold_corners")

    if no_notification then return true end

    local Notification = require("ui/widget/notification")
    if G_reader_settings:readSetting("ignore_hold_corners") then
        Notification:notify(_("Ignore long-press on corners: on"))
    else
        Notification:notify(_("Ignore long-press on corners: off"))
    end
    return true
end

function Gestures:onFlushSettings()
    if self.settings_data and self.updated then
        self.settings_data:flush()
        self.updated = false
    end
end

function Gestures:onDispatcherActionNameChanged(action)
    for _, section in ipairs({ "gesture_fm", "gesture_reader" }) do
        local gestures = self.settings_data.data[section]
        for gesture_name, gesture in pairs(gestures) do
            if gesture[action.old_name] ~= nil then
                if gesture.settings and gesture.settings.order then
                    for i, action_in_order in ipairs(gesture.settings.order) do
                        if action_in_order == action.old_name then
                            if action.new_name then
                                gesture.settings.order[i] = action.new_name
                            else
                                table.remove(gesture.settings.order, i)
                                if #gesture.settings.order < 2 then
                                    gesture.settings.order = nil
                                    if next(gesture.settings) == nil then
                                        gesture.settings = nil
                                    end
                                end
                            end
                            break
                        end
                    end
                end
                gesture[action.old_name] = nil
                if action.new_name then
                    gesture[action.new_name] = true
                else
                    if next(gesture) == nil then
                        self.settings_data.data[section][gesture_name] = nil
                    end
                end
                self.updated = true
            end
        end
    end
end

function Gestures:onDispatcherActionValueChanged(action)
    for _, section in ipairs({ "gesture_fm", "gesture_reader" }) do
        local gestures = self.settings_data.data[section]
        for gesture_name, gesture in pairs(gestures) do
            if gesture[action.name] == action.old_value then
                gesture[action.name] = action.new_value
                if action.new_value == nil then
                    if gesture.settings and gesture.settings.order then
                        for i, action_in_order in ipairs(gesture.settings.order) do
                            if action_in_order == action.name then
                                table.remove(gesture.settings.order, i)
                                if #gesture.settings.order < 2 then
                                    gesture.settings.order = nil
                                    if next(gesture.settings) == nil then
                                        gesture.settings = nil
                                    end
                                end
                                break
                            end
                        end
                    end
                    if next(gesture) == nil then
                        self.settings_data.data[section][gesture_name] = nil
                    end
                end
                self.updated = true
            end
        end
    end
end

return Gestures
