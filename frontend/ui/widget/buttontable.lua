local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local FocusManager = require("ui/widget/focusmanager")
local LineWidget = require("ui/widget/linewidget")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = Device.screen

local ButtonTable = FocusManager:new{
    width = Screen:getWidth(),
    buttons = {
        {
            {text="OK", enabled=true, callback=nil},
            {text="Cancel", enabled=false, callback=nil},
        },
    },
    sep_width = Screen:scaleBySize(1),
    padding = Screen:scaleBySize(2),

    zero_sep = false,
    button_font_face = "cfont",
    button_font_size = 20,
}

function ButtonTable:init()
    self.container = VerticalGroup:new{ width = self.width }
    table.insert(self, self.container)
    if self.zero_sep then
        self:addHorizontalSep()
    end
    for i = 1, #self.buttons do
        local horizontal_group = HorizontalGroup:new{}
        local line = self.buttons[i]
        local sizer_space = self.sep_width * (#line - 1) + 2
        for j = 1, #line do
            local button = Button:new{
                text = line[j].text,
                enabled = line[j].enabled,
                callback = line[j].callback,
                width = (self.width - sizer_space)/#line,
                bordersize = 0,
                margin = 0,
                padding = 0,
                text_font_face = self.button_font_face,
                text_font_size = self.button_font_size,
                show_parent = self.show_parent,
            }
            local button_dim = button:getSize()
            local vertical_sep = LineWidget:new{
                background = Blitbuffer.gray(0.5),
                dimen = Geom:new{
                    w = self.sep_width,
                    h = button_dim.h,
                }
            }
            self.buttons[i][j] = button
            table.insert(horizontal_group, button)
            if j < #line then
                table.insert(horizontal_group, vertical_sep)
            end
        end -- end for each button
        table.insert(self.container, horizontal_group)
        if i < #self.buttons then
            self:addHorizontalSep()
        end
    end -- end for each button line
    if Device:hasDPad() then
        self.layout = self.buttons
        self.layout[1][1]:onFocus()
        self.key_events.SelectByKeyPress = { {{"Press", "Enter"}} }
    else
        self.key_events = {}  -- deregister all key press event listeners
    end
end

function ButtonTable:addHorizontalSep()
    table.insert(self.container,
                 VerticalSpan:new{ width = Screen:scaleBySize(2) })
    table.insert(self.container, LineWidget:new{
        background = Blitbuffer.gray(0.5),
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        }
    })
    table.insert(self.container,
                 VerticalSpan:new{ width = Screen:scaleBySize(2) })
end

function ButtonTable:onSelectByKeyPress()
    self:getFocusItem().callback()
end

return ButtonTable
