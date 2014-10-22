local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Screen = require("ui/screen")
local DEBUG = require("dbg")
local _ = require("gettext")
local util = require("ffi/util")
local Blitbuffer = require("ffi/blitbuffer")

local InfoMessage = require("ui/widget/infomessage")
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

    self.input = input_field[1]

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

function MultiInputDialog:getFields()
    local fields = {}
    for i=1, #input_field do
        table.insert(fields, input_field[i].text)
    end
    return fields
end

function MultiInputDialog:onSwitchFocus(inputbox)
    -- unfocus current inputbox
    self.input:unfocus()
    self.input:onCloseKeyboard()

    -- focus new inputbox
    self.input = inputbox
    self.input:focus()
    self.input:onShowKeyboard()

    UIManager:show(self)
end

return MultiInputDialog

