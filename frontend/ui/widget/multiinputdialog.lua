local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

local input_field

local MultiInputDialog = InputDialog:extend{
    field = {},
    field_hint = {},
    fields = {},
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
        table.insert(VerticalGroupData,CenterContainer:new{
            dimen = Geom:new{
                w = self.title_bar:getSize().w,
                h = input_field[k]:getSize().h,
            },
            input_field[k],
        })
    end

    -- buttons
    table.insert(VerticalGroupData,CenterContainer:new{
        dimen = Geom:new{
            w = self.title_bar:getSize().w,
            h = self.button_table:getSize().h,
        },
        self.button_table,
    })

    self.dialog_frame = FrameContainer:new{
        radius = 8,
        bordersize = 3,
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

