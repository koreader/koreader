--[[--
A button table to be used in dialogs and widgets.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local dbg = require("dbg")
local Screen = Device.screen

local RadioButtonTable = FocusManager:extend{
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
    face = Font:getFace("cfont", 22),
    _first_button = nil,
    checked_button = nil,
    button_select_callback = nil,
}

function RadioButtonTable:init()
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
        local sizer_space = (self.sep_width + 2 * self.padding) * (column_cnt - 1)
        for j = 1, column_cnt do
            local btn_entry = row[j]
            local button = CheckButton:new{
                text = btn_entry.text,
                checkable = btn_entry.checkable,
                checked = btn_entry.checked,
                enabled = btn_entry.enabled,
                radio = true,
                provider = btn_entry.provider,

                bold = btn_entry.bold,
                fgcolor = btn_entry.fgcolor,
                bgcolor = btn_entry.bgcolor,

                width = (self.width - sizer_space) / column_cnt,
                bordersize = 0,
                margin = 0,
                padding = 0,
                face = self.face,

                show_parent = self.show_parent or self,
                parent = self.parent or self,
            }
            local button_callback = function()
                self:_checkButton(button)
                if self.button_select_callback then
                    self.button_select_callback(btn_entry)
                end
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
                background = Blitbuffer.COLOR_DARK_GRAY,
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
        self._first_button:toggleCheck()
        self.checked_button = self._first_button
    end

    if Device:hasDPad() or Device:hasKeyboard() then
        self.layout = self.radio_buttons_layout
        self:refocusWidget()
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
            background = black_line and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
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

function RadioButtonTable:_checkButton(button)
    -- nothing to do
    if button.checked then return end

    self.checked_button:toggleCheck()
    button:toggleCheck()
    self.checked_button = button
end

return RadioButtonTable
