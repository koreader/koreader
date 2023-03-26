local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local ButtonProgressWidget = FocusManager:extend{
    width = Screen:scaleBySize(216),
    height = Size.item.height_default,
    padding = Size.padding.small,
    font_face = "cfont",
    font_size = 16,
    enabled = true,
    num_buttons = 2,
    position = 1,
    default_position = nil,
    thin_grey_style = false, -- default to black
    fine_tune = false, -- no -/+ buttons on the extremities by default
    more_options = false, -- no "⋮" button
}

function ButtonProgressWidget:init()
    self.current_button_index = self.position

    self.buttonprogress_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_DARK_GRAY,
        radius = Size.radius.window,
        bordersize = 0,
        padding = self.padding,
        dim = not self.enabled,
    }


    self.buttonprogress_content = HorizontalGroup:new{}
    self.horizontal_span_width = 0
    if self.fine_tune or self.more_options then
        self.horizontal_span = HorizontalSpan:new{
            width = Size.margin.fine_tune
        }
        self.horizontal_span_width = self.horizontal_span.width
    end
    self:update()
    if self.fine_tune then
        self.current_button_index = self.current_button_index + 1
    end
    self.buttonprogress_frame[1] = self.buttonprogress_content
    self[1] = self.buttonprogress_frame
    self.dimen = Geom:new(self.buttonprogress_frame:getSize())
end

function ButtonProgressWidget:update()
    self.layout = {{}}

    self.buttonprogress_content:clear()
    local button_margin = Size.margin.tiny
    local button_padding = Size.padding.button
    local button_bordersize = self.thin_grey_style and Size.border.thin or Size.border.button
    local buttons_count = self.num_buttons
    local span_count = 0
    if self.fine_tune then
        buttons_count = buttons_count + 2
        span_count = 2
    end
    if self.more_options then
        buttons_count = buttons_count + 1
        span_count = span_count + 1
    end
    local button_width_real = (self.width - span_count * self.horizontal_span_width) / buttons_count
    local button_width = math.floor(button_width_real)
    local button_width_adjust = button_width_real - button_width
    local button_width_to_add = 0

    -- Minus button on the left
    if self.fine_tune then
        button_width_to_add = button_width_to_add + button_width_adjust
        local button = Button:new{
            text = "−",
            radius = 0,
            margin = button_margin,
            padding = button_padding,
            bordersize = button_bordersize,
            enabled = true,
            width = button_width,
            preselect = false,
            text_font_face = self.font_face,
            text_font_size = self.font_size,
            callback = function()
                self.callback("-")
                self:update()
            end,
            hold_callback = self.hold_callback and function() self.hold_callback("-") end,
        }
        if self.thin_grey_style then
            button.frame.color = Blitbuffer.COLOR_DARK_GRAY
        end
        table.insert(self.buttonprogress_content, button)
        table.insert(self.layout[1], button)
        table.insert(self.buttonprogress_content, self.horizontal_span)
    end

    -- Actual progress bar
    for i = 1, self.num_buttons do
        button_width_to_add = button_width_to_add + button_width_adjust
        local real_button_width = button_width
        if button_width_to_add >= 1 then
            -- One pixel wider to better align the entire widget
            real_button_width = button_width + math.floor(button_width_to_add)
            button_width_to_add = button_width_to_add - math.floor(button_width_to_add)
        end
        local highlighted = i <= self.position
        local is_default = i == self.default_position
        local margin = button_margin
        if self.thin_grey_style and highlighted then
            margin = 0 -- moved outside button so it's not inverted
            real_button_width = real_button_width - 2*button_margin
        end
        local extra_border_size = 0
        if not self.thin_grey_style and is_default then
            -- make the border a bit bigger on the default button
            extra_border_size = Size.border.thin
        end
        local button = Button:new{
            text = "",
            radius = 0,
            margin = margin,
            padding = button_padding,
            bordersize = button_bordersize + extra_border_size,
            enabled = true,
            width = real_button_width,
            preselect = highlighted,
            text_font_face = self.font_face,
            text_font_size = self.font_size,
            callback = function()
                self.callback(i)
                self.position = i
                self:update()
            end,
            no_focus = highlighted,
            hold_callback = self.hold_callback and function() self.hold_callback(i) end,
        }
        if self.thin_grey_style then
            if is_default then
                -- use a black border as a discreet visual hint
                button.frame.color = Blitbuffer.COLOR_BLACK
            else
                -- otherwise, gray border, same as the filled
                -- button, so looking as if no border
                button.frame.color = Blitbuffer.COLOR_DARK_GRAY
            end
            if highlighted then
                -- The button and its frame background will be inverted,
                -- so invert the color we want so it gets inverted back
                button.frame.background = Blitbuffer.COLOR_DARK_GRAY:invert()
                button = FrameContainer:new{ -- add margin back
                    margin = button_margin,
                    padding = 0,
                    bordersize = 0,
                    focusable = true,
                    focus_border_size = Size.border.thin,
                    button,
                }
            end
        end
        table.insert(self.buttonprogress_content, button)
        table.insert(self.layout[1], button)
    end

    -- Plus button on the right
    if self.fine_tune then
        button_width_to_add = button_width_to_add + button_width_adjust
        local real_button_width = button_width
        if button_width_to_add >= 1 then
            -- One pixel wider to better align the entire widget
            real_button_width = button_width + math.floor(button_width_to_add)
            button_width_to_add = button_width_to_add - math.floor(button_width_to_add)
        end
        local button = Button:new{
            text = "＋",
            radius = 0,
            margin = button_margin,
            padding = button_padding,
            bordersize = button_bordersize,
            enabled = true,
            width = real_button_width,
            preselect = false,
            text_font_face = self.font_face,
            text_font_size = self.font_size,
            callback = function()
                self.callback("+")
                self:update()
            end,
            hold_callback = self.hold_callback and function() self.hold_callback("+") end,
        }

        if self.thin_grey_style then
            button.frame.color = Blitbuffer.COLOR_DARK_GRAY
        end
        table.insert(self.buttonprogress_content, self.horizontal_span)
        table.insert(self.buttonprogress_content, button)
        table.insert(self.layout[1], button)
    end
    -- More option button on the right
    if self.more_options then
        button_width_to_add = button_width_to_add + button_width_adjust
        local real_button_width = button_width
        if button_width_to_add >= 1 then
            -- One pixel wider to better align the entire widget
            real_button_width = button_width + math.floor(button_width_to_add)
        end
        local button = Button:new{
            text = "⋮",
            radius = 0,
            margin = button_margin,
            padding = button_padding,
            bordersize = button_bordersize,
            enabled = true,
            width = real_button_width,
            preselect = false,
            text_font_face = self.font_face,
            text_font_size = self.font_size,
            callback = function()
                self.callback("⋮")
                self:update()
            end,
            hold_callback = self.hold_callback and function() self.hold_callback("⋮") end,
        }
        if self.thin_grey_style then
            button.frame.color = Blitbuffer.COLOR_DARK_GRAY
        end
        table.insert(self.buttonprogress_content, self.horizontal_span)
        table.insert(self.buttonprogress_content, button)
        table.insert(self.layout[1], button)
    end

    self:refocusWidget()
    UIManager:setDirty(self.show_parent, function()
        return "ui", self.dimen
    end)
end

function ButtonProgressWidget:setPosition(position, default_position)
    self.position = position
    self.default_position = default_position
    self:update()
end

function ButtonProgressWidget:onTapSelect(arg, gev)
    if gev == nil then
        self:circlePosition()
    end
end

function ButtonProgressWidget:circlePosition()
    if self.position then
        self.position = self.position+1
        if self.position > self.num_buttons then
            self.position = 1
        end
        self.callback(self.position)
        self:update()
    end
end

return ButtonProgressWidget
