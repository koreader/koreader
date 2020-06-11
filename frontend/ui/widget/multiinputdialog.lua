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
    fields = {},
    description_padding = Size.padding.default,
    description_margin = Size.margin.small,
}

function MultiInputDialog:init()
    -- init title and buttons in base class
    InputDialog.init(self)
    local VerticalGroupData = VerticalGroup:new{
        align = "left",
        self.title_widget,
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
            text_type =  field.text_type,
            face = self.input_face,
            width = math.floor(self.width * 0.9),
            focused = k == 1 and true or false,
            scroll = false,
            parent = self,
            padding = field.padding or nil,
            margin = field.margin or nil,
            -- Allow these to be specified per field if needed
            alignment = field.alignment or self.alignment,
            justified = field.justified or self.justified,
            lang = field.lang or self.lang,
            para_direction_rtl = field.para_direction_rtl or self.para_direction_rtl,
            auto_para_direction = field.auto_para_direction or self.auto_para_direction,
            alignment_strict = field.alignment_strict or self.alignment_strict,
        }
        if Device:hasDPad() then
            -- little hack to piggyback on the layout of the button_table to handle the new InputText
            table.insert(self.button_table.layout, #self.button_table.layout, {input_field[k]})
        end
        if field.description then
            input_description[k] = FrameContainer:new{
                padding = self.description_padding,
                margin = self.description_margin,
                bordersize = 0,
                TextBoxWidget:new{
                    text = field.description,
                    face = Font:getFace("x_smallinfofont"),
                    width = math.floor(self.width * 0.9),
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

    if Device:hasDPad() then
        -- remove the not needed hack in inputdialog
        table.remove(self.button_table.layout, 1)
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
    UIManager:setDirty(self, "ui")
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
    UIManager:setDirty(nil, function()
        return "ui", self.dialog_frame.dimen
    end)

    -- focus new inputbox
    self._input_widget = inputbox
    self._input_widget:focus()
    self._input_widget:onShowKeyboard()
end

return MultiInputDialog

