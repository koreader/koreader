local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
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
    sep_width = Size.line.medium,
    padding = Size.padding.default,

    zero_sep = false,
    button_font_face = "cfont",
    button_font_size = 20,
}

function ButtonTable:init()
    self.selected = { x = 1, y = 1 }
    self.buttons_layout = {}
    self.button_by_id = {}
    self.container = VerticalGroup:new{ width = self.width }
    table.insert(self, self.container)
    if self.zero_sep then
        -- If we're asked to add a first line, don't add a vspan before: caller
        -- must do its own padding before.
        -- Things look better when the first line is gray like the others.
        self:addHorizontalSep(false, true, true)
    else
        self:addHorizontalSep(false, false, true)
    end
    local row_cnt = #self.buttons
    for i = 1, row_cnt do
        local buttons_layout_line = {}
        local horizontal_group = HorizontalGroup:new{}
        local row = self.buttons[i]
        local column_cnt = #row
        local sizer_space = self.sep_width * (column_cnt - 1) + 2
        for j = 1, column_cnt do
            local btn_entry = row[j]
            local button = Button:new{
                text = btn_entry.text,
                text_func = btn_entry.text_func,
                enabled = btn_entry.enabled,
                callback = btn_entry.callback,
                hold_callback = btn_entry.hold_callback,
                vsync = btn_entry.vsync,
                width = math.ceil((self.width - sizer_space)/column_cnt),
                max_width = math.ceil((self.width - sizer_space)/column_cnt - 2*self.sep_width - 2*self.padding),
                bordersize = 0,
                margin = 0,
                padding = Size.padding.buttontable, -- a bit taller than standalone buttons, for easier tap
                padding_h = 0, -- allow text to take more of the horizontal space
                text_font_face = self.button_font_face,
                text_font_size = self.button_font_size,
                show_parent = self.show_parent,
            }
            if btn_entry.id then
                self.button_by_id[btn_entry.id] = button
            end
            local button_dim = button:getSize()
            local vertical_sep = LineWidget:new{
                background = Blitbuffer.COLOR_GRAY,
                dimen = Geom:new{
                    w = self.sep_width,
                    h = button_dim.h,
                }
            }
            buttons_layout_line[j] = button
            table.insert(horizontal_group, button)
            if j < column_cnt then
                table.insert(horizontal_group, vertical_sep)
            end
        end -- end for each button
        table.insert(self.container, horizontal_group)
        if i < row_cnt then
            self:addHorizontalSep(true, true, true)
        end
        if column_cnt > 0 then
            -- Only add lines that are not separator to the focusmanager
            table.insert(self.buttons_layout, buttons_layout_line)
        end
    end -- end for each button line
    self:addHorizontalSep(true, false, false)
    if Device:hasDPad() then
        self.layout = self.buttons_layout
        self.layout[1][1]:onFocus()
        self.key_events.SelectByKeyPress = { {{"Press"}} }
    else
        self.key_events = {}  -- deregister all key press event listeners
    end
end

function ButtonTable:addHorizontalSep(vspan_before, add_line, vspan_after, black_line)
    if vspan_before then
        table.insert(self.container,
                     VerticalSpan:new{ width = Size.span.vertical_default })
    end
    if add_line then
        table.insert(self.container, LineWidget:new{
            background = black_line and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY,
            dimen = Geom:new{
                w = self.width,
                h = self.sep_width,
            }
        })
    end
    if vspan_after then
        table.insert(self.container,
                     VerticalSpan:new{ width = Size.span.vertical_default })
    end
end

function ButtonTable:onSelectByKeyPress()
    local item = self:getFocusItem()
    if item.enabled then
        item.callback()
    end
end

function ButtonTable:getButtonById(id)
    return self.button_by_id[id] -- nil if not found
end

return ButtonTable
