local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local input_field, input_description

local MultiInputDialog = InputDialog:extend{
    field = {},
    field_hint = {},
    fields = {},
    description_padding = Size.padding.default,
    description_margin = Size.margin.small,
}

function MultiInputDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    local VerticalGroupData = VerticalGroup:new{
        align = "left",
        self.title,
        self.title_bar,
    }

    input_field = {}
    input_description = {}
    local k = 0
    for i, field in ipairs(self.fields) do
        k = k + 1
        input_field[k] = InputText:new{
            text = field.text or "",
            hint = field.hint or "",
            input_type = field.input_type or "string",
            face = self.input_face,
            width = self.width * 0.9,
            focused = k == 1 and true or false,
            scroll = false,
            parent = self,
        }
        if field.description then
            input_description[k] = FrameContainer:new{
                padding = self.description_padding,
                margin = self.description_margin,
                bordersize = 0,
                TextBoxWidget:new{
                    text = field.description,
                    face = Font:getFace("x_smallinfofont"),
                    width = self.width * 0.9,
                }
            }
            table.insert(VerticalGroupData, CenterContainer:new{
                dimen = Geom:new{
                    w = self.title_bar:getSize().w,
                    h = input_description[k]:getSize().h ,
                },
                input_description[k],
            })
        end
        table.insert(VerticalGroupData, CenterContainer:new{
            dimen = Geom:new{
                w = self.title_bar:getSize().w,
                h = input_field[k]:getSize().h,
            },
            input_field[k],
        })
    end

    -- Add same vertical space after than before InputText
    table.insert(VerticalGroupData,CenterContainer:new{
        dimen = Geom:new{
            w = self.title_bar:getSize().w,
            h = self.description_padding + self.description_margin,
        },
        VerticalSpan:new{ width = self.description_padding + self.description_margin },
    })
    -- buttons
    table.insert(VerticalGroupData,CenterContainer:new{
        dimen = Geom:new{
            w = self.title_bar:getSize().w,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    })

    self.dialog_frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroupData,
    }

    self._input_widget = input_field[1]

    self[1] = CenterContainer:new{
        dimen = Geom:new{
            w = Screen:getWidth(),
            h = Screen:getHeight() - self._input_widget:getKeyboardDimen().h,
        },
        self.dialog_frame,
    }
    UIManager:setDirty("all", "full")
end

function MultiInputDialog:getFields()
    local fields = {}
    for i=1, #input_field do
        table.insert(fields, input_field[i].text)
    end
    return fields
end

function MultiInputDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self._input_widget:unfocus()
    self._input_widget:onCloseKeyboard()

    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()

    UIManager:show(self)
end

return MultiInputDialog

