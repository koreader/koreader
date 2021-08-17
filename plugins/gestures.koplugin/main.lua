local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local util = require("util")
local T = FFIUtil.template
local _ = require("gettext")
local logger = require("logger")

if not Device:isTouchDevice() then
    return { disabled = true, }
end

local Gestures = InputContainer:new{
    name = "gestures",
    settings_data = nil,
    gestures = nil,
    defaults = nil,
    custom_multiswipes = nil,
    updated = false,
}
local gestures_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), "gestures.lua")

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

function Gestures:init()
    local defaults_path = FFIUtil.joinPath(self.path, "defaults.lua")
    if not lfs.attributes(gestures_path, "mode") then
        FFIUtil.copyFile(defaults_path, gestures_path)
    end
    self.ignore_hold_corners = G_reader_settings:isTrue("ignore_hold_corners")
    self.multiswipes_enabled = G_reader_settings:isTrue("multiswipes_enabled")
    self.is_docless = self.ui == nil or self.ui.document == nil
    self.ges_mode = self.is_docless and "gesture_fm" or "gesture_reader"
    self.defaults = LuaSettings:open(defaults_path).data[self.ges_mode]
    if not self.settings_data then
        self.settings_data = LuaSettings:open(gestures_path)
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
end

local gestureTextFunc = function(location, ges)
    local item = location[ges]
    local action_name = _("Pass through")
    if item then
        local sub_item = next(item)
        if sub_item == nil then return _("Nothing") end
        action_name = Dispatcher:getNameFromItem(sub_item, location, ges)
        if next(item, sub_item) ~= nil then
            action_name = _("Many")
        end
    end
    return action_name
end

function Gestures:gestureTitleFunc(ges)
    local title = gestures_list[ges] or self:friendlyMultiswipeName(ges)
    return T(_("%1   (%2)"), title, gestureTextFunc(self.gestures, ges))
end

function Gestures:genMenu(ges)
    local sub_items = {}
    if gestures_list[ges] ~= nil then
        table.insert(sub_items, {
            text = T(_("%1 (default)"), gestureTextFunc(self.defaults, ges)),
            keep_menu_open = true,
            separator = true,
            checked_func = function()
                return util.tableEquals(self.gestures[ges], self.defaults[ges])
            end,
            callback = function()
                self.gestures[ges] = util.tableDeepCopy(self.defaults[ges])
                self.updated = true
            end,
        })
    end
    table.insert(sub_items, {
        text = _("Pass through"),
        keep_menu_open = true,
        separator = true,
        checked_func = function()
            return self.gestures[ges] == nil
        end,
        callback = function()
            self.gestures[ges] = nil
            self.updated = true
        end,
    })
    Dispatcher:addSubMenu(self, sub_items, self.gestures, ges)
    return sub_items
end

function Gestures:genSubItem(ges, separator, hold_callback)
    local reader_only = {tap_top_left_corner=true, hold_top_left_corner=true,
                         tap_top_right_corner=true,}
    local enabled_func
    if reader_only[ges] then
       enabled_func = function() return self.ges_mode == "gesture_reader" end
    end
    return {
        text_func = function() return self:gestureTitleFunc(ges) end,
        enabled_func = enabled_func,
        sub_item_table = self:genMenu(ges),
        separator = separator,
        hold_callback = hold_callback,
    }
end

function Gestures:genSubItemTable(gestures)
    local sub_item_table = {}
    for _, item in ipairs(gestures) do
        table.insert(sub_item_table, self:genSubItem(item))
    end
    return sub_item_table
end

function Gestures:genMultiswipeMenu()
    local sub_item_table = {}
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
            doc = "Multiswipe in gesture creator"
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
        }
    }
    for item in FFIUtil.orderedPairs(self.custom_multiswipes) do
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

function Gestures:addIntervals(menu_items)
    menu_items.gesture_intervals = {
        text = _("Gesture intervals"),
        sub_item_table = {
            {
                text = _("Text selection rate"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local current_value = G_reader_settings:readSetting("hold_pan_rate")
                    if not current_value then
                        current_value = Screen.low_pan_rate and 5.0 or 30.0
                    end
                    local items = SpinWidget:new{
                        title_text = _("Text selection rate"),
                        info_text = T(_([[
The rate is how often screen will be refreshed per second while selecting text.
Higher values mean faster screen updates, but also use more CPU.

Default value: %1]]), Screen.low_pan_rate and 5.0 or 30.0),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = current_value,
                        value_min = 1.0,
                        value_max = 60.0,
                        value_step = 1,
                        value_hold_step = 15,
                        ok_text = _("Set rate"),
                        default_value = Screen.low_pan_rate and 5.0 or 30.0,
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
                    local SpinWidget = require("ui/widget/spinwidget")
                    local GestureDetector = require("device/gesturedetector")
                    local items = SpinWidget:new{
                        title_text = _("Tap interval"),
                        info_text = T(_([[
Any other taps made within this interval after a first tap will be considered accidental and ignored.

The interval value is in milliseconds and can range from 0 (0 seconds) to 2000 (2 seconds).
Default value: %1]]), GestureDetector.TAP_INTERVAL/1000),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = GestureDetector:getInterval("ges_tap_interval")/1000,
                        value_min = 0,
                        value_max = 2000,
                        value_step = 50,
                        value_hold_step = 200,
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.TAP_INTERVAL/1000,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_tap_interval", spin.value*1000)
                            GestureDetector:setNewInterval("ges_tap_interval", spin.value*1000)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Tap interval on keyboard"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items = SpinWidget:new{
                        title_text = _("Tap interval on keyboard"),
                        info_text = _([[
Any other taps made within this interval after a first tap will be considered accidental and ignored.

The interval value is in milliseconds and can range from 0 (0 seconds) to 2000 (2 seconds).
Default value: 0]]),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = (G_reader_settings:readSetting("ges_tap_interval_on_keyboard") or 0)/1000,
                        value_min = 0,
                        value_max = 2000,
                        value_step = 50,
                        value_hold_step = 200,
                        ok_text = _("Set interval"),
                        default_value = 0,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_tap_interval_on_keyboard", spin.value*1000)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Double tap interval"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local GestureDetector = require("device/gesturedetector")
                    local items = SpinWidget:new{
                        title_text = _("Double tap interval"),
                        info_text = T(_([[
When double tap is enabled, this sets the time to wait for the second tap. A single tap will take at least this long to be detected.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).
Default value: %1]]), GestureDetector.DOUBLE_TAP_INTERVAL/1000),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = GestureDetector:getInterval("ges_double_tap_interval")/1000,
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.DOUBLE_TAP_INTERVAL/1000,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_double_tap_interval", spin.value*1000)
                            GestureDetector:setNewInterval("ges_double_tap_interval", spin.value*1000)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Two finger tap duration"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local GestureDetector = require("device/gesturedetector")
                    local items = SpinWidget:new{
                        title_text = _("Two finger tap duration"),
                        info_text = T(_([[
This sets the allowed duration of any of the two fingers touch/release for the combined event to be considered a two finger tap.

The duration value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).
Default value: %1]]), GestureDetector.TWO_FINGER_TAP_DURATION/1000),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = GestureDetector:getInterval("ges_two_finger_tap_duration")/1000,
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        ok_text = _("Set duration"),
                        default_value = GestureDetector.TWO_FINGER_TAP_DURATION/1000,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_two_finger_tap_duration", spin.value*1000)
                            GestureDetector:setNewInterval("ges_two_finger_tap_duration", spin.value*1000)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Hold interval"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local GestureDetector = require("device/gesturedetector")
                    local items = SpinWidget:new{
                        title_text = _("Hold interval"),
                        info_text = T(_([[
If a touch is not released in this interval, it is considered a hold (or long-press). On document's text, single word selection is then triggered.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).
Default value: %1]]), GestureDetector.HOLD_INTERVAL/1000),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = GestureDetector:getInterval("ges_hold_interval")/1000,
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.HOLD_INTERVAL/1000,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_hold_interval", spin.value*1000)
                            GestureDetector:setNewInterval("ges_hold_interval", spin.value*1000)
                        end
                    }
                    UIManager:show(items)
                end,
            },
            {
                text = _("Swipe interval"),
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local GestureDetector = require("device/gesturedetector")
                    local items = SpinWidget:new{
                        title_text = _("Swipe interval"),
                        info_text = T(_([[
This sets the maximum delay between the start and the end of a swipe for it to be considered a swipe. Above this interval, it's considered panning.

The interval value is in milliseconds and can range from 100 (0.1 seconds) to 2000 (2 seconds).
Default value: %1]]), GestureDetector.SWIPE_INTERVAL/1000),
                        width = math.floor(Screen:getWidth() * 0.75),
                        value = GestureDetector:getInterval("ges_swipe_interval")/1000,
                        value_min = 100,
                        value_max = 2000,
                        value_step = 100,
                        value_hold_step = 500,
                        ok_text = _("Set interval"),
                        default_value = GestureDetector.SWIPE_INTERVAL/1000,
                        callback = function(spin)
                            G_reader_settings:saveSetting("ges_swipe_interval", spin.value*1000)
                            GestureDetector:setNewInterval("ges_swipe_interval", spin.value*1000)
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
                text = _("Multiswipes"),
                sub_item_table = self:genMultiswipeMenu(),
                enabled_func = function() return self.multiswipes_enabled end,
            },
            {
                text = _("Custom multiswipes"),
                sub_item_table = self:genCustomMultiswipeSubmenu(),
                enabled_func = function() return self.multiswipes_enabled end,
                separator = true,
            },
            {
                text = _("Tap corner"),
                sub_item_table = self:genSubItemTable({"tap_top_left_corner", "tap_top_right_corner", "tap_left_bottom_corner", "tap_right_bottom_corner"}),
            },
            {
                text = _("Hold corner"),
                sub_item_table = self:genSubItemTable({"hold_top_left_corner", "hold_top_right_corner", "hold_bottom_left_corner", "hold_bottom_right_corner"}),
            },
            {
                text = _("One-finger swipe"),
                sub_item_table = self:genSubItemTable({"short_diagonal_swipe", "one_finger_swipe_left_edge_down", "one_finger_swipe_left_edge_up", "one_finger_swipe_right_edge_down", "one_finger_swipe_right_edge_up", "one_finger_swipe_top_edge_right", "one_finger_swipe_top_edge_left", "one_finger_swipe_bottom_edge_right", "one_finger_swipe_bottom_edge_left"}),
            },
            {
                text = _("Double tap"),
                enabled_func = function()
                    return self.ges_mode == "gesture_reader" and self.ui.disable_double_tap ~= true
                end,
                sub_item_table = self:genSubItemTable({"double_tap_left_side", "double_tap_right_side", "double_tap_top_left_corner", "double_tap_top_right_corner", "double_tap_bottom_left_corner", "double_tap_bottom_right_corner"}),
            },
        },
    }

    if Device:hasMultitouch() then
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = _("Two-finger tap corner"),
            sub_item_table = self:genSubItemTable({"two_finger_tap_top_left_corner", "two_finger_tap_top_right_corner", "two_finger_tap_bottom_left_corner", "two_finger_tap_bottom_right_corner"}),
        })
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = _("Two-finger swipe"),
            sub_item_table = self:genSubItemTable({"two_finger_swipe_east", "two_finger_swipe_west", "two_finger_swipe_south", "two_finger_swipe_north", "two_finger_swipe_northeast", "two_finger_swipe_northwest", "two_finger_swipe_southeast", "two_finger_swipe_southwest"}),
        })
        table.insert(menu_items.gesture_manager.sub_item_table, {
            text = _("Spread and pinch"),
            sub_item_table = self:genSubItemTable({"spread_gesture", "pinch_gesture"}),
        })
    end

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

    local zone_left_edge = {
        ratio_x = 0, ratio_y = 0,
        ratio_w = 1/8, ratio_h = 1,
    }
    local zone_right_edge = {
        ratio_x = 7/8, ratio_y = 0,
        ratio_w = 1/8, ratio_h = 1,
    }
    local zone_top_edge = {
        ratio_x = 0, ratio_y = 0,
        ratio_w = 1, ratio_h = 1/8,
    }
    local zone_bottom_edge = {
        ratio_x = 0, ratio_y = 7/8,
        ratio_w = 1, ratio_h = 1/8,
    }

    -- legacy global variable DTAP_ZONE_FLIPPING may still be defined in default.persistent.lua
    local dtap_zone_top_left = DTAP_ZONE_FLIPPING and DTAP_ZONE_FLIPPING or DTAP_ZONE_TOP_LEFT
    local zone_top_left_corner = {
        ratio_x = dtap_zone_top_left.x,
        ratio_y = dtap_zone_top_left.y,
        ratio_w = dtap_zone_top_left.w,
        ratio_h = dtap_zone_top_left.h,
    }
    -- legacy global variable DTAP_ZONE_BOOKMARK may still be defined in default.persistent.lua
    local dtap_zone_top_right = DTAP_ZONE_BOOKMARK and DTAP_ZONE_BOOKMARK or DTAP_ZONE_TOP_RIGHT
    local zone_top_right_corner = {
        ratio_x = dtap_zone_top_right.x,
        ratio_y = dtap_zone_top_right.y,
        ratio_w = dtap_zone_top_right.w,
        ratio_h = dtap_zone_top_right.h,
    }
    local zone_bottom_left_corner = {
        ratio_x = DTAP_ZONE_BOTTOM_LEFT.x,
        ratio_y = DTAP_ZONE_BOTTOM_LEFT.y,
        ratio_w = DTAP_ZONE_BOTTOM_LEFT.w,
        ratio_h = DTAP_ZONE_BOTTOM_LEFT.h,
    }
    local zone_bottom_right_corner = {
        ratio_x = DTAP_ZONE_BOTTOM_RIGHT.x,
        ratio_y = DTAP_ZONE_BOTTOM_RIGHT.y,
        ratio_w = DTAP_ZONE_BOTTOM_RIGHT.w,
        ratio_h = DTAP_ZONE_BOTTOM_RIGHT.h,
    }
    -- NOTE: The defaults are effectively mapped to DTAP_ZONE_BACKWARD & DTAP_ZONE_FORWARD
    local zone_left = {
        ratio_x = DDOUBLE_TAP_ZONE_PREV_CHAPTER.x,
        ratio_y = DDOUBLE_TAP_ZONE_PREV_CHAPTER.y,
        ratio_w = DDOUBLE_TAP_ZONE_PREV_CHAPTER.w,
        ratio_h = DDOUBLE_TAP_ZONE_PREV_CHAPTER.h,
    }
    local zone_right = {
        ratio_x = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.x,
        ratio_y = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.y,
        ratio_w = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.w,
        ratio_h = DDOUBLE_TAP_ZONE_NEXT_CHAPTER.h,
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
        Dispatcher:execute(action_list, ges)
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

function Gestures:onIgnoreHoldCorners(ignore_hold_corners)
    if ignore_hold_corners == nil then
        G_reader_settings:flipNilOrFalse("ignore_hold_corners")
    else
        G_reader_settings:saveSetting("ignore_hold_corners", ignore_hold_corners)
    end
    self.ignore_hold_corners = G_reader_settings:isTrue("ignore_hold_corners")
    return true
end

function Gestures:onFlushSettings()
    if self.settings_data and self.updated then
        self.settings_data:flush()
        self.updated = false
    end
end

return Gestures
