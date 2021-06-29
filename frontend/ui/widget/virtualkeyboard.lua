local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KeyboardLayoutDialog = require("ui/widget/keyboardlayoutdialog")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TimeVal = require("ui/timeval")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local Screen = Device.screen

local VirtualKeyPopup

local VirtualKey = InputContainer:new{
    key = nil,
    icon = nil,
    label = nil,
    bold = nil,

    keyboard = nil,
    callback = nil,
    -- This is to inhibit the key's own refresh (useful to avoid conflicts on Layer changing keys)
    skiptap = nil,
    skiphold = nil,

    width = nil,
    height = math.max(Screen:getWidth(), Screen:getHeight())*0.33,
    bordersize = Size.border.thin,
    focused_bordersize = Size.border.default * 5,
    radius = 0,
    face = Font:getFace("infont"),
}

function VirtualKey:init()
    if self.keyboard.symbolmode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayer("Sym") end
        self.skiptap = true
    elseif self.keyboard.shiftmode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayer("Shift") end
        self.skiptap = true
    elseif self.keyboard.utf8mode_keys[self.label] ~= nil then
        self.key_chars = self:genkeyboardLayoutKeyChars()
        self.callback = function ()
            local current = G_reader_settings:readSetting("keyboard_layout")
            local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
            local enabled = false
            local next_layout = nil
            for k, v in FFIUtil.orderedPairs(keyboard_layouts) do
                if enabled and v == true then
                    next_layout = k
                    break
                end
                if k == current then
                    enabled = true
                end
            end
            if not next_layout then
                for k, v in FFIUtil.orderedPairs(keyboard_layouts) do
                    if enabled and v == true then
                        next_layout = k
                        break
                    end
                end
            end
            if next_layout then
                self.keyboard:setKeyboardLayout(next_layout)
            end
        end
        self.hold_callback = function()
            if util.tableSize(self.key_chars) > 3 then
                self.popup = VirtualKeyPopup:new{
                    parent_key = self,
                }
            else
                self.keyboard_layout_dialog = KeyboardLayoutDialog:new{
                    parent = self,
                }
                UIManager:show(self.keyboard_layout_dialog)
            end
        end
        self.swipe_callback = function(ges)
            local key_function = self.key_chars[ges.direction.."_func"]
            if key_function then
                key_function()
            end
        end
        self.skiptap = true
    elseif self.keyboard.umlautmode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayer("Äéß") end
        self.skiptap = true
    elseif self.label == "" then
        self.callback = function () self.keyboard:delChar() end
        self.hold_callback = function ()
            self.ignore_key_release = true -- don't have delChar called on release
            self.keyboard:delToStartOfLine()
        end
        --self.skiphold = true
    elseif self.label == "←" then
        self.callback = function() self.keyboard:leftChar() end
        self.hold_callback = function()
            self.ignore_key_release = true
            self.keyboard:goToStartOfLine()
        end
    elseif self.label == "→" then
        self.callback = function() self.keyboard:rightChar() end
        self.hold_callback = function()
            self.ignore_key_release = true
            self.keyboard:goToEndOfLine()
        end
    elseif self.label == "↑" then
        self.callback = function() self.keyboard:upLine() end
    elseif self.label == "↓" then
        self.callback = function() self.keyboard:downLine() end
    else
        self.callback = function () self.keyboard:addChar(self.key) end
        self.hold_callback = function()
            if not self.key_chars then return end

            VirtualKeyPopup:new{
                parent_key = self,
            }
        end
        self.swipe_callback = function(ges)
            local key_string = self.key_chars[ges.direction]
            local key_function = self.key_chars[ges.direction.."_func"]

            if not key_function and key_string then
                if type(key_string) == "table" and key_string.key then
                    key_string = key_string.key
                end
                self.keyboard:addChar(key_string)
            elseif key_function then
                key_function()
            end
        end
    end

    local label_widget
    if self.icon then
        -- Scale icon to fit other characters height
        -- (use *1.5 as our icons have a bit of white padding)
        local icon_height = math.ceil(self.face.size * 1.5)
        label_widget = ImageWidget:new{
            file = self.icon,
            scale_factor = 0, -- keep icon aspect ratio
            height = icon_height,
            width = self.width - 2*self.bordersize,
        }
    else
        label_widget = TextWidget:new{
            text = self.label,
            face = self.face,
            bold = self.bold or false,
        }
    end
    self[1] = FrameContainer:new{
        margin = 0,
        bordersize = self.bordersize,
        background = Blitbuffer.COLOR_WHITE,
        radius = 0,
        padding = 0,
        allow_mirroring = false,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width - 2*self.bordersize,
                h = self.height - 2*self.bordersize,
            },
            label_widget,
        },
    }
    self.dimen = Geom:new{
        w = self.width,
        h = self.height,
    }
    --self.dimen = self[1]:getSize()
    if Device:isTouchDevice() then
        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
            },
            HoldReleaseKey = {
                GestureRange:new{
                    ges = "hold_release",
                    range = self.dimen,
                },
            },
            PanReleaseKey = {
                GestureRange:new{
                    ges = "pan_release",
                    range = self.dimen,
                },
            },
            SwipeKey = {
                GestureRange:new{
                    ges = "swipe",
                    range = self.dimen,
                },
            },
        }
    end
    if (self.keyboard.shiftmode_keys[self.label] ~= nil  and self.keyboard.shiftmode) or
    (self.keyboard.umlautmode_keys[self.label] ~= nil and self.keyboard.umlautmode) then
        self[1].background = Blitbuffer.COLOR_LIGHT_GRAY
    end
    self.flash_keyboard = G_reader_settings:nilOrTrue("flash_keyboard")
end

function VirtualKey:genkeyboardLayoutKeyChars()
    local positions = {
        "northeast",
        "north",
        "northwest",
        "west",
    }
    local keyboard_layouts = G_reader_settings:readSetting("keyboard_layouts") or {}
    local key_chars = {
        { label = "🌐",
        },
        east = { label = "🌐", },
        east_func = function ()
            self.keyboard_layout_dialog = KeyboardLayoutDialog:new{
                parent = self,
            }
            UIManager:show(self.keyboard_layout_dialog)
        end,
    }
    local index = 1
    for k, v in FFIUtil.orderedPairs(keyboard_layouts) do
        if v == true then
            key_chars[positions[index]] = string.sub(k, 1, 2)
            key_chars[positions[index] .. "_func"] = function()
                UIManager:tickAfterNext(function() UIManager:close(self.popup) end)
                self.keyboard:setKeyboardLayout(k)
            end
            if index >= 4 then break end
            index = index + 1
        end
    end
    return key_chars
end

function VirtualKey:update_keyboard(want_flash, want_fast)
    -- NOTE: We mainly use "fast" when inverted & "ui" when not, with a cherry on top:
    --       we flash the *full* keyboard instead when we release a hold.
    if want_flash then
        UIManager:setDirty(self.keyboard, function()
            return "flashui", self.keyboard[1][1].dimen
        end)
    else
        local refresh_type = "ui"
        if want_fast then
            refresh_type = "fast"
        end
        -- Only repaint the key itself, not the full board...
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, function()
            logger.dbg("update key region", self[1].dimen)
            return refresh_type, self[1].dimen
        end)
    end
end

function VirtualKey:onFocus()
    self[1].inner_bordersize = self.focused_bordersize
end

function VirtualKey:onUnfocus()
    self[1].inner_bordersize = 0
end

function VirtualKey:onTapSelect(skip_flash)
    Device:performHapticFeedback("KEYBOARD_TAP")
    -- just in case it's not flipped to false on hold release where it's supposed to
    self.keyboard.ignore_first_hold_release = false
    if self.flash_keyboard and not skip_flash and not self.skiptap then
        self[1].inner_bordersize = self.focused_bordersize
        self:update_keyboard(false, true)
        if self.callback then
            self.callback()
        end
        UIManager:tickAfterNext(function() self:invert(false) end)
    else
        if self.callback then
            self.callback()
        end
    end
    return true
end

function VirtualKey:onHoldSelect()
    Device:performHapticFeedback("LONG_PRESS")
    if self.flash_keyboard and not self.skiphold then
        self[1].inner_bordersize = self.focused_bordersize
        self:update_keyboard(false, true)
        -- Don't refresh the key region if we're going to show a popup on top of it ;).
        if self.hold_callback then
            self[1].inner_bordersize = 0
            self.hold_callback()
        else
            UIManager:tickAfterNext(function() self:invert(false, true) end)
        end
    else
        if self.hold_callback then
            self.hold_callback()
        end
    end
    return true
end

function VirtualKey:onSwipeKey(arg, ges)
    Device:performHapticFeedback("KEYBOARD_TAP")
    if self.flash_keyboard and not self.skipswipe then
        self[1].inner_bordersize = self.focused_bordersize
        self:update_keyboard(false, true)
        if self.swipe_callback then
            self.swipe_callback(ges)
        end
        UIManager:tickAfterNext(function() self:invert(false, false) end)
    else
        if self.swipe_callback then
            self.swipe_callback(ges)
        end
    end
    return true
end

function VirtualKey:onHoldReleaseKey()
    if self.ignore_key_release then
        self.ignore_key_release = nil
        return true
    end
    Device:performHapticFeedback("LONG_PRESS")
    if self.keyboard.ignore_first_hold_release then
        self.keyboard.ignore_first_hold_release = false
        return true
    end
    self:onTapSelect()
    return true
end

function VirtualKey:onPanReleaseKey()
    if self.ignore_key_release then
        self.ignore_key_release = nil
        return true
    end
    Device:performHapticFeedback("LONG_PRESS")
    if self.keyboard.ignore_first_hold_release then
        self.keyboard.ignore_first_hold_release = false
        return true
    end
    self:onTapSelect()
    return true
end

function VirtualKey:invert(invert, hold)
    if invert then
        self[1].inner_bordersize = self.focused_bordersize
    else
        self[1].inner_bordersize = 0
    end
    self:update_keyboard(hold, false)
end

VirtualKeyPopup = FocusManager:new{
    modal = true,
    disable_double_tap = true,
    inputbox = nil,
    layout = {},
}

function VirtualKeyPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self[1][1].dimen) then
        UIManager:close(self)
        return true
    end
    return false
end

function VirtualKeyPopup:onClose()
    UIManager:close(self)
    return true
end

function VirtualKeyPopup:onCloseWidget()
    self:free()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
end

function VirtualKeyPopup:onPressKey()
    self:getFocusItem():handleEvent(Event:new("TapSelect"))
    return true
end

function VirtualKeyPopup:init()
    local parent_key = self.parent_key
    local key_chars = parent_key.key_chars
    local key_char_orig = key_chars[1]
    local key_char_orig_func = parent_key.callback

    local rows = {
        extra_key_chars = {
            key_chars[2],
            key_chars[3],
            key_chars[4],
            -- _func equivalent for unnamed extra keys
            key_chars[5],
            key_chars[6],
            key_chars[7],
        },
        top_key_chars = {
            key_chars.northwest,
            key_chars.north,
            key_chars.northeast,
            key_chars.northwest_func,
            key_chars.north_func,
            key_chars.northeast_func,
        },
        middle_key_chars = {
            key_chars.west,
            key_char_orig,
            key_chars.east,
            key_chars.west_func,
            key_char_orig_func,
            key_chars.east_func,
        },
        bottom_key_chars = {
            key_chars.southwest,
            key_chars.south,
            key_chars.southeast,
            key_chars.southwest_func,
            key_chars.south_func,
            key_chars.southeast_func,
        },
    }
    if util.tableSize(rows.extra_key_chars) == 0 then rows.extra_key_chars = nil end
    if util.tableSize(rows.top_key_chars) == 0 then rows.top_key_chars = nil end
    -- we should always have a middle
    if util.tableSize(rows.bottom_key_chars) == 0 then rows.bottom_key_chars = nil end

    -- to store if a column exists
    local columns = {}
    local blank = {
        HorizontalSpan:new{width = 0},
        HorizontalSpan:new{width = parent_key.width},
        HorizontalSpan:new{width = 0},
    }
    local h_key_padding = {
        HorizontalSpan:new{width = 0},
        HorizontalSpan:new{width = parent_key.keyboard.key_padding},
        HorizontalSpan:new{width = 0},
    }
    local v_key_padding = VerticalSpan:new{width = parent_key.keyboard.key_padding}

    local vertical_group = VerticalGroup:new{ allow_mirroring = false }
    local horizontal_group_extra = HorizontalGroup:new{ allow_mirroring = false }
    local horizontal_group_top = HorizontalGroup:new{ allow_mirroring = false }
    local horizontal_group_middle = HorizontalGroup:new{ allow_mirroring = false }
    local horizontal_group_bottom = HorizontalGroup:new{ allow_mirroring = false }

    local function horizontalRow(chars, group)
        local layout_horizontal = {}

        for i = 1,3 do
            local v = chars[i]
            local v_func = chars[i+3]

            if v then
                columns[i] = true
                blank[i].width = blank[2].width
                if i == 1 then
                    h_key_padding[i].width = h_key_padding[2].width
                end

                local key = type(v) == "table" and v.key or v
                local label = type(v) == "table" and v.label or key
                local icon = type(v) == "table" and v.icon
                local bold = type(v) == "table" and v.bold
                local virtual_key = VirtualKey:new{
                    key = key,
                    label = label,
                    icon = icon,
                    bold = bold,
                    keyboard = parent_key.keyboard,
                    key_chars = key_chars,
                    width = parent_key.width,
                    height = parent_key.height,
                }
                -- Support any function as a callback.
                if v_func then
                    virtual_key.callback = v_func
                end
                -- don't open another popup on hold
                virtual_key.hold_callback = nil
                -- close popup on hold release
                virtual_key.onHoldReleaseKey = function()
                    -- NOTE: Check our *parent* key!
                    if parent_key.ignore_key_release then
                        parent_key.ignore_key_release = nil
                        return true
                    end
                    Device:performHapticFeedback("LONG_PRESS")
                    if virtual_key.keyboard.ignore_first_hold_release then
                        virtual_key.keyboard.ignore_first_hold_release = false
                        return true
                    end

                    virtual_key:onTapSelect(true)
                    UIManager:close(self)
                    return true
                end
                virtual_key.onPanReleaseKey = virtual_key.onHoldReleaseKey

                if v == key_char_orig then
                    virtual_key[1].background = Blitbuffer.COLOR_LIGHT_GRAY

                    -- restore ability to hold/pan release on central key after opening popup
                    virtual_key._keyOrigHoldPanHandler = function()
                        virtual_key.onHoldReleaseKey = virtual_key._onHoldReleaseKey
                        virtual_key.onPanReleaseKey = virtual_key._onPanReleaseKey
                    end
                    virtual_key._onHoldReleaseKey = virtual_key.onHoldReleaseKey
                    virtual_key.onHoldReleaseKey = virtual_key._keyOrigHoldPanHandler
                    virtual_key._onPanReleaseKey = virtual_key.onPanReleaseKey
                    virtual_key.onPanReleaseKey = virtual_key._keyOrigHoldPanHandler
                end

                table.insert(group, virtual_key)
                table.insert(layout_horizontal, virtual_key)
            else
                table.insert(group, blank[i])
            end
            table.insert(group, h_key_padding[i])
        end
        table.insert(vertical_group, group)
        table.insert(self.layout, layout_horizontal)
    end
    if rows.extra_key_chars then
        horizontalRow(rows.extra_key_chars, horizontal_group_extra)
        table.insert(vertical_group, v_key_padding)
    end
    if rows.top_key_chars then
        horizontalRow(rows.top_key_chars, horizontal_group_top)
        table.insert(vertical_group, v_key_padding)
    end
    -- always middle row
    horizontalRow(rows.middle_key_chars, horizontal_group_middle)
    if rows.bottom_key_chars then
        table.insert(vertical_group, v_key_padding)
        horizontalRow(rows.bottom_key_chars, horizontal_group_bottom)
    end

    if not columns[3] then
        h_key_padding[2].width = 0
    end

    local num_rows = util.tableSize(rows)
    local num_columns = util.tableSize(columns)

    local keyboard_frame = FrameContainer:new{
        margin = 0,
        bordersize = Size.border.default,
        background = Blitbuffer.COLOR_WHITE,
        radius = 0,
        padding = parent_key.keyboard.padding,
        allow_mirroring = false,
        CenterContainer:new{
            dimen = Geom:new{
                w = parent_key.width*num_columns + 2*Size.border.default + (num_columns)*parent_key.keyboard.key_padding,
                h = parent_key.height*num_rows + 2*Size.border.default + num_rows*parent_key.keyboard.key_padding,
            },
            vertical_group,
        }
    }
    keyboard_frame.dimen = keyboard_frame:getSize()

    self.ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
            }
        },
    }
    self.tap_interval_override = G_reader_settings:readSetting("ges_tap_interval_on_keyboard") or 0
    self.tap_interval_override = TimeVal:new{ usec = self.tap_interval_override }

    if Device:hasDPad() then
        self.key_events.PressKey = { {"Press"}, doc = "select key" }
    end
    if Device:hasKeys() then
        self.key_events.Close = { {"Back"}, doc = "close keyboard" }
    end

    local offset_x = 2*parent_key.keyboard.padding + 2*parent_key.keyboard.bordersize
    if columns[1] then
        offset_x = offset_x + parent_key.width + parent_key.keyboard.padding + 2*parent_key.keyboard.bordersize
    end

    local offset_y = parent_key.keyboard.padding + parent_key.keyboard.padding + 2*parent_key.keyboard.bordersize
    if rows.extra_key_chars then
        offset_y = offset_y + parent_key.height + parent_key.keyboard.padding + 2*parent_key.keyboard.bordersize
    end
    if rows.top_key_chars then
        offset_y = offset_y + parent_key.height + parent_key.keyboard.padding + 2*parent_key.keyboard.bordersize
    end

    local position_container = WidgetContainer:new{
        dimen = {
            x = parent_key.dimen.x - offset_x,
            y = parent_key.dimen.y - offset_y,
            h = Screen:getSize().h,
            w = Screen:getSize().w,
        },
        keyboard_frame,
    }
    if position_container.dimen.x < 0 then
        position_container.dimen.x = 0
        -- We effectively move the popup, which means the key underneath our finger may no longer *exactly* be parent_key.
        -- Make sure we won't close the popup right away, as that would risk being a *different* key, in order to make that less confusing.
        parent_key.ignore_key_release = true
    elseif position_container.dimen.x + keyboard_frame.dimen.w > Screen:getWidth() then
        position_container.dimen.x = Screen:getWidth() - keyboard_frame.dimen.w
        parent_key.ignore_key_release = true
    end
    if position_container.dimen.y < 0 then
        position_container.dimen.y = 0
        parent_key.ignore_key_release = true
    elseif position_container.dimen.y + keyboard_frame.dimen.h > Screen:getHeight() then
        position_container.dimen.y = Screen:getHeight() - keyboard_frame.dimen.h
        parent_key.ignore_key_release = true
    end

    self[1] = position_container

    UIManager:show(self)

    UIManager:setDirty(self, function()
        return "ui", keyboard_frame.dimen
    end)
end

local VirtualKeyboard = FocusManager:new{
    name = "VirtualKeyboard",
    modal = true,
    disable_double_tap = true,
    inputbox = nil,
    KEYS = {}, -- table to store layouts
    shiftmode_keys = {},
    symbolmode_keys = {},
    utf8mode_keys = {},
    umlautmode_keys = {},
    keyboard_layer = 2,
    shiftmode = false,
    symbolmode = false,
    umlautmode = false,
    layout = {},

    width = Screen:scaleBySize(600),
    height = nil,
    bordersize = Size.border.default,
    padding = Size.padding.small,
    key_padding = Size.padding.default,

    lang_to_keyboard_layout = {
        ar_AA = "ar_AA_keyboard",
        bg_BG = "bg_keyboard",
        de = "de_keyboard",
        el = "el_keyboard",
        en = "en_keyboard",
        es = "es_keyboard",
        fa = "fa_keyboard",
        fr = "fr_keyboard",
        he = "he_keyboard",
        ja = "ja_keyboard",
        ka = "ka_keyboard",
        pl = "pl_keyboard",
        pt_BR = "pt_keyboard",
        ro = "ro_keyboard",
        ko_KR = "ko_KR_keyboard",
        ru = "ru_keyboard",
        tr = "tr_keyboard",
    },
}

function VirtualKeyboard:init()
    if self.uwrap_func then
        self.uwrap_func()
        self.uwrap_func = nil
    end
    local lang = self:getKeyboardLayout()
    local keyboard_layout = self.lang_to_keyboard_layout[lang] or self.lang_to_keyboard_layout["en"]
    local keyboard = require("ui/data/keyboardlayouts/" .. keyboard_layout)
    self.KEYS = keyboard.keys
    self.shiftmode_keys = keyboard.shiftmode_keys
    self.symbolmode_keys = keyboard.symbolmode_keys
    self.utf8mode_keys = keyboard.utf8mode_keys
    self.umlautmode_keys = keyboard.umlautmode_keys
    self.height = Screen:scaleBySize(64 * #self.KEYS)
    self.min_layer = keyboard.min_layer
    self.max_layer = keyboard.max_layer
    self:initLayer(self.keyboard_layer)
    self.tap_interval_override = G_reader_settings:readSetting("ges_tap_interval_on_keyboard") or 0
    self.tap_interval_override = TimeVal:new{ usec = self.tap_interval_override }
    if Device:hasDPad() then
        self.key_events.PressKey = { {"Press"}, doc = "select key" }
    end
    if Device:hasKeys() then
        self.key_events.Close = { {"Back"}, doc = "close keyboard" }
    end
    if keyboard.wrapInputBox then
        self.uwrap_func = keyboard.wrapInputBox(self.inputbox) or self.uwrap_func
    end
end

function VirtualKeyboard:getKeyboardLayout()
    return G_reader_settings:readSetting("keyboard_layout") or G_reader_settings:readSetting("language")
end

function VirtualKeyboard:setKeyboardLayout(layout)
    local prev_keyboard_height = self.dimen and self.dimen.h
    G_reader_settings:saveSetting("keyboard_layout", layout)
    self:init()
    if prev_keyboard_height and self.dimen.h ~= prev_keyboard_height then
        self:_refresh(true, true)
        -- Keyboard height change: notify parent (InputDialog)
        if self.inputbox and self.inputbox.parent and self.inputbox.parent.onKeyboardHeightChanged then
            self.inputbox.parent:onKeyboardHeightChanged()
        end
    else
        self:_refresh(true)
    end
end

function VirtualKeyboard:onClose()
    UIManager:close(self)
    return true
end

function VirtualKeyboard:onPressKey()
    self:getFocusItem():handleEvent(Event:new("TapSelect"))
    return true
end

function VirtualKeyboard:_refresh(want_flash, fullscreen)
    local refresh_type = "ui"
    if want_flash then
        refresh_type = "flashui"
    end
    if fullscreen then
        UIManager:setDirty("all", refresh_type)
        return
    end
    UIManager:setDirty(self, function()
        return refresh_type, self[1][1].dimen
    end)
end

function VirtualKeyboard:onShow()
    self:_refresh(true)
    return true
end

function VirtualKeyboard:onCloseWidget()
    self:_refresh(false)
end

function VirtualKeyboard:initLayer(layer)
    local function VKLayer(b1, b2, b3)
        local function boolnum(bool)
            return bool and 1 or 0
        end
        return 2 - boolnum(b1) + 2 * boolnum(b2) + 4 * boolnum(b3)
    end

    if layer then
        -- to be sure layer is selected properly
        layer = math.max(layer, self.min_layer)
        layer = math.min(layer, self.max_layer)
        self.keyboard_layer = layer
        -- fill the layer modes
        self.shiftmode  = (layer == 1 or layer == 3 or layer == 5 or layer == 7 or layer == 9 or layer == 11)
        self.symbolmode = (layer == 3 or layer == 4 or layer == 7 or layer == 8 or layer == 11 or layer == 12)
        self.umlautmode   = (layer == 5 or layer == 6 or layer == 7 or layer == 8)
    else -- or, without input parameter, restore layer from current layer modes
        self.keyboard_layer = VKLayer(self.shiftmode, self.symbolmode, self.umlautmode)
    end
    self:addKeys()
end

function VirtualKeyboard:addKeys()
    self:free() -- free previous keys' TextWidgets
    self.layout = {}
    local base_key_width = math.floor((self.width - (#self.KEYS[1] + 1)*self.key_padding - 2*self.padding)/#self.KEYS[1])
    local base_key_height = math.floor((self.height - (#self.KEYS + 1)*self.key_padding - 2*self.padding)/#self.KEYS)
    local h_key_padding = HorizontalSpan:new{width = self.key_padding}
    local v_key_padding = VerticalSpan:new{width = self.key_padding}
    local vertical_group = VerticalGroup:new{ allow_mirroring = false }
    for i = 1, #self.KEYS do
        local horizontal_group = HorizontalGroup:new{ allow_mirroring = false }
        local layout_horizontal = {}
        for j = 1, #self.KEYS[i] do
            local key
            local key_chars = self.KEYS[i][j][self.keyboard_layer]
            local label
            if type(key_chars) == "table" then
                key = key_chars[1]
                label = key_chars.label
            else
                key = key_chars
                key_chars = nil
            end
            local width_factor = self.KEYS[i][j].width or 1.0
            local key_width = math.floor((base_key_width + self.key_padding) * width_factor)
                            - self.key_padding
            local key_height = base_key_height
            label = label or self.KEYS[i][j].label or key
            local virtual_key = VirtualKey:new{
                key = key,
                key_chars = key_chars,
                icon = self.KEYS[i][j].icon,
                label = label,
                bold = self.KEYS[i][j].bold,
                keyboard = self,
                width = key_width,
                height = key_height,
            }
            if not virtual_key.key_chars then
                virtual_key.swipe_callback = nil
            end
            table.insert(horizontal_group, virtual_key)
            table.insert(layout_horizontal, virtual_key)
            if j ~= #self.KEYS[i] then
                table.insert(horizontal_group, h_key_padding)
            end
        end
        table.insert(vertical_group, horizontal_group)
        table.insert(self.layout, layout_horizontal)
        if i ~= #self.KEYS then
            table.insert(vertical_group, v_key_padding)
        end
    end

    local keyboard_frame = FrameContainer:new{
        margin = 0,
        bordersize = Size.border.default,
        background = Blitbuffer.COLOR_WHITE,
        radius = 0,
        padding = self.padding,
        allow_mirroring = false,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width - 2*Size.border.default - 2*self.padding,
                h = self.height - 2*Size.border.default - 2*self.padding,
            },
            vertical_group,
        }
    }
    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        keyboard_frame,
    }
    self.dimen = keyboard_frame:getSize()
end

function VirtualKeyboard:setLayer(key)
    if key == "Shift" then
        self.shiftmode = not self.shiftmode
    elseif key == "Sym" or key == "ABC" then
        self.symbolmode = not self.symbolmode
    elseif key == "Äéß" then
        self.umlautmode = not self.umlautmode
    end
    self:initLayer()
    self:_refresh(true)
end

function VirtualKeyboard:addChar(key)
    logger.dbg("add char", key)
    self.inputbox:addChars(key)
end

function VirtualKeyboard:delChar()
    logger.dbg("delete char")
    self.inputbox:delChar()
end

function VirtualKeyboard:delToStartOfLine()
    logger.dbg("delete to start of line")
    self.inputbox:delToStartOfLine()
end

function VirtualKeyboard:leftChar()
    self.inputbox:leftChar()
end

function VirtualKeyboard:rightChar()
    self.inputbox:rightChar()
end

function VirtualKeyboard:goToStartOfLine()
    self.inputbox:goToStartOfLine()
end

function VirtualKeyboard:goToEndOfLine()
    self.inputbox:goToEndOfLine()
end

function VirtualKeyboard:upLine()
    self.inputbox:upLine()
end

function VirtualKeyboard:downLine()
    self.inputbox:downLine()
end

function VirtualKeyboard:clear()
    logger.dbg("clear input")
    self.inputbox:clear()
end

return VirtualKeyboard
