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
local Util = require("ffi/util")

local InfoMessage = require("ui/widget/infomessage")
local input_field

local MultiInputDialog = InputDialog:extend{
    field = {},
    field_hint = {},
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
    for i,j in Util.orderedPairs(self.field) do
        k = k + 1
        input_field[k] = InputText:new{
            text = tostring(i) .. " = " .. tostring(j),
            hint = tostring(self.field_hint[j]) or "",
            face = self.input_face,
            width = self.width * 0.9,
            focused = true,
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
        background = 0,
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

function MultiInputDialog:getCredential()
    local field = {}
    local dummy
    for i=1,#input_field do
        dummy = input_field[i].text
        field[dummy:match("^[^= ]+")] = dummy:match("[^= ]+$")
    end

    return field
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

