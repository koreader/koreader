--[[--
This widget displays with two text fields
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = require("device").screen

local DobleInputDialog = InputDialog:extend{
--    input1_desc = "",
--    input1_text = "",
--    input1_hint = "",
--    input1_type = "",
--    input2_desc = "",
--    input2_text = "",
--    input2_hint = "",
--    input2_type = "",
}

function DobleInputDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    self.input1 = InputText:new{
        text = self.input1_text,
        hint = self.input1_hint,
        input_type = self.input1_type,
        face = self.input_face,
        width = math.floor(self.width * 0.9),
        text_type = self.input1_type or "text",
        focused = true,
        scroll = false,
        parent = self,
    }

    self.input2 = InputText:new{
        text = self.input2_text,
        hint = self.input2_hint,
        input_type = self.input2_type,
        face = self.input_face,
        width = math.floor(self.width * 0.9),
        text_type = self.input2_type or "text",
        focused = false,
        scroll = false,
        parent = self,
    }

    self.description1 = FrameContainer:new{
        bordersize = 0,
        TextBoxWidget:new{
            text = self.input1_desc,
            face = self.description_face,
--            width = text_dialog.width - 2*text_dialog.desc_padding - 2*text_dialog.desc_margin,
        }
    }

    self.description2 = FrameContainer:new{
        bordersize = 0,
        TextBoxWidget:new{
            text = self.input2_desc,
            face = self.description_face,
--            width = text_dialog.width - 2*text_dialog.desc_padding - 2*text_dialog.desc_margin,
        }
    }

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            self.title_widget,
            self.title_bar,
            -- description 1
            LeftContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.description1:getSize().h,
                },
                self.description1,
            },
            -- input 1
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.input1:getSize().h,
                },
                self.input1,
            },
            -- description 2
            LeftContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.description2:getSize().h,
                },
                self.description2,
            },
            -- input 2
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = self.input2:getSize().h,
                },
                self.input2,
            },
            VerticalSpan:new{ width = self.desc_margin + self.desc_padding },
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

    self._input_widget = self.input1

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        self.dialog_frame,
    }
end

function DobleInputDialog:getInputText()
    local input1_ret = self.input1:getText()
    local input2_ret = self.input2:getText()
    return input1_ret, input2_ret
end

function DobleInputDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self._input_widget:unfocus()
    self._input_widget:onCloseKeyboard()
    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
    UIManager:setDirty(self, "ui")
end

return DobleInputDialog

