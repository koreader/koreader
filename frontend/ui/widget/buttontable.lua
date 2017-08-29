local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget = require("ui/widget/linewidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Geom = require("ui/geometry")
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
    self.buttons_layout = {}
    self.container = VerticalGroup:new{ width = self.width }
    table.insert(self, self.container)
    if self.zero_sep then
        self:addHorizontalSep()
    end
    local row_cnt = #self.buttons
    for i = 1, row_cnt do
        self.buttons_layout[i] = {}
        local horizontal_group = HorizontalGroup:new{}
        local row = self.buttons[i]
        local column_cnt = #row
        local sizer_space = self.sep_width * (column_cnt - 1) + 2
        for j = 1, column_cnt do
            local btn_entry = row[j]
            local button = Button:new{
                text = btn_entry.text,
                enabled = btn_entry.enabled,
                callback = btn_entry.callback,
                width = (self.width - sizer_space)/column_cnt,
                max_width = (self.width - sizer_space)/column_cnt - 2*self.sep_width - 2*self.padding,
                bordersize = 0,
                margin = 0,
                padding = 0,
                text_font_face = self.button_font_face,
                text_font_size = self.button_font_size,
                show_parent = self.show_parent,
            }
            local button_dim = button:getSize()
            local vertical_sep = LineWidget:new{
                background = Blitbuffer.COLOR_GREY,
                dimen = Geom:new{
                    w = self.sep_width,
                    h = button_dim.h,
                }
            }
            self.buttons_layout[i][j] = button
            table.insert(horizontal_group, button)
            if j < column_cnt then
                table.insert(horizontal_group, vertical_sep)
            end
        end -- end for each button
        table.insert(self.container, horizontal_group)
        if i < row_cnt then
            self:addHorizontalSep()
        end
    end -- end for each button line
    if Device:hasDPad() or Device:hasKeyboard() then
        self.layout = self.buttons_layout
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
        background = Blitbuffer.COLOR_GREY,
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
