--[[--
Widget for taking user input.

Example:

    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = "default value",
        input_hint = "hint text",
        input_type = "string",
        description = "Some more description",
        -- text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(sample_input)
                    end,
                },
                {
                    text = _("Save"),
                    -- button with is_enter_default set to true will be
                    -- triggered after user press the enter key from keyboard
                    is_enter_default = true,
                    callback = function()
                        print('Got user input as raw text:', sample_input:getInputText())
                        print('Got user input as value:', sample_input:getInputValue())
                    end,
                },
            }
        },
    }
    UIManager:show(sample_input)
    sample_input:onShowKeyboard()

To get a full screen text editor, use:
    fullscreen = true, -- no need to provide any height and width
    condensed = true,
    allow_newline = true,
    cursor_at_end = false,
    -- and one of these:
    add_scroll_buttons = true,
    add_nav_bar = true,

If it would take the user more than half a minute to recover from a mistake,
a "Cancel" button <em>must</em> be added to the dialog. The cancellation button
should be kept on the left and the button executing the action on the right.

It is strongly recommended to use a text describing the action to be
executed, as demonstrated in the example above. If the resulting phrase would be
longer than three words it should just read "OK".

]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RenderText = require("ui/rendertext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local InputDialog = InputContainer:new{
    is_always_active = true,
    title = "",
    input = "",
    input_hint = "",
    description = nil,
    buttons = nil,
    input_type = nil,
    enter_callback = nil,
    allow_newline = false, -- allow entering new lines (this disables any enter_callback)
    cursor_at_end = true, -- starts with cursor at end of text, ready for appending
    fullscreen = false, -- adjust to full screen minus keyboard
    condensed = false, -- true will prevent adding air and balance between elements
    add_scroll_buttons = false, -- add scroll Up/Down buttons to first row of buttons
    add_nav_bar = false, -- append a row of page navigation buttons
    -- note that the text widget can be scrolled with Swipe North/South even when no button

    -- movable = true, -- set to false if movable gestures conflicts with subwidgets gestures
    -- for now, too much conflicts between InputText and MovableContainer, and
    -- there's the keyboard to exclude from move area (the InputDialog could
    -- be moved under the keyboard, and the user would be locked)
    movable = false,

    width = nil,

    text_width = nil,
    text_height = nil,

    title_face = Font:getFace("x_smalltfont"),
    description_face = Font:getFace("x_smallinfofont"),
    input_face = Font:getFace("x_smallinfofont"),

    title_padding = Size.padding.default,
    title_margin = Size.margin.title,
    desc_padding = Size.padding.default, -- Use the same as title for their
    desc_margin = Size.margin.title,     -- texts to be visually aligned
    input_padding = Size.padding.default,
    input_margin = Size.margin.default,
    button_padding = Size.padding.default,
    border_size = Size.border.window,
}

function InputDialog:init()
    if self.fullscreen then
        self.movable = false
        self.border_size = 0
        self.width = Screen:getWidth() - 2*self.border_size
    else
        self.width = self.width or Screen:getWidth() * 0.8
    end
    if self.condensed then
        self.text_width = self.width - 2*(self.border_size + self.input_padding + self.input_margin)
    else
        self.text_width = self.text_width or self.width * 0.9
    end

    -- Title & description
    local title_width = RenderText:sizeUtf8Text(0, self.width,
            self.title_face, self.title, true).x
    if title_width > self.width then
        local indicator = "  >> "
        local indicator_w = RenderText:sizeUtf8Text(0, self.width,
                self.title_face, indicator, true).x
        self.title = RenderText:getSubTextByWidth(self.title, self.title_face,
                self.width - indicator_w, true) .. indicator
    end
    self.title = FrameContainer:new{
        padding = self.title_padding,
        margin = self.title_margin,
        bordersize = 0,
        TextWidget:new{
            text = self.title,
            face = self.title_face,
            width = self.width,
        }
    }
    self.title_bar = LineWidget:new{
        dimen = Geom:new{
            w = self.width,
            h = Size.line.thick,
        }
    }
    if self.description then
        self.description_widget = FrameContainer:new{
            padding = self.desc_padding,
            margin = self.desc_margin,
            bordersize = 0,
            TextBoxWidget:new{
                text = self.description,
                face = self.description_face,
                width = self.width - 2*self.desc_padding - 2*self.desc_margin,
            }
        }
    else
        self.description_widget = VerticalSpan:new{ width = 0 }
    end

    -- Vertical spaces added before and after InputText
    -- (these will be adjusted later to center the input text if needed)
    local vspan_before_input_text = VerticalSpan:new{ width = 0 }
    local vspan_after_input_text = VerticalSpan:new{ width = 0 }
    -- We add the same vertical space used under description after the input widget
    -- (can be disabled by setting condensed=true)
    if not self.condensed then
        local desc_pad_height = self.desc_margin + self.desc_padding
        if self.description then
            vspan_before_input_text.width = 0 -- already provided by description_widget
            vspan_after_input_text.width = desc_pad_height
        else
            vspan_before_input_text.width = desc_pad_height
            vspan_after_input_text.width = desc_pad_height
        end
    end

    -- Buttons
    if self.add_nav_bar then
        if not self.buttons then
            self.buttons = {}
        end
        local nav_bar = {}
        table.insert(self.buttons, nav_bar)
        table.insert(nav_bar, {
            text = "⇱",
            callback = function()
                self._input_widget:scrollToTop()
            end,
        })
        table.insert(nav_bar, {
            text = "⇲",
            callback = function()
                self._input_widget:scrollToBottom()
            end,
        })
        table.insert(nav_bar, {
            text = "△",
            callback = function()
                self._input_widget:scrollUp()
            end,
        })
        table.insert(nav_bar, {
            text = "▽",
            callback = function()
                self._input_widget:scrollDown()
            end,
        })
    elseif self.add_scroll_buttons then
        if not self.buttons then
            self.buttons = {{}}
        end
        -- Add them to the end of first row
        table.insert(self.buttons[1], {
            text = "△",
            callback = function()
                self._input_widget:scrollUp()
            end,
        })
        table.insert(self.buttons[1], {
            text = "▽",
            callback = function()
                self._input_widget:scrollDown()
            end,
        })
    end
    self.button_table = ButtonTable:new{
        width = self.width - 2*self.button_padding,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }
    local buttons_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.width,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    }

    -- InputText
    if not self.text_height or self.fullscreen then
        -- We need to find the best height to avoid screen overflow
        -- Create a dummy input widget to get some metrics
        local input_widget = InputText:new{
            text = self.fullscreen and "-" or self.input,
            face = self.input_face,
            width = self.text_width,
            padding = self.input_padding,
            margin = self.input_margin,
        }
        local text_height = input_widget:getTextHeight()
        local line_height = input_widget:getLineHeight()
        local input_pad_height = input_widget:getSize().h - text_height
        local keyboard_height = input_widget:getKeyboardDimen().h
        input_widget:free()
        -- Find out available height
        local available_height = Screen:getHeight()
                                    - 2*self.border_size
                                    - self.title:getSize().h
                                    - self.title_bar:getSize().h
                                    - self.description_widget:getSize().h
                                    - vspan_before_input_text:getSize().h
                                    - input_pad_height
                                    - vspan_after_input_text:getSize().h
                                    - buttons_container:getSize().h
                                    - keyboard_height
        if self.fullscreen or text_height > available_height then
            -- Don't leave unusable space in the text widget, as the user could think
            -- it's an empty line: move that space in pads after and below (for centering)
            self.text_height = math.floor(available_height / line_height) * line_height
            local pad_height = available_height - self.text_height
            local pad_before = math.ceil(pad_height / 2)
            local pad_after = pad_height - pad_before
            vspan_before_input_text.width = vspan_before_input_text.width + pad_before
            vspan_after_input_text.width = vspan_after_input_text.width + pad_after
            self.cursor_at_end = false -- stay at start if overflowed
        else
            -- Don't leave unusable space in the text widget
            self.text_height = text_height
        end
    end
    self._input_widget = InputText:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        width = self.text_width,
        height = self.text_height or nil,
        padding = self.input_padding,
        margin = self.input_margin,
        input_type = self.input_type,
        text_type = self.text_type,
        enter_callback = self.enter_callback or function()
            for _,btn_row in ipairs(self.buttons) do
                for _,btn in ipairs(btn_row) do
                    if btn.is_enter_default then
                        btn.callback()
                        return
                    end
                end
            end
        end,
        scroll = true,
        cursor_at_end = self.cursor_at_end,
        parent = self,
    }
    if self.allow_newline then -- remove any enter_callback
        self._input_widget.enter_callback = nil
    end
    if Device:hasKeys() then
        --little hack to piggyback on the layout of the button_table to handle the new InputText
        table.insert(self.button_table.layout, 1, {self._input_widget})
    end

    -- Final widget
    self.dialog_frame = FrameContainer:new{
        radius = self.fullscreen and 0 or Size.radius.window,
        padding = 0,
        margin = 0,
        bordersize = self.border_size,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title,
            self.title_bar,
            self.description_widget,
            vspan_before_input_text,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self._input_widget:getSize().h,
                },
                self._input_widget,
            },
            vspan_after_input_text,
            buttons_container,
        }
    }
    local frame = self.dialog_frame
    if self.movable then
        frame = MovableContainer:new{
            self.dialog_frame,
        }
    end
    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        frame
    }
end

function InputDialog:getInputText()
    return self._input_widget:getText()
end

function InputDialog:getInputValue()
    local text = self:getInputText()
    if self.input_type == "number" then
        return tonumber(text)
    else
        return text
    end
end

function InputDialog:setInputText(text)
    self._input_widget:setText(text)
end

function InputDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dialog_frame.dimen
    end)
end

function InputDialog:onCloseWidget()
    self:onClose()
    UIManager:setDirty(nil, function()
        return "partial", self.dialog_frame.dimen
    end)
end

function InputDialog:onShowKeyboard()
    self._input_widget:onShowKeyboard()
end

function InputDialog:onClose()
    self._input_widget:onCloseKeyboard()
end

return InputDialog
