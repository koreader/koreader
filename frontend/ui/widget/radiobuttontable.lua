local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget = require("ui/widget/linewidget")
local RadioButton = require("ui/widget/radiobutton")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local dbg = require("dbg")
local Screen = Device.screen

local RadioButtonTable = FocusManager:new{
    width = Screen:getWidth(),
    radio_buttons = {
        {
            {text="Cancel", enabled=false, callback=nil},
            {text="OK", enabled=true, callback=nil},
        },
    },
    sep_width = Size.line.medium,
    padding = Size.padding.button,

    zero_sep = false,
    button_font_face = "cfont",
    button_font_size = 20,

    _first_button = nil,
    checked_button = nil,
}

function RadioButtonTable:init()
    self.selected = { x = 1, y = 1 }
    self.radio_buttons_layout = {}
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

    local row_cnt = #self.radio_buttons

    for i = 1, row_cnt do
        self.radio_buttons_layout[i] = {}
        local horizontal_group = HorizontalGroup:new{}
        local row = self.radio_buttons[i]
        local column_cnt = #row
        local sizer_space = self.sep_width * (column_cnt - 1) + 2
        for j = 1, column_cnt do
            local btn_entry = row[j]
            local button = RadioButton:new{
                text = btn_entry.text,
                enabled = btn_entry.enabled,
                checked = btn_entry.checked,
                provider = btn_entry.provider,

                width = (self.width - sizer_space)/column_cnt,
                max_width = (self.width - sizer_space)/column_cnt - 2*self.sep_width - 2*self.padding,
                bordersize = 0,
                margin = 0,
                padding = 0,
                text_font_face = self.button_font_face,
                text_font_size = self.button_font_size,

                show_parent = self.show_parent or self,
                parent = self.parent or self,
            }
            local button_callback = function()
                self:_checkButton(button)
            end
            button.callback = button_callback

            if i == 1 and j == 1 then
                self._first_button = button
            end

            if button.checked and not self.checked_button then
                self.checked_button = button
            elseif dbg.is_on and
                       button.checked and self.checked_button then
                error("RadioButtonGroup: multiple checked RadioButtons")
            end

            local button_dim = button:getSize()
            local vertical_sep = LineWidget:new{
                background = Blitbuffer.COLOR_GREY,
                dimen = Geom:new{
                    w = self.sep_width,
                    h = button_dim.h,
                }
            }
            self.radio_buttons_layout[i][j] = button
            table.insert(horizontal_group, button)
            if j < column_cnt then
                table.insert(horizontal_group, vertical_sep)
            end
        end -- end for each button
        table.insert(self.container, horizontal_group)
        --if i < row_cnt then
            --self:addHorizontalSep(true, true, true)
        --end
    end -- end for each button line
    self:addHorizontalSep(true, false, false)

    -- check first entry unless otherwise specified
    if not self.checked_button then
        self._first_button:check()
        self.checked_button = self._first_button
    end

    if Device:hasDPad() or Device:hasKeyboard() then
        self.layout = self.radio_buttons_layout
        self.layout[1][1]:onFocus()
        self.key_events.SelectByKeyPress = { {{"Press", "Enter"}} }
    else
        self.key_events = {}  -- deregister all key press event listeners
    end
end

function RadioButtonTable:addHorizontalSep(vspan_before, add_line, vspan_after, black_line)
    if vspan_before then
        table.insert(self.container,
                     VerticalSpan:new{ width = Size.span.vertical_default })
    end
    if add_line then
        table.insert(self.container, LineWidget:new{
            background = black_line and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GREY,
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

function RadioButtonTable:onSelectByKeyPress()
    self:getFocusItem().callback()
end

function RadioButtonTable:_checkButton(button)
    -- nothing to do
    if button.checked then return end

    self.checked_button:unCheck()
    button:check()
    self.checked_button = button
end

return RadioButtonTable
