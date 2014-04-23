local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ButtonTable = require("ui/widget/buttontable")
local TextWidget = require("ui/widget/textwidget")
local LineWidget = require("ui/widget/linewidget")
local InputText = require("ui/widget/inputtext")
local VerticalGroup = require("ui/widget/verticalgroup")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Screen = require("ui/screen")

local InputDialog = InputContainer:new{
    title = "",
    input = "",
    input_hint = "",
    buttons = nil,
    input_type = nil,
    enter_callback = nil,

    width = nil,
    height = nil,

    title_face = Font:getFace("tfont", 22),
    input_face = Font:getFace("cfont", 20),

    title_padding = Screen:scaleByDPI(5),
    title_margin = Screen:scaleByDPI(2),
    input_padding = Screen:scaleByDPI(10),
    input_margin = Screen:scaleByDPI(10),
    button_padding = Screen:scaleByDPI(14),
}

function InputDialog:init()
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
    self.input = InputText:new{
        text = self.input,
        hint = self.input_hint,
        face = self.input_face,
        width = self.width * 0.9,
        input_type = self.input_type,
        enter_callback = self.enter_callback,
        scroll = false,
        parent = self,
    }
    self.button_table = ButtonTable:new{
        width = self.width,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = self.buttons,
        zero_sep = true,
    }
    self.title_bar = LineWidget:new{
        --background = 8,
        dimen = Geom:new{
            w = self.button_table:getSize().w + self.button_padding,
            h = Screen:scaleByDPI(2),
        }
    }

    self.dialog_frame = FrameContainer:new{
        radius = 8,
        bordersize = 3,
        padding = 0,
        margin = 0,
        background = 0,
        VerticalGroup:new{
            align = "left",
            self.title,
            self.title_bar,
            -- input
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.input:getSize().h,
                },
                self.input,
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
            h = Screen:getHeight() - self.input:getKeyboardDimen().h,
        },
        self.dialog_frame,
    }
    UIManager.repaint_all = true
    UIManager.full_refresh = true
end

function InputDialog:onShowKeyboard()
    self.input:onShowKeyboard()
end

function InputDialog:getInputText()
    return self.input:getText()
end

function InputDialog:onClose()
    self.input:onCloseKeyboard()
end

return InputDialog
