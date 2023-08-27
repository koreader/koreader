local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local util = require("util")
local Screen = Device.screen

local PhysicalNumericKey = WidgetContainer:extend{
    key = nil,
    label = nil,
    physical_key_label = nil,

    keyboard = nil,
    callback = nil,
    mapping = nil,

    width = nil,
    height = nil,
    bordersize = Size.border.button,
    face = Font:getFace("infont"),
    pkey_face = Font:getFace("infont", 14),
}

function PhysicalNumericKey:init()
    local label_widget = TextWidget:new{
        text = self.label,
        face = self.face,
    }
    self[1] = FrameContainer:new{
        margin = 0,
        bordersize = self.bordersize,
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.default,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{
                w = self.width - 2*self.bordersize,
                h = self.height - 2*self.bordersize,
            },
            VerticalGroup:new{
                label_widget,
                TextWidget:new{
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    text = self.physical_key_label,
                    face = self.pkey_face,
                },
            }
        },
    }
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.height,
    }
end

-- start of PhysicalKeyboard

local PhysicalKeyboard = InputContainer:extend{
    is_always_active = true,
    inputbox = nil,  -- expect ui/widget/inputtext instance
    bordersize = Size.border.button,
    padding = Size.padding.button,
    height = math.max(Screen:getWidth(), Screen:getHeight())*0.33,
    key_padding = Size.padding.default,
}

function PhysicalKeyboard:init()
    local all_keys = {}
    for _,row in ipairs(Device.keyboard_layout) do
        util.arrayAppend(all_keys, row)
    end
    self.key_events.KeyPress = { { all_keys } }

    self.dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }

    self:setType(self.inputbox.input_type)
end

function PhysicalKeyboard:setType(t)
    if t == "number" then
        self.mapping = {
            {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"}
        }
        self.key_transformer = {}
        for i,row in ipairs(self.mapping) do
            for j,key in ipairs(row) do
                local pkey = Device.keyboard_layout[i][j]
                self.key_transformer[pkey] = self.mapping[i][j]
            end
        end
        self:setupNumericMappingUI()
    else
        -- default mapping
        self.mapping = Device.keyboard_layout
    end
end

function PhysicalKeyboard:onKeyPress(ev)
    local key = ev.key
    if key == "Back" then
        logger.warn("TODO: exit keyboard")
    elseif key == "Del" then
        self.inputbox:delChar()
    else
        if self.key_transformer then
            key = self.key_transformer[key]
        end
        self.inputbox:addChars(key)
    end
end

function PhysicalKeyboard:setupNumericMappingUI()
    local key_rows = VerticalGroup:new{}
    local key_margin = Size.margin.tiny
    local row_len = #self.mapping[1]
    local base_key_width = math.floor((self.width - row_len*(self.key_padding+2*key_margin) - 2*self.padding)/10)
    local base_key_height = math.floor((self.height - self.key_padding - 2*self.padding)/4)
    local key_width = math.floor(base_key_width + self.key_padding)

    for i, kb_row in ipairs(self.mapping) do
        local row = HorizontalGroup:new{}
        for j, key in ipairs(kb_row) do
            if j > 1 then
                table.insert(row, HorizontalSpan:new{width=key_margin*2})
            end
            table.insert(row, PhysicalNumericKey:new{
                label = key,
                physical_key_label = Device.keyboard_layout[i][j],
                width = key_width,
                height = base_key_height,
            })
        end
        table.insert(key_rows, row)
    end

    local keyboard_frame = FrameContainer:new{
        margin = 0,
        bordersize = 0,
        radius = 0,
        padding = self.padding,
        TopContainer:new{
            dimen = Geom:new{
                w = self.width - 2*self.bordersize -2*self.padding,
                h = self.height - 2*self.bordersize -2*self.padding,
            },
            key_rows,
        }
    }

    self[1] = BottomContainer:new{
        dimen = Screen:getSize(),
        keyboard_frame,
    }

    self.dimen = keyboard_frame:getSize()
end

-- Match VirtualKeyboard's API to ease caller's life
function PhysicalKeyboard:lockVisibility() end
function PhysicalKeyboard:setVisibility() end
function PhysicalKeyboard:isVisible() return true end
function PhysicalKeyboard:showKeyboard() end
function PhysicalKeyboard:hideKeyboard() end

return PhysicalKeyboard
