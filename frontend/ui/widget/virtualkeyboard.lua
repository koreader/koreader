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
    elseif self.label == "Äéß" then
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
    max_layout = 12,
    layout = 2,
    shiftmode = false,
    symbolmode = false,
    utf8mode = false,
    umlautmode = false,

    width = 600,
    height = 256,
    bordersize = 2,
    padding = 2,
    key_padding = Screen:scaleByDPI(6),
}

function VirtualKeyboard:init()
    self.KEYS = {
        -- first row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { "Q",        "q",    "1",    "!",    "Я",    "я",    "1",    "!",    "Ä",    "ä",    "1",    "ª", },
            { "W",        "w",    "2",    "?",    "Ж",    "ж",    "2",    "?",    "Ö",    "ö",    "2",    "º", },
            { "E",        "e",    "3",    "|",    "Е",    "е",    "3",    "«",    "Ü",    "ü",    "3",    "¡", },
            { "R",        "r",    "4",    "#",    "Р",    "р",    "4",    "»",    "ß",    "ß",    "4",    "¿", },
            { "T",        "t",    "5",    "@",    "Т",    "т",    "5",    ":",    "À",    "à",    "5",    "¼", },
            { "Y",        "y",    "6",    "‰",    "Ы",    "ы",    "6",    ";",    "Â",    "â",    "6",    "½", },
            { "U",        "u",    "7",    "'",    "У",    "у",    "7",    "~",    "Æ",    "æ",    "7",    "¾", },
            { "I",        "i",    "8",    "`",    "И",    "и",    "8",    "(",    "Ç",    "ç",    "8",    "©", },
            { "O",        "o",    "9",    ":",    "О",    "о",    "9",    ")",    "È",    "è",    "9",    "®", },
            { "P",        "p",    "0",    ";",    "П",    "п",    "0",    "=",    "É",    "é",    "0",    "™", },
        },
        -- second raw
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { "A",        "a",    "+",    "…",    "А",    "а",    "Ш",    "ш",    "Ê",    "ê",    "Ş",    "ş", },
            { "S",        "s",    "-",    "_",    "С",    "с",    "Ѕ",    "ѕ",    "Ë",    "ë",    "İ",    "ı", },
            { "D",        "d",    "*",    "=",    "Д",    "д",    "Э",    "э",    "Î",    "î",    "Ğ",    "ğ", },
            { "F",        "f",    "/",    "\\",   "Ф",    "ф",    "Ю",    "ю",    "Ï",    "ï",    "Ć",    "ć", },
            { "G",        "g",    "%",    "„",    "Г",    "г",    "Ґ",    "ґ",    "Ô",    "ô",    "Č",    "č", },
            { "H",        "h",    "^",    "“",    "Ч",    "ч",    "Ј",    "ј",    "Œ",    "œ",    "Đ",    "đ", },
            { "J",        "j",    "<",    "”",    "Й",    "й",    "І",    "і",    "Ù",    "ù",    "Š",    "š", },
            { "K",        "k",    "=",    "\"",   "К",    "к",    "Ќ",    "ќ",    "Û",    "û",    "Ž",    "ž", },
            { "L",        "l",    ">",    "~",    "Л",    "л",    "Љ",    "љ",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third raw
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { "Z",        "z",    "(",    "$",    "З",    "з",    "Щ",    "щ",    "Á",    "á",    "Ű",    "ű", },
            { "X",        "x",    ")",    "€",    "Х",    "х",    "№",    "@",    "É",    "é",    "Ø",    "ø", },
            { "C",        "c",    "{",    "¥",    "Ц",    "ц",    "Џ",    "џ",    "Í",    "í",    "Þ",    "þ", },
            { "V",        "v",    "}",    "£",    "В",    "в",    "Ў",    "ў",    "Ñ",    "ñ",    "Ý",    "ý", },
            { "B",        "b",    "[",    "‚",    "Б",    "б",    "Ћ",    "ћ",    "Ó",    "ó",    "†",    "‡", },
            { "N",        "n",    "]",    "‘",    "Н",    "н",    "Њ",    "њ",    "Ú",    "ú",    "–",    "—", },
            { "M",        "m",    "&",    "’",    "М",    "м",    "Ї",    "ї",    "Ç",    "ç",    "…",    "¨", },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth raw
        {
            { "Sym",    "Sym",    "ABC",    "ABC",    "Sym",    "Sym",    "ABC",    "ABC",    "Sym",    "Sym",    "ABC",    "ABC",
              width = 1.5},
            { label = "IM",
              icon = "resources/icons/appbar.globe.wire.png",
            },
            { "Äéß",        "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß",    "Äéß", },
            { label = "space",
              " ",        " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 4.0},
            { ",",        ".",    ".",    ",",    ",",    ".",    "Є",    "є",    ",",    ".",    ",",    ".", },
            { label = "Enter",
              "\n",        "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",    "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },

        }
    }
    self:initLayout(self.layout)
    if GLOBAL_INPUT_VALUE then
        for i = 1, string.len(GLOBAL_INPUT_VALUE) do
            self:addChar(string.sub(GLOBAL_INPUT_VALUE,i,i))
        end
    end    
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
        self.layout = layout
        -- fill the layout modes
        self.shiftmode  = (layout == 1 or layout == 3 or layout == 5 or layout == 7 or layout == 9 or layout == 11)
        self.symbolmode = (layout == 3 or layout == 4 or layout == 7 or layout == 8 or layout == 11 or layout == 12)
        self.utf8mode   = (layout == 5 or layout == 6 or layout == 7 or layout == 8)
        self.umlautmode = (layout == 9 or layout == 10 or layout == 11 or layout == 12)
    else -- or, without input parameter, restore layout from current layout modes
        self.layout = VKLayout(self.shiftmode, self.symbolmode, self.utf8mode, self.umlautmode)
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
    elseif key == "Äéß" then
        self.umlautmode = not self.umlautmode
        if self.umlautmode then self.utf8mode = false end
    elseif key == "IM" then
        self.utf8mode = not self.utf8mode
        if self.utf8mode then self.umlautmode = false end
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
