local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
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

    keyboard = nil,
    callback = nil,
    -- This is to inhibit the key's own refresh (useful to avoid conflicts on Layout changing keys)
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
        self.callback = function () self.keyboard:setLayout("Sym") end
        self.skiptap = true
    elseif self.keyboard.shiftmode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayout("Shift") end
        self.skiptap = true
    elseif self.keyboard.utf8mode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayout("IM") end
        self.skiptap = true
    elseif self.keyboard.umlautmode_keys[self.label] ~= nil then
        self.callback = function () self.keyboard:setLayout("Äéß") end
        self.skiptap = true
    elseif self.label == "Backspace" then
        self.callback = function () self.keyboard:delChar() end
        self.hold_callback = function () self.keyboard:delToStartOfLine() end
        --self.skiphold = true
    elseif self.label =="←" then
        self.callback = function() self.keyboard:leftChar() end
    elseif self.label == "→" then
        self.callback = function() self.keyboard:rightChar() end
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
            self.keyboard:addChar(self.key_chars[ges.direction])
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
            width = icon_height * 100, -- to fit height when ensuring a/r
        }
    else
        label_widget = TextWidget:new{
            text = self.label,
            face = self.face,
        }
    end
    self[1] = FrameContainer:new{
        margin = 0,
        bordersize = self.bordersize,
        background = Blitbuffer.COLOR_WHITE,
        radius = 0,
        padding = 0,
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
    self.flash_keyboard = G_reader_settings:readSetting("flash_keyboard") ~= false
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
    if self.keyboard.ignore_first_hold_release then
        self.keyboard.ignore_first_hold_release = false
        return true
    end
    self:onTapSelect()
end

function VirtualKey:onPanReleaseKey()
    if self.keyboard.ignore_first_hold_release then
        self.keyboard.ignore_first_hold_release = false
        return true
    end
    self:onTapSelect()
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

    local rows = {
        extra_key_chars = {
            key_chars[2],
            key_chars[3],
            key_chars[4],
        },
        top_key_chars = {
            key_chars.northwest,
            key_chars.north,
            key_chars.northeast,
        },
        middle_key_chars = {
            key_chars.west,
            key_char_orig,
            key_chars.east,
        },
        bottom_key_chars = {
            key_chars.southwest,
            key_chars.south,
            key_chars.southeast,
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

    local vertical_group = VerticalGroup:new{}
    local horizontal_group_extra = HorizontalGroup:new{}
    local horizontal_group_top = HorizontalGroup:new{}
    local horizontal_group_middle = HorizontalGroup:new{}
    local horizontal_group_bottom = HorizontalGroup:new{}

    local function horizontalRow(chars, group)
        local layout_horizontal = {}

        for i = 1,3 do
            local v = chars[i]

            if v then
                columns[i] = true
                blank[i].width = blank[2].width
                if i == 1 then
                    h_key_padding[i].width = h_key_padding[2].width
                end

                local virtual_key = VirtualKey:new{
                    key = v,
                    label = v,
                    keyboard = parent_key.keyboard,
                    key_chars = key_chars,
                    width = parent_key.width,
                    height = parent_key.height,
                }
                -- don't open another popup on hold
                virtual_key.hold_callback = nil
                -- close popup on hold release
                virtual_key.onHoldReleaseKey = function()
                    virtual_key:onTapSelect(true)
                    UIManager:close(self)
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
    elseif position_container.dimen.x + keyboard_frame.dimen.w > Screen:getWidth() then
        position_container.dimen.x = Screen:getWidth() - keyboard_frame.dimen.w
    end
    if position_container.dimen.y < 0 then
        position_container.dimen.y = 0
    elseif position_container.dimen.y + keyboard_frame.dimen.h > Screen:getHeight() then
        position_container.dimen.y = Screen:getHeight() - keyboard_frame.dimen.h
    end

    self[1] = position_container

    UIManager:show(self)

    UIManager:setDirty(self, function()
        return "ui", keyboard_frame.dimen
    end)
end

local VirtualKeyboard = FocusManager:new{
    modal = true,
    disable_double_tap = true,
    inputbox = nil,
    KEYS = {}, -- table to store layouts
    shiftmode_keys = {},
    symbolmode_keys = {},
    utf8mode_keys = {},
    umlautmode_keys = {},
    min_layout = 2,
    max_layout = 12,
    keyboard_layout = 2,
    shiftmode = false,
    symbolmode = false,
    utf8mode = false,
    umlautmode = false,
    layout = {},

    width = Screen:scaleBySize(600),
    height = nil,
    bordersize = Size.border.default,
    padding = Size.padding.small,
    key_padding = Size.padding.default,
}

local lang_to_keyboard_layout = {
    el = "el_keyboard",
    en = "en_keyboard",
    es = "es_keyboard",
    fr = "fr_keyboard",
    ja = "ja_keyboard",
    pl = "pl_keyboard",
    pt_BR = "pt_keyboard",
}

function VirtualKeyboard:init()
    local lang = G_reader_settings:readSetting("language")
    local keyboard_layout = lang_to_keyboard_layout[lang] or lang_to_keyboard_layout["en"]
    local keyboard = require("ui/data/keyboardlayouts/" .. keyboard_layout)
    self.KEYS = keyboard.keys
    self.shiftmode_keys = keyboard.shiftmode_keys
    self.symbolmode_keys = keyboard.symbolmode_keys
    self.utf8mode_keys = keyboard.utf8mode_keys
    self.umlautmode_keys = keyboard.umlautmode_keys
    self.height = Screen:scaleBySize(64 * #self.KEYS)
    self:initLayout(self.keyboard_layout)
    if Device:hasDPad() then
        self.key_events.PressKey = { {"Press"}, doc = "select key" }
    end
    if Device:hasKeys() then
        self.key_events.Close = { {"Back"}, doc = "close keyboard" }
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

function VirtualKeyboard:_refresh(want_flash)
    local refresh_type = "ui"
    if want_flash then
        refresh_type = "flashui"
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
    return true
end

function VirtualKeyboard:initLayout(layout)
    local function VKLayout(b1, b2, b3, b4)
        local function boolnum(bool)
            return bool and 1 or 0
        end
        return 2 - boolnum(b1) + 2 * boolnum(b2) + 4 * boolnum(b3) + 8 * boolnum(b4)
    end

    if layout then
        -- to be sure layout is selected properly
        layout = math.max(layout, self.min_layout)
        layout = math.min(layout, self.max_layout)
        self.keyboard_layout = layout
        -- fill the layout modes
        self.shiftmode  = (layout == 1 or layout == 3 or layout == 5 or layout == 7 or layout == 9 or layout == 11)
        self.symbolmode = (layout == 3 or layout == 4 or layout == 7 or layout == 8 or layout == 11 or layout == 12)
        self.utf8mode   = (layout == 5 or layout == 6 or layout == 7 or layout == 8)
        self.umlautmode = (layout == 9 or layout == 10 or layout == 11 or layout == 12)
    else -- or, without input parameter, restore layout from current layout modes
        self.keyboard_layout = VKLayout(self.shiftmode, self.symbolmode, self.utf8mode, self.umlautmode)
    end
    self:addKeys()
end

function VirtualKeyboard:addKeys()
    self.layout = {}
    local base_key_width = math.floor((self.width - (#self.KEYS[1] + 1)*self.key_padding - 2*self.padding)/#self.KEYS[1])
    local base_key_height = math.floor((self.height - (#self.KEYS + 1)*self.key_padding - 2*self.padding)/#self.KEYS)
    local h_key_padding = HorizontalSpan:new{width = self.key_padding}
    local v_key_padding = VerticalSpan:new{width = self.key_padding}
    local vertical_group = VerticalGroup:new{}
    for i = 1, #self.KEYS do
        local horizontal_group = HorizontalGroup:new{}
        local layout_horizontal = {}
        for j = 1, #self.KEYS[i] do
            local key
            local key_chars = self.KEYS[i][j][self.keyboard_layout]
            if type(key_chars) == "table" then
                key = key_chars[1]
            else
                key = key_chars
                key_chars = nil
            end
            local width_factor = self.KEYS[i][j].width or 1.0
            local key_width = math.floor((base_key_width + self.key_padding) * width_factor)
                            - self.key_padding
            local key_height = base_key_height
            local label = self.KEYS[i][j].label or key
            local virtual_key = VirtualKey:new{
                key = key,
                key_chars = key_chars,
                icon = self.KEYS[i][j].icon,
                label = label,
                keyboard = self,
                width = key_width,
                height = key_height,
            }
            if not key_chars then
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

function VirtualKeyboard:setLayout(key)
    if key == "Shift" then
        self.shiftmode = not self.shiftmode
    elseif key == "Sym" or key == "ABC" then
        self.symbolmode = not self.symbolmode
    elseif key == "Äéß" then
        self.umlautmode = not self.umlautmode
        if self.umlautmode then self.utf8mode = false end
    elseif key == "IM" then
        self.utf8mode = not self.utf8mode
        if self.utf8mode then self.umlautmode = false end
    end
    self:initLayout()
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
