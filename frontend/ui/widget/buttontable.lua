local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local LineWidget = require("ui/widget/linewidget")
local Button = require("ui/widget/button")
local Screen = require("ui/screen")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")

local ButtonTable = VerticalGroup:new{
    width = Screen:getWidth(),
    buttons = {
        {
            {text="OK", enabled=true, callback=nil},
            {text="Cancel", enabled=false, callback=nil},
        },
    },
    sep_width = Screen:scaleByDPI(1),
    padding = Screen:scaleByDPI(2),

    zero_sep = false,
    button_font_face = "cfont",
    button_font_size = 20,
}

function ButtonTable:init()
    --local vertical_group = VerticalGroup:new{}
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
            table.insert(horizontal_group, button)
            if j < #line then
                table.insert(horizontal_group, vertical_sep)
            end
        end -- end for each button
        table.insert(self, horizontal_group)
        if i < #self.buttons then
            self:addHorizontalSep()
        end
    end -- end for each button line
end

function ButtonTable:addHorizontalSep()
    table.insert(self, VerticalSpan:new{ width = Screen:scaleByDPI(2) })
    table.insert(self, LineWidget:new{
        background = Blitbuffer.gray(0.5),
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        }
    })
    table.insert(self, VerticalSpan:new{ width = Screen:scaleByDPI(2) })
end

return ButtonTable
