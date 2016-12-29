--[[--
Widget for taking user input.

Example:

    local _ = require("gettext")
    local UIManager = require("ui/uimanager")
    local sample_input
    sample_input = InputDialog:new{
        title = _("Dialog title"),
        input = "default value",
        input_hint = "hint text",
        input_type = "string",
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
    sample_input:onShowKeyboard()
    UIManager:show(sample_input)

]]

local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonTable = require("ui/widget/buttontable")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local InputText = require("ui/widget/inputtext")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Geom = require("ui/geometry")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")

local InputDialog = InputContainer:new{
    title = "",
    input = "",
    input_hint = "",
    buttons = nil,
    input_type = nil,
    enter_callback = nil,

    width = nil,
    height = nil,

    text_width = nil,
    text_height = nil,

    title_face = Font:getFace("tfont", 22),
    input_face = Font:getFace("cfont", 20),

    title_padding = Screen:scaleBySize(5),
    title_margin = Screen:scaleBySize(2),
    input_padding = Screen:scaleBySize(10),
    input_margin = Screen:scaleBySize(10),
    button_padding = Screen:scaleBySize(14),
}

function InputDialog:init()
    self.width = self.width or Screen:getWidth() * 0.8
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

    self._input_widget = InputText:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        width = self.text_width or self.width * 0.9,
        height = self.text_height or nil,
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
        scroll = false,
        parent = self,
    }
    self.button_table = ButtonTable:new{
        width = self.width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = self.buttons,
        zero_sep = true,
        show_parent = self,
    }
    self.title_bar = LineWidget:new{
        dimen = Geom:new{
            w = self.button_table:getSize().w + self.button_padding,
            h = Screen:scaleBySize(2),
        }
    }

    self.dialog_frame = FrameContainer:new{
        radius = 8,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title,
            self.title_bar,
            -- input
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self._input_widget:getSize().h,
                },
                self._input_widget,
            },
            -- buttons
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            }
        }
    }

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        self.dialog_frame,
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
