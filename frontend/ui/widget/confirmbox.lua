local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ButtonTable = require("ui/widget/buttontable")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Device = require("ui/device")
local Geom = require("ui/geometry")
local Input = require("ui/input")
local Screen = require("ui/screen")
local Font = require("ui/font")
local DEBUG = require("dbg")
local _ = require("gettext")

-- screen

--[[
Widget that shows a message and OK/Cancel buttons
]]
local ConfirmBox = InputContainer:new{
    text = _("no text"),
    face = Font:getFace("infofont", 25),
    ok_text = _("OK"),
    cancel_text = _("Cancel"),
    ok_callback = function() end,
    cancel_callback = function() end,
    margin = 5,
    padding = 5,
}

function ConfirmBox:init()
    local content = HorizontalGroup:new{
        align = "center",
        ImageWidget:new{
            file = "resources/info-i.png"
        },
        HorizontalSpan:new{ width = 10 },
        TextBoxWidget:new{
            text = self.text,
            face = self.face,
            width = Screen:getWidth()*2/3,
        }
    }
    local button_table = ButtonTable:new{
        width = content:getSize().w,
        button_font_face = "cfont",
        button_font_size = 20,
        buttons = {
            {
                {
                    text = self.cancel_text,
                    callback = function()
                        self.cancel_callback()
                        UIManager:close(self)
                    end,
                },
                {
                    text = self.ok_text,
                    callback = function()
                        self.ok_callback()
                        UIManager:close(self)
                    end,
                },
            },
        },
        zero_sep = true,
        show_parent = self,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            background = 0,
            margin = self.margin,
            padding = self.padding,
            VerticalGroup:new{
                align = "left",
                content,
                button_table,
            }
        }
    }

end

function ConfirmBox:onClose()
    UIManager:close(self)
    return true
end

function ConfirmBox:onSelect()
    DEBUG("selected:", self.selected.x)
    if self.selected.x == 1 then
        self:ok_callback()
    else
        self:cancel_callback()
    end
    UIManager:close(self)
    return true
end

return ConfirmBox
