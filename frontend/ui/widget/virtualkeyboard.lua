local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local HorizontalSpan = require("ui/widget/horizontalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local Device = require("ui/device")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")

local VirtualKey = InputContainer:new{
    key = nil,
    icon = nil,
    label = nil,

    keyboard = nil,
    callback = nil,

    width = nil,
    height = nil,
    bordersize = 2,
    face = Font:getFace("infont", 22),
}

function VirtualKey:init()
    if self.label == "Sym" or self.label == "ABC" then
        self.callback = function () self.keyboard:setLayout(self.key or self.label) end
    elseif self.label == "Shift" then
        self.callback = function () self.keyboard:setLayout(self.key or self.label) end
    elseif self.label == "IM" then
        self.callback = function () self.keyboard:setLayout(self.key or self.label) end
    elseif self.label == "Backspace" then
        self.callback = function () self.keyboard:delChar() end
    else
        self.callback = function () self.keyboard:addChar(self.key) end
    end

    local label_widget = nil
    if self.icon then
        label_widget = ImageWidget:new{
            file = self.icon,
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
        background = 0,
        radius = 5,
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
        }
    end
end

function VirtualKey:onTapSelect()
    self[1].invert = true
    if self.callback then
        self.callback()
    end
    UIManager:scheduleIn(0.02, function() self:invert(false) end)
    return true
end

function VirtualKey:invert(invert)
    self[1].invert = invert
    UIManager:setDirty(self.keyboard, "partial")
end

local VirtualKeyboard = InputContainer:new{
    is_always_active = true,
    disable_double_tap = true,
    inputbox = nil,
    KEYS = {}, -- table to store layouts
    min_layout = 2,
    max_layout = 9,
    layout = 2,
    shiftmode = false,
    symbolmode = false,
    utf8mode = false,

    width = 600,
    height = 256,
    bordersize = 2,
    padding = 2,
    key_padding = Screen:scaleByDPI(6),
}

function VirtualKeyboard:init()
    self.KEYS = {
        -- first row
        {
            { "Q",        "q",    "1",    "!",    "Я",    "я",    "1",    "!", },
            { "W",        "w",    "2",    "?",    "Ж",    "ж",    "2",    "?", },
            { "E",        "e",    "3",    "|",    "Е",    "е",    "3",    "«", },
            { "R",        "r",    "4",    "#",    "Р",    "р",    "4",    "»", },
            { "T",        "t",    "5",    "@",    "Т",    "т",    "5",    ":", },
            { "Y",        "y",    "6",    "‰",    "Ы",    "ы",    "6",    ";", },
            { "U",        "u",    "7",    "'",    "У",    "у",    "7",    "~", },
            { "I",        "i",    "8",    "`",    "И",    "и",    "8",    "(", },
            { "O",        "o",    "9",    ":",    "О",    "о",    "9",    ")", },
            { "P",        "p",    "0",    ";",    "П",    "п",    "0",    "=", },
        },
        -- second raw
        {
            { "A",        "a",    "+",    "…",    "А",    "а",    "Ш",    "ш", },
            { "S",        "s",    "-",    "_",    "С",    "с",    "Ѕ",    "ѕ", },
            { "D",        "d",    "*",    "=",    "Д",    "д",    "Э",    "э", },
            { "F",        "f",    "/",    "\\",    "Ф",    "ф",    "Ю",    "ю", },
            { "G",        "g",    "%",    "„",    "Г",    "г",    "Ґ",    "ґ", },
            { "H",        "h",    "^",    "“",    "Ч",    "ч",    "Ј",    "ј", },
            { "J",        "j",    "<",    "”",    "Й",    "й",    "І",    "і", },
            { "K",        "k",    "=",    "\"",    "К",    "к",    "Ќ",    "ќ", },
            { "L",        "l",    ">",    "~",    "Л",    "л",    "Љ",    "љ", },
        },
        -- third raw
        {
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { "Z",        "z",    "(",    "$",    "З",    "з",    "Щ",    "щ", },
            { "X",        "x",    ")",    "€",    "Х",    "х",    "№",    "@", },
            { "C",        "c",    "&",    "¥",    "Ц",    "ц",    "Џ",    "џ", },
            { "V",        "v",    ":",    "£",    "В",    "в",    "Ў",    "ў", },
            { "B",        "b",    "π",    "‚",    "Б",    "б",    "Ћ",    "ћ", },
            { "N",        "n",    "е",    "‘",    "Н",    "н",    "Њ",    "њ", },
            { "M",        "m",    "~",    "’",    "М",    "м",    "Ї",    "ї", },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth raw
        {
            { "Sym",    "Sym",    "ABC",    "ABC",    "Sym",    "Sym",    "ABC",    "ABC",
              width = 1.5},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { label = "space",
              " ",        " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 5.0},
            { ",",        ".",    ".",    ",",    ",",    ".",    "Є",    "є", },
            { label = "Enter",
              "\n",        "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },

        }
    }
    self:initLayout(self.layout)
end

function VirtualKeyboard:initLayout(layout)
    local function VKLayout(b1, b2, b3)
        local function boolnum(bool)
            return bool and 1 or 0
        end
        return 2 - boolnum(b1) + 2 * boolnum(b2) + 4 * boolnum(b3)
    end

    if layout then
        -- to be sure layout is selected properly
        layout = math.max(layout, self.min_layout)
        layout = math.min(layout, self.max_layout)
        self.layout = layout
        -- fill the layout modes
        layout = layout % 4
        self.shiftmode  = (layout == 1 or layout == 3)
        self.symbolmode = (layout == 3 or layout == 4)
        self.utf8mode   = (self.layout > 5)
    else -- or, without input parameter, restore layout from current layout modes
        self.layout = VKLayout(self.shiftmode, self.symbolmode, self.utf8mode)
    end
    self:addKeys()
end

function VirtualKeyboard:addKeys()
    local base_key_width = math.floor((self.width - 11*self.key_padding - 2*self.padding)/10)
    local base_key_height = math.floor((self.height - 5*self.key_padding - 2*self.padding)/4)
    local h_key_padding = HorizontalSpan:new{width = self.key_padding}
    local v_key_padding = VerticalSpan:new{width = self.key_padding}
    local vertical_group = VerticalGroup:new{}
    for i = 1, #self.KEYS do
        local horizontal_group = HorizontalGroup:new{}
        for j = 1, #self.KEYS[i] do
            local width_factor = self.KEYS[i][j].width or 1.0
            local key_width = math.floor((base_key_width + self.key_padding) * width_factor)
                            - self.key_padding
            local key_height = base_key_height
            local label = self.KEYS[i][j].label or self.KEYS[i][j][self.layout]
            local key = VirtualKey:new{
                key = self.KEYS[i][j][self.layout],
                icon = self.KEYS[i][j].icon,
                label = label,
                keyboard = self,
                width = key_width,
                height = key_height,
            }
            table.insert(horizontal_group, key)
            if j ~= #self.KEYS[i] then
                table.insert(horizontal_group, h_key_padding)
            end
        end
        table.insert(vertical_group, horizontal_group)
        if i ~= #self.KEYS then
            table.insert(vertical_group, v_key_padding)
        end
    end

    local size = vertical_group:getSize()
    local keyboard_frame = FrameContainer:new{
        margin = 0,
        bordersize = self.bordersize,
        background = 0,
        radius = 0,
        padding = self.padding,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width - 2*self.bordersize -2*self.padding,
                h = self.height - 2*self.bordersize -2*self.padding,
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
    elseif key == "IM" then
        self.utf8mode = not self.utf8mode
    end
    self:initLayout()
    UIManager:setDirty(self, "partial")
end

function VirtualKeyboard:addChar(key)
    DEBUG("add char", key)
    self.inputbox:addChar(key)
    UIManager:setDirty(self, "partial")
    UIManager:setDirty(self.inputbox, "partial")
end

function VirtualKeyboard:delChar()
    DEBUG("delete char")
    self.inputbox:delChar()
    UIManager:setDirty(self, "partial")
    UIManager:setDirty(self.inputbox, "partial")
end

return VirtualKeyboard
